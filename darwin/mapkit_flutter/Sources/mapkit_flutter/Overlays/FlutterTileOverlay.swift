import Foundation
import ImageIO
import MapKit

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

final class FlutterTileOverlay: MKTileOverlay, @unchecked Sendable {
    let id: String
    var alpha: CGFloat = 1.0
    var overlayLevel: MKOverlayLevel = .aboveRoads

    init(fromPlatform data: PlatformTileOverlay) {
        self.id = data.id
        super.init(urlTemplate: data.urlTemplate)
        self.tileSize = CGSize(width: CGFloat(data.tileSize), height: CGFloat(data.tileSize))
        self.minimumZ = Int(data.minimumZ)
        self.maximumZ = Int(data.maximumZ)
        self.canReplaceMapContent = data.canReplaceMapContent
        self.alpha = CGFloat(data.alpha)
        self.overlayLevel = data.level.mkLevel
    }
}

/// One tile a snapshot needs, and the square of the map it covers. `mapRect` is
/// unwrapped (it can lie past the antimeridian); `path.x` is wrapped for the URL.
struct TileRequest: Sendable {
    let overlay: FlutterTileOverlay
    let path: MKTileOverlayPath
    let mapRect: MKMapRect

    var name: String { "\(path.z)/\(path.x)/\(path.y)" }

    /// The tiles' bytes in request order, or the first failure, or a timeout
    /// after `deadline` seconds. `loadTile` can't be cancelled and, against a
    /// silent server, can go minutes without calling back, so nothing here waits
    /// on the tiles still outstanding once the outcome is known.
    nonisolated static func load(_ requests: [TileRequest], deadline: TimeInterval) async throws -> [Data] {
        guard !requests.isEmpty else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            TileBatch(requests: requests, continuation: continuation).start(deadline: deadline)
        }
    }
}

/// One snapshot's tile fetches, resolved exactly once. `loadTile` calls back on
/// its own queues, and may still do so after the outcome is known; by then the
/// batch holds no bytes and no timer keeps it alive.
final class TileBatch: @unchecked Sendable {
    private let lock = NSLock()
    private let requests: [TileRequest]
    private var continuation: CheckedContinuation<[Data], Error>?
    private var deadlineTimer: DispatchSourceTimer?
    private var loaded: [Data?]
    private var remaining: Int

    init(requests: [TileRequest], continuation: CheckedContinuation<[Data], Error>) {
        self.requests = requests
        self.continuation = continuation
        self.loaded = Array(repeating: nil, count: requests.count)
        self.remaining = requests.count
    }

    /// A timer source, not `asyncAfter`: a scheduled block stays retained, batch
    /// and bytes with it, until its time comes even when cancelled.
    func start(deadline: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + deadline)
        timer.setEventHandler { [self] in timeOut(after: deadline) }
        lock.withLock { deadlineTimer = timer }
        for (index, request) in requests.enumerated() {
            request.overlay.loadTile(at: request.path) { [self] data, error in
                finish(index, data: data, error: error)
            }
        }
        timer.resume()
    }

    private func finish(_ index: Int, data: Data?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil else { return }
        guard let data else {
            let request = requests[index]
            resolve(.failure(mapKitError(
                .snapshotFailed,
                "Tile overlay \"\(request.overlay.id)\" could not load tile \(request.name): "
                    + (error?.localizedDescription ?? "no data"))))
            return
        }
        guard loaded[index] == nil else { return }
        loaded[index] = data
        remaining -= 1
        if remaining == 0 {
            resolve(.success(loaded.compactMap { $0 }))
        }
    }

    private func timeOut(after deadline: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard continuation != nil else { return }
        let waiting = zip(requests, loaded).first { $0.1 == nil }?.0
        resolve(.failure(mapKitError(
            .snapshotFailed,
            "Tile overlay \"\(waiting?.overlay.id ?? "")\" did not deliver tile \(waiting?.name ?? "") within "
                + "\(Int(deadline)) seconds; \(remaining) of \(requests.count) tiles are still loading.")))
    }

    /// Tile bytes still held, for tests of what an outcome lets go of.
    var heldBytes: Int {
        lock.withLock { loaded.reduce(0) { $0 + ($1?.count ?? 0) } }
    }

    private func resolve(_ result: Result<[Data], Error>) {
        continuation?.resume(with: result)
        continuation = nil
        deadlineTimer?.cancel()
        deadlineTimer = nil
        loaded = []
    }
}

/// What the compositor needs from tile overlays, fetched and decoded.
struct SnapshotTiles {
    struct Tile {
        let mapRect: MKMapRect
        let image: CGImage
    }

    let viewport: MapKitViewHost.TileViewport
    let replacesBaseMap: Bool
    private let byOverlay: [ObjectIdentifier: [Tile]]

    init(
        viewport: MapKitViewHost.TileViewport = MapKitViewHost.TileViewport(
            coverage: .null, center: CLLocationCoordinate2D(), ground: [])
    ) {
        self.viewport = viewport
        replacesBaseMap = false
        byOverlay = [:]
    }

    /// `MKTileOverlay.loadTile` hands back an error page's body with no error,
    /// so bytes that aren't an image are a failed tile too.
    init(requests: [TileRequest], data: [Data], viewport: MapKitViewHost.TileViewport, replacesBaseMap: Bool) throws {
        var byOverlay: [ObjectIdentifier: [Tile]] = [:]
        for (request, bytes) in zip(requests, data) {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw mapKitError(
                    .snapshotFailed,
                    "Tile overlay \"\(request.overlay.id)\" returned tile \(request.name) "
                        + "that is not an image (\(bytes.count) bytes).")
            }
            byOverlay[ObjectIdentifier(request.overlay), default: []].append(
                Tile(mapRect: request.mapRect, image: image))
        }
        self.viewport = viewport
        self.replacesBaseMap = replacesBaseMap
        self.byOverlay = byOverlay
    }

    func tiles(of overlay: FlutterTileOverlay) -> [Tile] {
        byOverlay[ObjectIdentifier(overlay)] ?? []
    }
}

extension FlutterTileOverlay {
    /// The tiles covering the viewport's ground, each at the zoom closest to its
    /// own on-screen size, so a steep view takes few, coarse tiles toward the
    /// horizon where one zoom for the whole view would take thousands or more.
    /// Past `maximumZ` the highest tiles get upscaled; ground a tile below
    /// `minimumZ` would cover has no data, so there is nothing to fetch or draw.
    /// Throws as soon as more than `limit` tiles are needed, before building them.
    func tileRequests(
        in viewport: MapKitViewHost.TileViewport, contentScale: CGFloat, limit: Int,
        project: (MKMapPoint) -> CGPoint
    ) throws -> [TileRequest] {
        var selection = TileSelection(
            overlay: self, ground: viewport.ground, contentScale: contentScale, limit: limit)
        let world = MKMapSize.world.width
        for x in Int((viewport.coverage.minX / world).rounded(.down))...Int((viewport.coverage.maxX / world).rounded(.down)) {
            try selection.visit(x: x, y: 0, z: 0, side: world, project: project)
        }
        return selection.requests
    }

    /// Composites as one layer, so `alpha` applies to the overlay as a whole.
    /// Edges aren't antialiased: neighbouring cells share theirs, and blending
    /// both would leave a seam.
    func draw(
        _ all: SnapshotTiles, of snapshot: MKMapSnapshotter.Snapshot, in context: CGContext, deepestSplit: Int
    ) throws {
        let tiles = all.tiles(of: self)
        guard !tiles.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(alpha)
        context.setShouldAntialias(false)
        context.interpolationQuality = .high
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        let viewSize = snapshot.image.size
        var painter = TilePainter(
            viewport: all.viewport, context: context, deepestSplit: deepestSplit,
            patchBudget: TilePainter.patchBudget(forViewOf: viewSize)
        ) {
            snapshot.point(for: $0.coordinate)
        }
        for tile in tiles {
            try painter.paint(tile, covering: all.viewport.coverage)
        }
    }
}

/// The part of the convex `ground` inside `rect`: Sutherland–Hodgman against the
/// rect's four sides.
private func groundPatch(_ polygon: [MKMapPoint], in rect: MKMapRect) -> [MKMapPoint] {
    func side(
        _ points: [MKMapPoint], inside: (MKMapPoint) -> Bool, crossing: (MKMapPoint, MKMapPoint) -> MKMapPoint
    ) -> [MKMapPoint] {
        var kept: [MKMapPoint] = []
        for (index, point) in points.enumerated() {
            let previous = points[(index + points.count - 1) % points.count]
            if inside(point) != inside(previous) { kept.append(crossing(previous, point)) }
            if inside(point) { kept.append(point) }
        }
        return kept
    }
    func atX(_ x: Double) -> (MKMapPoint, MKMapPoint) -> MKMapPoint {
        { a, b in MKMapPoint(x: x, y: a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)) }
    }
    func atY(_ y: Double) -> (MKMapPoint, MKMapPoint) -> MKMapPoint {
        { a, b in MKMapPoint(x: a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y), y: y) }
    }
    var clipped = side(polygon, inside: { $0.x >= rect.minX }, crossing: atX(rect.minX))
    clipped = side(clipped, inside: { $0.x <= rect.maxX }, crossing: atX(rect.maxX))
    clipped = side(clipped, inside: { $0.y >= rect.minY }, crossing: atY(rect.minY))
    return side(clipped, inside: { $0.y <= rect.maxY }, crossing: atY(rect.maxY))
}

/// Walks the tile pyramid down from the whole world: a tile on the viewport's
/// ground splits until it would show at no more than its own size, give or take
/// the same factor as rounding the zoom to the nearest level.
private struct TileSelection {
    private static let largestDisplayedSize = 2.0.squareRoot()

    let overlay: FlutterTileOverlay
    let ground: [MKMapPoint]
    let contentScale: CGFloat
    let limit: Int
    private(set) var requests: [TileRequest] = []

    mutating func visit(x: Int, y: Int, z: Int, side: Double, project: (MKMapPoint) -> CGPoint) throws {
        let rect = MKMapRect(x: Double(x) * side, y: Double(y) * side, width: side, height: side)
        let onGround = groundPatch(ground, in: rect)
        guard onGround.count >= 3 else { return }
        let displayed = Self.pointsPerMapPoint(across: onGround, project: project) * side / Double(overlay.tileSize.width)
        let fitsItsSize = displayed <= Self.largestDisplayedSize
        if z < overlay.minimumZ && fitsItsSize { return }
        if z >= overlay.minimumZ && (fitsItsSize || z >= overlay.maximumZ) {
            guard requests.count < limit else {
                throw mapKitError(
                    .snapshotFailed,
                    "This view needs more than \(MapKitViewHost.tileLimit) tiles from its tile overlays, "
                        + "the most one snapshot may fetch. Fewer overlays or a larger tileSize need fewer.")
            }
            let tilesPerSide = 1 << z
            let wrapped = ((x % tilesPerSide) + tilesPerSide) % tilesPerSide
            requests.append(TileRequest(
                overlay: overlay,
                path: MKTileOverlayPath(x: wrapped, y: y, z: z, contentScaleFactor: contentScale),
                mapRect: rect))
            return
        }
        for (childY, childX) in [(y * 2, x * 2), (y * 2, x * 2 + 1), (y * 2 + 1, x * 2), (y * 2 + 1, x * 2 + 1)] {
            try visit(x: childX, y: childY, z: z + 1, side: side / 2, project: project)
        }
    }

    /// How large this patch of ground shows. Every vertex is ground the view
    /// shows, so unlike a step off a vertex, none can cross the horizon and project
    /// somewhere meaningless. Along its width a far patch shows nearly as large as
    /// a near one, while its depth all but vanishes: going by the width alone takes
    /// tens of times the tiles, by area alone softens the near ground, so this is
    /// their geometric mean.
    private static func pointsPerMapPoint(across polygon: [MKMapPoint], project: (MKMapPoint) -> CGPoint) -> Double {
        let projected = polygon.map(project)
        var widest = 0.0
        for first in polygon.indices {
            for second in polygon.indices where second > first {
                let distance = hypot(polygon[first].x - polygon[second].x, polygon[first].y - polygon[second].y)
                guard distance > 0 else { continue }
                let onScreen = hypot(projected[first].x - projected[second].x, projected[first].y - projected[second].y)
                widest = max(widest, Double(onScreen) / distance)
            }
        }
        let mapArea = area(polygon.map { ($0.x, $0.y) })
        guard mapArea > 0 else { return widest }
        return (widest * (area(projected.map { (Double($0.x), Double($0.y)) }) / mapArea).squareRoot()).squareRoot()
    }

    private static func area(_ polygon: [(x: Double, y: Double)]) -> Double {
        var doubled = 0.0
        for (index, point) in polygon.enumerated() {
            let next = polygon[(index + 1) % polygon.count]
            doubled += point.x * next.y - next.x * point.y
        }
        return abs(doubled) / 2
    }

}

/// Maps tile images through the snapshot's projection. A patch close enough to
/// affine draws as one transformed image; anything else splits: the closer a
/// coarse tile comes to a steep camera, the smaller the patches it needs. Only
/// the ground the view shows decides whether a patch matters, since a corner can
/// be behind the camera while the patch still shows ground. A patch MapKit
/// projects mirrored faces away from the view, as ground does where MapKit folds
/// it just short of the Mercator world's edge, and one that has shrunk below a
/// sixteenth of a point lies across such a fold or the horizon: neither has
/// anything to draw. Real views settle within about 22 splits and, per overlay,
/// 90,000 patches on a 2560 by 1440 point view. A projection that hasn't after
/// `deepestSplit` splits or `patchBudget` patches, a NaN one say, or one twisting
/// along a line, fails the snapshot instead of splitting on until the main actor
/// freezes.
struct TilePainter {
    /// Keeps a patch's corners on the same copy of the world as seen from the
    /// view's center.
    static let largestPatch = MKMapSize.world.width / 8
    /// How far, in points, the fourth corner may stray from an affine patch.
    static let affineTolerance: CGFloat = 0.5
    /// Patches whose corners all lie this close, in points, are below any pixel.
    static let smallestPatch: CGFloat = 1.0 / 16

    /// About five times the patches a view of this many points has needed.
    static func patchBudget(forViewOf size: CGSize) -> Int {
        50_000 + Int(size.width * size.height / 8)
    }

    let context: CGContext
    let ground: [MKMapPoint]
    let deepestSplit: Int
    let project: (MKMapPoint) -> CGPoint
    let patchBudget: Int
    private var patchesLeft: Int
    /// The turning direction of an unmirrored patch: it differs between
    /// top-left (iOS) and bottom-left (macOS) point spaces.
    let handedness: CGFloat

    init(
        viewport: MapKitViewHost.TileViewport, context: CGContext, deepestSplit: Int, patchBudget: Int,
        project: @escaping (MKMapPoint) -> CGPoint
    ) {
        self.patchBudget = patchBudget
        self.patchesLeft = patchBudget
        self.context = context
        self.ground = viewport.ground
        self.deepestSplit = deepestSplit
        self.project = project
        let center = MKMapPoint(viewport.center)
        let step = MKMapSize.world.width / Double(1 << 20)
        let origin = project(center)
        let east = project(MKMapPoint(x: center.x + step, y: center.y))
        let south = project(MKMapPoint(x: center.x, y: center.y + step))
        self.handedness = Self.turn(origin, east, south) < 0 ? -1 : 1
    }

    mutating func paint(_ tile: SnapshotTiles.Tile, covering coverage: MKMapRect) throws {
        let visible = tile.mapRect.intersection(coverage)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
        let columns = max(1, Int((visible.width / Self.largestPatch).rounded(.up)))
        let rows = max(1, Int((visible.height / Self.largestPatch).rounded(.up)))
        let width = visible.width / Double(columns)
        let height = visible.height / Double(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                try paintPatch(
                    MKMapRect(
                        x: visible.minX + Double(column) * width, y: visible.minY + Double(row) * height,
                        width: width, height: height),
                    of: tile, splitsLeft: deepestSplit)
            }
        }
    }

    private func project(_ x: Double, _ y: Double) -> CGPoint {
        project(MKMapPoint(x: x, y: y))
    }

    private func unsettled() -> MapKitHostError {
        mapKitError(
            .snapshotFailed,
            "A tile overlay didn't settle into drawable patches within \(deepestSplit) splits and "
                + "\(patchBudget) patches; the snapshot's projection gave no usable shape for it.")
    }

    private static func turn(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
    }

    private mutating func paintPatch(_ rect: MKMapRect, of tile: SnapshotTiles.Tile, splitsLeft: Int) throws {
        patchesLeft -= 1
        guard patchesLeft > 0 else { throw unsettled() }
        guard groundPatch(ground, in: rect).count >= 3 else { return }
        let northWest = project(rect.minX, rect.minY)
        let northEast = project(rect.maxX, rect.minY)
        let southEast = project(rect.maxX, rect.maxY)
        let southWest = project(rect.minX, rect.maxY)
        let corners = [northWest, northEast, southEast, southWest]
        let turns = [
            Self.turn(northWest, northEast, southEast), Self.turn(northEast, southEast, southWest),
            Self.turn(southEast, southWest, northWest), Self.turn(southWest, northWest, northEast),
        ].map { $0 * handedness }
        let skew = hypot(
            southEast.x - (northEast.x + southWest.x - northWest.x),
            southEast.y - (northEast.y + southWest.y - northWest.y))
        if turns.allSatisfy({ $0 > 0 }), skew <= Self.affineTolerance {
            let quad = CGMutablePath()
            quad.addLines(between: corners)
            quad.closeSubpath()
            draw(tile, in: rect, clippedTo: quad, southWest: southWest, southEast: southEast, northWest: northWest)
            return
        }
        if turns.allSatisfy({ $0 < 0 }) { return }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        if let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max(),
           max(right - left, bottom - top) <= Self.smallestPatch {
            return
        }
        guard splitsLeft > 0 else { throw unsettled() }
        let (halfWidth, halfHeight) = (rect.width / 2, rect.height / 2)
        for (x, y) in [
            (rect.minX, rect.minY), (rect.minX + halfWidth, rect.minY),
            (rect.minX, rect.minY + halfHeight), (rect.minX + halfWidth, rect.minY + halfHeight),
        ] {
            try paintPatch(
                MKMapRect(x: x, y: y, width: halfWidth, height: halfHeight), of: tile, splitsLeft: splitsLeft - 1)
        }
    }

    /// Core Graphics draws an image into the unit square with its bottom-left
    /// at the origin: this maps u east and v north across the whole tile onto
    /// the patch's corners.
    private func draw(
        _ tile: SnapshotTiles.Tile, in rect: MKMapRect, clippedTo quad: CGPath,
        southWest: CGPoint, southEast: CGPoint, northWest: CGPoint
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(quad)
        context.clip()
        let widthInTiles = CGFloat(rect.width / tile.mapRect.width)
        let heightInTiles = CGFloat(rect.height / tile.mapRect.height)
        let uAtSouthWest = CGFloat((rect.minX - tile.mapRect.minX) / tile.mapRect.width)
        let vAtSouthWest = 1 - CGFloat((rect.maxY - tile.mapRect.minY) / tile.mapRect.height)
        let east = CGPoint(
            x: (southEast.x - southWest.x) / widthInTiles, y: (southEast.y - southWest.y) / widthInTiles)
        let north = CGPoint(
            x: (northWest.x - southWest.x) / heightInTiles, y: (northWest.y - southWest.y) / heightInTiles)
        context.concatenate(CGAffineTransform(
            a: east.x, b: east.y, c: north.x, d: north.y,
            tx: southWest.x - uAtSouthWest * east.x - vAtSouthWest * north.x,
            ty: southWest.y - uAtSouthWest * east.y - vAtSouthWest * north.y))
        context.draw(tile.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

import Foundation
import MapKit

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

/// Hosts one `MKMapView` platform view and implements the pigeon-generated
/// `MapKitHostApi`, mirroring `MKMapView`'s imperative surface
/// (setCamera/setRegion/setCenter, camera/region reads, conversions).
///
/// On iOS this object is itself the `FlutterPlatformView` (see the extension
/// below); on macOS the factory wraps it in a `MapKitContainerView` `NSView`.
@MainActor
public class MapKitViewHost: NSObject, @preconcurrency MapKitHostApi {
    #if os(iOS)
    var contentView: UIView
    #endif
    var mapView: FlutterMapView
    var flutterApi: MapKitFlutterApi
    private let hostMessenger: ConnectionTrackingMessenger
    var currentlySelectedAnnotation: String?
    var suppressSelectionCallbacksForAnnotationId: String?
    var tileOverlays: [String: FlutterTileOverlay] = [:]
    var annotationsById: [String: FlutterAnnotation] = [:]
    var polylinesById: [String: any FlutterOverlay] = [:]
    var polygonsById: [String: any FlutterOverlay] = [:]
    var circlesById: [String: any FlutterOverlay] = [:]
    private(set) var isDisposed = false

    public convenience init(withFrame frame: CGRect, withRegistrar registrar: FlutterPluginRegistrar, withId id: Int64) {
        #if os(iOS)
        self.init(messenger: registrar.messenger(), id: id)
        #elseif os(macOS)
        self.init(messenger: registrar.messenger, id: id)
        #endif
    }

    init(messenger: FlutterBinaryMessenger, id: Int64) {
        let suffix = "\(id)"
        self.hostMessenger = ConnectionTrackingMessenger(messenger)
        self.flutterApi = MapKitFlutterApi(binaryMessenger: messenger, messageChannelSuffix: suffix)
        self.mapView = FlutterMapView()

        #if os(iOS)
        // To stop the odd movement of the Apple logo.
        self.contentView = UIScrollView()
        self.contentView.addSubview(mapView)
        mapView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        #endif

        super.init()

        self.mapView.delegate = self
        self.mapView.flutterApi = self.flutterApi
        MapKitHostApiSetup.setUp(
            binaryMessenger: hostMessenger, api: WeakMapKitHostApi(self), messageChannelSuffix: suffix)
    }

    /// Dart's `dispose` never comes for a view unmounted before its creation
    /// finished. The engine then still drops the platform view, so the host
    /// goes away with it and takes its channel handlers along.
    deinit {
        hostMessenger.removeAllHandlers()
    }

    // MARK: - MapKitHostApi

    func initialize(params: PlatformMapViewCreationParams) throws {
        // Decode the annotations (icons can be invalid) before touching the
        // map, so a throw leaves it untouched.
        let annotations = try params.annotations.map(FlutterAnnotation.init(fromPlatform:))
        try self.mapView.apply(configuration: params.configuration)
        if let camera = params.initialCamera {
            self.mapView.move(.camera(camera.mkCamera), animated: false)
        }
        self.annotationsToAdd(annotations)
        self.applyOverlayUpdate(
            into: &self.polylinesById,
            adding: params.polylines.map { makeStyledPolyline(fromPlatform: $0) },
            changing: [],
            removing: [])
        self.applyOverlayUpdate(
            into: &self.polygonsById,
            adding: params.polygons.map(FlutterPolygon.init(fromPlatform:)),
            changing: [],
            removing: [])
        self.applyOverlayUpdate(
            into: &self.circlesById,
            adding: params.circles.map(FlutterCircle.init(fromPlatform:)),
            changing: [],
            removing: [])
    }

    func setCamera(camera: PlatformMapCamera, animated: Bool) throws {
        self.mapView.move(.camera(camera.mkCamera), animated: animated)
    }

    func setRegion(region: PlatformCoordinateRegion, animated: Bool) throws {
        self.mapView.move(.region(region.mkRegion), animated: animated)
    }

    func setCenter(coordinate: PlatformCoordinate, animated: Bool) throws {
        self.mapView.move(.center(coordinate.clCoordinate), animated: animated)
    }

    func getCamera() throws -> PlatformMapCamera? {
        guard self.mapView.hasLayout else { return nil }
        return self.mapView.currentPlatformCamera()
    }

    func getRegion() throws -> PlatformCoordinateRegion? {
        return self.mapView.currentPlatformRegion()
    }

    func convertToPoint(coordinate: PlatformCoordinate) throws -> PlatformPoint? {
        guard self.mapView.hasLayout else { return nil }
        let point = self.mapView.convert(coordinate.clCoordinate, toPointTo: self.mapView)
        return PlatformPoint(x: Double(point.x), y: Double(point.y))
    }

    func convertToCoordinate(point: PlatformPoint) throws -> PlatformCoordinate? {
        guard self.mapView.hasLayout else { return nil }
        let coordinate = self.mapView.convert(
            CGPoint(x: point.x, y: point.y),
            toCoordinateFrom: self.mapView
        )
        return .from(coordinate)
    }

    func updateAnnotations(toAdd: [PlatformAnnotation], toChange: [PlatformAnnotation], idsToRemove: [String]) throws {
        // Decode first: an invalid icon fails the whole update, never half of it.
        let added = try toAdd.map(FlutterAnnotation.init(fromPlatform:))
        let changed = try toChange.map(FlutterAnnotation.init(fromPlatform:))
        if !added.isEmpty { self.annotationsToAdd(added) }
        if !changed.isEmpty { self.annotationsToChange(changed) }
        if !idsToRemove.isEmpty { self.annotationsToRemove(idsToRemove) }
    }

    func updatePolylines(toAdd: [PlatformPolyline], toChange: [PlatformPolyline], idsToRemove: [String]) throws {
        self.applyOverlayUpdate(
            into: &self.polylinesById,
            adding: toAdd.map { makeStyledPolyline(fromPlatform: $0) },
            changing: toChange.map { makeStyledPolyline(fromPlatform: $0) },
            removing: idsToRemove)
    }

    func updatePolygons(toAdd: [PlatformPolygon], toChange: [PlatformPolygon], idsToRemove: [String]) throws {
        self.applyOverlayUpdate(
            into: &self.polygonsById,
            adding: toAdd.map(FlutterPolygon.init(fromPlatform:)),
            changing: toChange.map(FlutterPolygon.init(fromPlatform:)),
            removing: idsToRemove)
    }

    func updateCircles(toAdd: [PlatformCircle], toChange: [PlatformCircle], idsToRemove: [String]) throws {
        self.applyOverlayUpdate(
            into: &self.circlesById,
            adding: toAdd.map(FlutterCircle.init(fromPlatform:)),
            changing: toChange.map(FlutterCircle.init(fromPlatform:)),
            removing: idsToRemove)
    }

    func updateMapConfiguration(configuration: PlatformMapConfiguration) throws {
        try self.mapView.apply(configuration: configuration)
    }

    func selectAnnotation(annotationId: String) throws -> Bool {
        return self.selectAnnotation(with: annotationId)
    }

    func deselectAnnotation(annotationId: String) throws -> Bool {
        return self.deselectAnnotation(with: annotationId)
    }

    func isAnnotationSelected(annotationId: String) throws -> Bool {
        return self.isAnnotationSelected(with: annotationId)
    }

    func takeSnapshot(options: PlatformSnapshotOptions, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
        Task { @MainActor in
            do {
                guard let data = try await self.takeSnapshot(options: options) else {
                    completion(.failure(mapKitError(.snapshotFailed, "Snapshot produced no image data.")))
                    return
                }
                completion(.success(data))
            } catch let error as MapKitHostError {
                completion(.failure(error))
            } catch {
                completion(.failure(mapKitError(.snapshotFailed, error.localizedDescription)))
            }
        }
    }

    /// `false` only when no scene exists for the coordinate; a failed scene
    /// request or a missing presenter is an error, not "no scene".
    func openLookAround(coordinate: PlatformCoordinate, completion: @escaping (Result<Bool, Error>) -> Void) {
        #if os(iOS)
        let coord = coordinate.clCoordinate
        Task { @MainActor [weak self] in
            let sceneResult: Result<MKLookAroundScene?, Error>
            do {
                sceneResult = .success(try await Self.requestLookAroundScene(at: coord))
            } catch {
                sceneResult = .failure(error)
            }
            guard let self, !self.isDisposed else {
                completion(.failure(mapKitError(.lookAroundFailed, "The map view was disposed during Look Around.")))
                return
            }
            let scene: MKLookAroundScene?
            do {
                scene = try sceneResult.get()
            } catch {
                completion(.failure(mapKitError(.lookAroundFailed, error.localizedDescription)))
                return
            }
            guard let scene else {
                completion(.success(false))
                return
            }
            let vc = MKLookAroundViewController(scene: scene)
            guard let host = self.contentView.window?.rootViewController
                ?? UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first else {
                completion(.failure(mapKitError(.lookAroundFailed, "No view controller to present Look Around from.")))
                return
            }
            Self.present(
                vc, over: host, isDisposed: { [weak self = self] in self?.isDisposed ?? true }, completion: completion)
        }
        #elseif os(macOS)
        // MKLookAroundViewController exists on macOS 13+, but presenting it from the AppKit host isn't wired yet.
        completion(.failure(mapKitError(.unsupportedPlatform, "openLookAround is iOS only.")))
        #endif
    }

    #if os(iOS)
    /// UIKit drops a presentation it rejects (presenter off-window) without
    /// calling back, and postpones one made mid-transition without linking it;
    /// an accepted one links `vc` to its presenter synchronously. So a running
    /// transition is waited out first, and `completion` runs at most once.
    static func present(
        _ vc: UIViewController,
        over host: UIViewController,
        isDisposed: @escaping () -> Bool = { false },
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        if isDisposed() {
            completion(.failure(mapKitError(.lookAroundFailed, "The map view was disposed during Look Around.")))
            return
        }
        var presenter = host
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        if let transition = presenter.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in
                present(vc, over: host, isDisposed: isDisposed, completion: completion)
            }
            return
        }
        let report = ReportOnce(completion)
        presenter.present(vc, animated: true) {
            report(.success(true))
        }
        if vc.presentingViewController == nil {
            report(.failure(mapKitError(
                .lookAroundFailed, "UIKit rejected presenting Look Around from \(type(of: presenter)).")))
        }
    }

    /// Runs the scene request off the main actor and hands the result back
    /// with `sending`: older SDKs don't mark `MKLookAroundScene` Sendable, so
    /// awaiting `request.scene` directly from `@MainActor` fails to compile
    /// there. Region isolation proves the fresh scene is safe to move.
    private nonisolated static func requestLookAroundScene(
        at coordinate: CLLocationCoordinate2D
    ) async throws -> sending MKLookAroundScene? {
        try await MKLookAroundSceneRequest(coordinate: coordinate).scene
    }
    #endif

    func addTileOverlay(overlay overlayData: PlatformTileOverlay) throws {
        guard tileOverlays[overlayData.id] == nil else {
            throw mapKitError(.duplicateId, "A tile overlay with id \"\(overlayData.id)\" is already on the map.")
        }
        let overlay = FlutterTileOverlay(fromPlatform: overlayData)
        tileOverlays[overlay.id] = overlay
        self.mapView.addOverlay(overlay, level: overlay.overlayLevel)
    }

    func removeTileOverlay(tileOverlayId: String) throws -> Bool {
        guard let overlay = tileOverlays.removeValue(forKey: tileOverlayId) else { return false }
        self.mapView.removeOverlay(overlay)
        return true
    }

    func dispose() throws {
        isDisposed = true
        hostMessenger.removeAllHandlers()
        mapView.tearDown()
        annotationsById.removeAll()
        polylinesById.removeAll()
        polygonsById.removeAll()
        circlesById.removeAll()
        tileOverlays.removeAll()
        currentlySelectedAnnotation = nil
        suppressSelectionCallbacksForAnnotationId = nil
    }

    private func applyOverlayUpdate(
        into store: inout [String: any FlutterOverlay],
        adding: [any FlutterOverlay],
        changing: [any FlutterOverlay],
        removing: [String]
    ) {
        var overlaysToRemove: [MKOverlay] = []
        for id in removing {
            if let overlay = store.removeValue(forKey: id) {
                overlaysToRemove.append(overlay)
            }
        }
        for new in changing {
            if let old = store.removeValue(forKey: new.id) {
                overlaysToRemove.append(old)
            }
        }
        for new in adding {
            if let old = store.removeValue(forKey: new.id) {
                overlaysToRemove.append(old)
            }
        }

        if !overlaysToRemove.isEmpty {
            self.mapView.removeOverlays(overlaysToRemove)
        }

        for new in changing {
            store[new.id] = new
            self.mapView.addFlutterOverlay(new)
        }
        for new in adding {
            store[new.id] = new
            self.mapView.addFlutterOverlay(new)
        }
    }
}

extension MapKitViewHost: MKMapViewDelegate {
    // onIdle
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        if self.mapView.bounds.size != .zero {
            let camera = self.mapView.currentPlatformCamera()
            self.flutterApi.send { try await $0.onCameraMove(camera: camera) }
        }
        self.flutterApi.send { try await $0.onCameraIdle() }
    }

    public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        guard self.mapView.bounds.size != .zero else { return }
        let camera = self.mapView.currentPlatformCamera()
        flutterApi.send { try await $0.onCameraMove(camera: camera) }
    }

    // onMoveStarted
    public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        self.flutterApi.send { try await $0.onCameraMoveStarted() }
    }

    public func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        let platformMode = PlatformUserTrackingMode(mkMode: mode)
        self.flutterApi.send { try await $0.onUserTrackingModeChanged(mode: platformMode) }
    }

    public func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        let message = error.localizedDescription
        self.flutterApi.send { try await $0.onDidFailLoadingMap(error: message) }
    }

    public func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
        let message = error.localizedDescription
        self.flutterApi.send { try await $0.onDidFailToLocateUser(error: message) }
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tile = overlay as? FlutterTileOverlay {
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            renderer.alpha = tile.alpha
            return renderer
        }
        return (overlay as? any FlutterOverlay)?.makeRenderer() ?? MKOverlayRenderer()
    }
}

extension MapKitViewHost {
    /// How long a snapshot waits for its tiles, in seconds.
    /// `MKTileOverlay.loadTile` has no bound of its own worth relying on: against
    /// a silent or trickling server it was still quiet after 100 seconds, with
    /// the controller's queue blocked behind it.
    @MainActor static var tileLoadDeadline: TimeInterval = 60

    /// How many times a tile's patch may split while drawing; see `TilePainter`.
    /// Replaced by tests.
    @MainActor static var deepestPatchSplit = 40

    /// Tiles one snapshot may fetch, all overlays together. With each tile at the
    /// zoom its on-screen size asks for, one overlay stays well under this at any
    /// pitch; beyond it, fetching and decoding would hold the controller's queue
    /// for minutes and gigabytes of memory. A very small `tileSize` gets here, or
    /// about four overlays at the steepest camera in a 2560-point window.
    nonisolated static let tileLimit = 1024

    /// Everything a snapshot needs from the live map, as Sendable values: the
    /// snapshotter runs off the main actor and must never see `mapView` objects.
    struct SnapshotInput: Sendable {
        var region: MKCoordinateRegion
        var size: CGSize
        var displayScale: CGFloat
        var camera: PlatformMapCamera
        var configuration: PlatformMapConfiguration?
        var isDark: Bool
        var options: PlatformSnapshotOptions
    }

    func snapshotInput(_ options: PlatformSnapshotOptions) -> SnapshotInput {
        #if os(iOS)
        // Unspecified traits report displayScale == 0, which leaves the scale to MapKit.
        let displayScale = self.mapView.traitCollection.displayScale
        let isDark = self.mapView.traitCollection.userInterfaceStyle == .dark
        #elseif os(macOS)
        let displayScale: CGFloat = 0
        let isDark = self.mapView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        #endif
        return SnapshotInput(
            region: self.mapView.region,
            size: self.mapView.frame.size,
            displayScale: displayScale,
            camera: self.mapView.currentPlatformCamera(),
            configuration: self.mapView.appliedConfiguration,
            isDark: isDark,
            options: options)
    }

    nonisolated static func makeSnapshotOptions(_ input: SnapshotInput) throws -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.region = input.region
        options.size = input.size
        options.camera = input.camera.mkCamera
        if let configuration = input.configuration {
            options.preferredConfiguration = try FlutterMapView.makeMapConfiguration(
                configuration, hidingPointsOfInterest: !input.options.showsPointsOfInterest)
        }
        #if os(iOS)
        // Not `UITraitCollection { }`: its `UIMutableTraits` closure is UI-actor isolated (27 SDK).
        let traits = UITraitCollection(userInterfaceStyle: input.isDark ? .dark : .light)
        options.traitCollection = input.displayScale > 0
            ? traits.replacing(UITraitDisplayScale.self, value: input.displayScale)
            : traits
        #elseif os(macOS)
        options.appearance = NSAppearance(named: input.isDark ? .darkAqua : .aqua)
        #endif
        return options
    }

    /// `dispose` skips Dart's queue, so it can land while a snapshot awaits. It
    /// empties the map, and compositing that would return a wrong image as success.
    private func checkNotDisposedDuringSnapshot() throws {
        if self.isDisposed {
            throw mapKitError(.snapshotFailed, "The map view was disposed during the snapshot.")
        }
    }

    private func takeSnapshot(options: PlatformSnapshotOptions) async throws -> FlutterStandardTypedData? {
        let input = snapshotInput(options)
        let viewport = tileViewport()
        guard input.size.width > 0, input.size.height > 0 else {
            throw mapKitError(.snapshotFailed, "Map view has zero size.")
        }
        // Caller-side options exist only for `size`/`mapRect` in the
        // compositing pass below; the snapshotter gets its own copy off-actor.
        let snapshotOptions = try Self.makeSnapshotOptions(input)

        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await Self.startSnapshot(input)
        } catch {
            try self.checkNotDisposedDuringSnapshot()
            throw error
        }
        try self.checkNotDisposedDuringSnapshot()
        let tiles: SnapshotTiles
        do {
            tiles = options.showsOverlays
                ? try await self.loadTiles(for: snapshot, in: viewport)
                : SnapshotTiles(viewport: viewport)
        } catch {
            try self.checkNotDisposedDuringSnapshot()
            throw error
        }
        try self.checkNotDisposedDuringSnapshot()

        #if os(iOS)
        var drawingFailure: Error?
        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: snapshotOptions.size, format: format).image { context in
            if !tiles.replacesBaseMap {
                snapshot.image.draw(at: .zero)
            }
            let rect = snapshotOptions.mapRect
            // Image-space bounds: `snapshot.point(for:)` projects into this
            // space, so drawn frames are tested here rather than in map space.
            let bounds = CGRect(origin: .zero, size: snapshotOptions.size)
            if options.showsOverlays {
                do {
                    try self.drawOverlays(snapshot: snapshot, mapRect: rect, tiles: tiles, in: context.cgContext)
                } catch {
                    drawingFailure = error
                    return
                }
            }
            if options.showsAnnotations {
                for annotation in self.mapView.getMapViewAnnotations() where !annotation.isHidden {
                    self.drawAnnotations(annotation: annotation, point: snapshot.point(for: annotation.coordinate), bounds: bounds)
                }
            }
        }
        if let drawingFailure { throw drawingFailure }
        guard let imageData = image.pngRepresentation else {
            return nil
        }
        #elseif os(macOS)
        guard let imageData = try self.composite(snapshot, options: options, snapshotOptions: snapshotOptions, tiles: tiles) else {
            return nil
        }
        #endif
        return FlutterStandardTypedData(bytes: imageData)
    }

    #if os(macOS)
    /// Draws annotations and overlays over the snapshot at its pixel size.
    /// Annotations draw in a top-left-origin point space like the iOS
    /// renderer; macOS `snapshot.point(for:)` is bottom-left-origin, so their
    /// points are flipped and the overlay layers render under a local re-flip.
    private func composite(
        _ snapshot: MKMapSnapshotter.Snapshot,
        options: PlatformSnapshotOptions,
        snapshotOptions: MKMapSnapshotter.Options,
        tiles: SnapshotTiles
    ) throws -> Data? {
        let size = snapshotOptions.size
        guard let base = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        if !tiles.replacesBaseMap {
            context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        }
        let scale = CGFloat(base.width) / size.width
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let bounds = CGRect(origin: .zero, size: size)
        if options.showsOverlays {
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            try self.drawOverlays(snapshot: snapshot, mapRect: snapshotOptions.mapRect, tiles: tiles, in: context)
            context.restoreGState()
        }
        if options.showsAnnotations {
            for annotation in self.mapView.getMapViewAnnotations() where !annotation.isHidden {
                let point = snapshot.point(for: annotation.coordinate)
                self.drawAnnotations(annotation: annotation, point: CGPoint(x: point.x, y: size.height - point.y), bounds: bounds)
            }
        }

        guard let composed = context.makeImage() else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: composed)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }
    #endif

    /// Runs the snapshotter off the main actor and hands the result back with
    /// `sending`: older SDKs don't mark `MKMapSnapshotter.Snapshot` Sendable,
    /// so awaiting `start()` directly from `@MainActor` fails to compile
    /// there. Only the Sendable input crosses in; the options and snapshotter
    /// live entirely in this disconnected region, so the fresh snapshot is
    /// provably safe to move out.
    private nonisolated static func startSnapshot(_ input: SnapshotInput) async throws -> sending MKMapSnapshotter.Snapshot {
        try await MKMapSnapshotter(options: try makeSnapshotOptions(input)).start()
    }

    /// Skips fully off-image annotations (their drawn frame does not
    /// intersect `bounds`) before the expensive hierarchy / image draw;
    /// partially visible edge annotations still draw, matching MKMapView.
    private func drawAnnotations(annotation: FlutterAnnotation, point: CGPoint, bounds: CGRect) {
        let annotationView = self.getAnnotationView(annotation: annotation)

        if annotationView is MKMarkerAnnotationView {
            let frame = CGRect(
                x: point.x - annotationView.bounds.width / 2,
                y: point.y - annotationView.bounds.height / 2,
                width: annotationView.bounds.width,
                height: annotationView.bounds.height
            )
            guard frame.intersects(bounds) else { return }
            #if os(iOS)
            annotationView.drawHierarchy(in: frame, afterScreenUpdates: true)
            #elseif os(macOS)
            // Off-window marker views build their balloon only when prepared.
            annotationView.prepareForDisplay()
            annotationView.layoutSubtreeIfNeeded()
            guard let rep = annotationView.bitmapImageRepForCachingDisplay(in: annotationView.bounds) else { return }
            annotationView.cacheDisplay(in: annotationView.bounds, to: rep)
            rep.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            #endif
        } else if let image = annotationView.image {
            // Place the image so its normalized anchor point lands on the
            // annotation's coordinate, matching MKAnnotationView.anchorPoint.
            let origin = CGPoint(
                x: point.x - annotation.anchorPoint.x * image.size.width,
                y: point.y - annotation.anchorPoint.y * image.size.height
            )
            guard CGRect(origin: origin, size: image.size).intersects(bounds) else { return }
            #if os(iOS)
            image.draw(at: origin, blendMode: .normal, alpha: CGFloat(annotation.alpha))
            #elseif os(macOS)
            image.draw(
                in: CGRect(origin: origin, size: image.size), from: .zero, operation: .sourceOver,
                fraction: CGFloat(annotation.alpha), respectFlipped: true, hints: nil)
            #endif
        }
    }

    private var stackedOverlays: [any MKOverlay] {
        self.mapView.overlays(in: .aboveRoads) + self.mapView.overlays(in: .aboveLabels)
    }

    private static func intersects(_ overlay: any MKOverlay, _ rect: MKMapRect) -> Bool {
        overlay.intersects?(rect) ?? overlay.boundingMapRect.intersects(rect)
    }

    /// Under a pitched camera, `snapshotOptions.mapRect` only covers the flat
    /// center region; `coverage` extends to the far visible ground toward the
    /// horizon on the center's copy of the world.
    private static func intersects(_ overlay: any MKOverlay, mapRect: MKMapRect, coverage: MKMapRect) -> Bool {
        if intersects(overlay, mapRect) { return true }
        guard !coverage.isNull else { return false }
        let world = MKMapSize.world.width
        for copy in Int((coverage.minX / world).rounded(.down))...Int((coverage.maxX / world).rounded(.down)) {
            if intersects(overlay, coverage.offsetBy(dx: -Double(copy) * world, dy: 0)) { return true }
        }
        return false
    }

    /// Draws in the map's own stacking order: levels bottom to top, each level
    /// bottom to top.
    private func drawOverlays(
        snapshot: MKMapSnapshotter.Snapshot, mapRect: MKMapRect, tiles: SnapshotTiles, in context: CGContext
    ) throws {
        for overlay in self.stackedOverlays {
            if let tileOverlay = overlay as? FlutterTileOverlay {
                try tileOverlay.draw(tiles, of: snapshot, in: context, deepestSplit: Self.deepestPatchSplit)
            } else if let flutterOverlay = overlay as? any FlutterOverlay,
                      Self.intersects(overlay, mapRect: mapRect, coverage: tiles.viewport.coverage) {
                flutterOverlay.drawSnapshot(snapshot, in: context)
            }
        }
    }

    /// The live map's view for tile overlays. Captured beside `snapshotInput`:
    /// the snapshot shows the view of that moment, whatever the camera does next.
    struct TileViewport: Sendable {
        /// `ground`'s bounding rect, and at least the map's `visibleMapRect`.
        let coverage: MKMapRect
        let center: CLLocationCoordinate2D
        /// The convex patch of map the view shows, on the center's copy of the
        /// world.
        let ground: [MKMapPoint]
    }

    func tileViewport() -> TileViewport {
        let center = self.mapView.centerCoordinate
        let centerPoint = MKMapPoint(center)
        let world = MKMapSize.world.width
        var visible = self.mapView.visibleMapRect
        visible.origin.x += ((centerPoint.x - visible.midX) / world).rounded() * world
        let bounds = self.mapView.bounds
        guard let left = self.groundEdge(x: bounds.minX, around: centerPoint),
              let right = self.groundEdge(x: bounds.maxX, around: centerPoint) else {
            let ground = [
                MKMapPoint(x: visible.minX, y: visible.minY), MKMapPoint(x: visible.maxX, y: visible.minY),
                MKMapPoint(x: visible.maxX, y: visible.maxY), MKMapPoint(x: visible.minX, y: visible.maxY),
            ]
            return TileViewport(coverage: visible, center: center, ground: ground)
        }
        let ground = [left.near, left.far, right.far, right.near]
        var coverage = visible
        for point in ground {
            coverage = coverage.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        return TileViewport(coverage: coverage, center: center, ground: ground)
    }

    /// The ground a vertical edge of the view shows, or nil when neither of its
    /// ends is ground. Past the horizon `convert` answers with a pole; just short
    /// of it the ground runs off at great speed. A quarter of the world from the
    /// center, what's left is well under a point of the view, so that is where
    /// the ground ends.
    private func groundEdge(x: CGFloat, around center: MKMapPoint) -> (near: MKMapPoint, far: MKMapPoint)? {
        let world = MKMapSize.world.width
        func ground(at y: CGFloat) -> MKMapPoint? {
            let coordinate = self.mapView.convert(CGPoint(x: x, y: y), toCoordinateFrom: self.mapView)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            var mapPoint = Self.straightMapPoint(coordinate)
            mapPoint.x += ((center.x - mapPoint.x) / world).rounded() * world
            return max(abs(mapPoint.x - center.x), abs(mapPoint.y - center.y)) <= world / 4 ? mapPoint : nil
        }
        let bounds = self.mapView.bounds
        switch (ground(at: bounds.minY), ground(at: bounds.maxY)) {
        case (let top?, let bottom?):
            return (near: bottom, far: top)
        case (nil, nil):
            return nil
        case (let top, let bottom):
            var onGround = top == nil ? bounds.maxY : bounds.minY
            var pastIt = top == nil ? bounds.minY : bounds.maxY
            var far = top ?? bottom
            for _ in 0..<16 {
                let middle = (onGround + pastIt) / 2
                if let point = ground(at: middle) {
                    onGround = middle
                    far = point
                } else {
                    pastIt = middle
                }
            }
            guard let near = top ?? bottom, let far else { return nil }
            return (near: near, far: far)
        }
    }

    /// `MKMapPoint` clamps latitude at the Mercator world's edge, about 85.05°,
    /// and keeps the longitude, which bends the view's straight edge off its line
    /// wherever it runs past that. `convert` keeps going, so this does too.
    static func straightMapPoint(_ coordinate: CLLocationCoordinate2D) -> MKMapPoint {
        let sine = sin(coordinate.latitude * .pi / 180)
        let world = MKMapSize.world.height
        return MKMapPoint(
            x: MKMapPoint(coordinate).x,
            y: (0.5 - log((1 + sine) / (1 - sine)) / (4 * .pi)) * world)
    }

    /// Fetches every tile the snapshot needs through each overlay's own
    /// `loadTile`, before compositing: its drawing closure is synchronous.
    private func loadTiles(
        for snapshot: MKMapSnapshotter.Snapshot, in viewport: TileViewport
    ) async throws -> SnapshotTiles {
        let overlays = self.stackedOverlays.compactMap { $0 as? FlutterTileOverlay }
        guard !overlays.isEmpty else { return SnapshotTiles(viewport: viewport) }
        let contentScale = Self.contentScale(of: snapshot)
        var requests: [TileRequest] = []
        for overlay in overlays {
            requests += try overlay.tileRequests(
                in: viewport, contentScale: contentScale, limit: Self.tileLimit - requests.count
            ) { snapshot.point(for: $0.coordinate) }
        }
        return try SnapshotTiles(
            requests: requests,
            data: try await TileRequest.load(requests, deadline: Self.tileLoadDeadline),
            viewport: viewport,
            replacesBaseMap: overlays.contains { $0.canReplaceMapContent })
    }

    private static func contentScale(of snapshot: MKMapSnapshotter.Snapshot) -> CGFloat {
        #if os(iOS)
        return snapshot.image.scale
        #elseif os(macOS)
        guard let image = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              snapshot.image.size.width > 0 else { return 1 }
        return CGFloat(image.width) / snapshot.image.size.width
        #endif
    }
}

#if os(iOS)
// `@preconcurrency`: FlutterPlatformView is nonisolated; the engine calls
// `view()` on the platform thread (main), same as the MapKitHostApi
// conformance above.
extension MapKitViewHost: @preconcurrency FlutterPlatformView {
    public func view() -> UIView {
        return contentView
    }
}
#endif

#if os(iOS)
@MainActor
private final class ReportOnce {
    private var completion: ((Result<Bool, Error>) -> Void)?

    init(_ completion: @escaping (Result<Bool, Error>) -> Void) {
        self.completion = completion
    }

    func callAsFunction(_ result: Result<Bool, Error>) {
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}
#endif

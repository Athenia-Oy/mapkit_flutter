import Foundation
import MapKit

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

class FlutterMapView: MKMapView, PlatformGestureRecognizerDelegate {
    weak var flutterApi: MapKitFlutterApi?

    /// Camera moves made while the view has no size, oldest first; replayed
    /// once it has real bounds so MapKit doesn't resolve them against a zero
    /// rect, and so a move made in `onMapCreated` outlives the initial camera.
    /// At most one move of each kind, in camera, region, center order: a camera
    /// move sets every camera property, a region move the center and zoom, a
    /// center move only the center, so each drops the queued moves it overwrites.
    private(set) var pendingMoves: [CameraMove] = []

    /// The last configuration Dart pushed.
    private(set) var appliedConfiguration: PlatformMapConfiguration?

    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        registerDefaultAnnotationViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerDefaultAnnotationViews()
    }

    convenience init() {
        self.init(frame: CGRect.zero)
        initialiseTapGestureRecognizers()
    }

    private func registerDefaultAnnotationViews() {
        self.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "FlutterMarkerAnnotationView")
        self.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "FlutterCustomAnnotationView")
        self.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "mapkit.cluster")
    }

    #if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        reapplyPendingCamera()
    }
    #elseif os(macOS)
    override func layout() {
        super.layout()
        reapplyPendingCamera()
    }
    #endif

    private func reapplyPendingCamera() {
        guard hasLayout, !pendingMoves.isEmpty else { return }
        let moves = pendingMoves
        pendingMoves = []
        for move in moves {
            apply(move, animated: false)
        }
    }

    // MARK: - Camera

    enum CameraMove {
        case camera(MKMapCamera)
        case region(MKCoordinateRegion)
        case center(CLLocationCoordinate2D)
    }

    /// Applies `move` now and, while the view has no size, queues it for
    /// replay. Once sized, queued moves replay first, even before the next
    /// layout pass, so they never land on top of a later move.
    func move(_ move: CameraMove, animated: Bool) {
        guard hasLayout else {
            enqueue(move)
            apply(move, animated: false)
            return
        }
        reapplyPendingCamera()
        apply(move, animated: animated)
    }

    private func enqueue(_ move: CameraMove) {
        switch move {
        case .camera:
            pendingMoves = []
        case .region:
            pendingMoves.removeAll { if case .camera = $0 { false } else { true } }
        case .center:
            pendingMoves.removeAll { if case .center = $0 { true } else { false } }
        }
        pendingMoves.append(move)
    }

    private func apply(_ move: CameraMove, animated: Bool) {
        switch move {
        case .camera(let camera): setCamera(camera, animated: animated)
        case .region(let region): setRegion(region, animated: animated)
        case .center(let center): setCenter(center, animated: animated)
        }
    }

    /// The live camera; callers check `hasLayout` first — a zero-sized view
    /// reports a degenerate camera (distance 0).
    func currentPlatformCamera() -> PlatformMapCamera {
        return .from(self.camera)
    }

    /// Whether the view has real bounds; camera and region reads, conversions
    /// and snapshots are meaningless before the first layout.
    var hasLayout: Bool { bounds.size != .zero }

    func currentPlatformRegion() -> PlatformCoordinateRegion? {
        guard hasLayout else { return nil }
        return .from(self.region)
    }

    // MARK: - Configuration

    /// Applies a Dart configuration. Everything MapKit could reject is
    /// resolved first, so a throw leaves the map unchanged.
    func apply(configuration config: PlatformMapConfiguration) throws {
        let mapConfiguration = try Self.makeMapConfiguration(config)
        let trackingMode = try config.userTrackingMode.mkMode()
        let zoomRange = try Self.zoomRange(config.cameraZoomRange)
        let boundary = try config.cameraBoundary.map { region in
            guard let boundary = MKMapView.CameraBoundary(coordinateRegion: region.mkRegion) else {
                throw mapKitError(.invalidArgument, "MapKit rejects cameraBoundary \(region.mkRegion).")
            }
            return boundary
        }

        let previousTrackingMode = appliedConfiguration?.userTrackingMode
        appliedConfiguration = config
        self.preferredConfiguration = mapConfiguration

        self.showsCompass = config.showsCompass
        self.showsScale = config.showsScale

        self.isRotateEnabled = config.isRotateEnabled
        self.isScrollEnabled = config.isScrollEnabled
        self.isPitchEnabled = config.isPitchEnabled
        self.isZoomEnabled = config.isZoomEnabled

        // Like MKMapView, never prompts for location permission: the app owns
        // authorization, and a denied or undetermined status surfaces through
        // `mapView(_:didFailToLocateUserWithError:)`.
        self.showsUserLocation = config.showsUserLocation
        self.showsUserTrackingButton = config.showsUserTrackingButton

        // MapKit drops to `.none` when the user pans and reports it through
        // `mapView(_:didChange:animated:)`; unrelated config changes must not
        // snap back.
        if config.userTrackingMode != previousTrackingMode {
            self.setUserTrackingMode(trackingMode, animated: false)
        }

        // Always assign — nil clears a previously-set range/boundary.
        self.cameraZoomRange = zoomRange
        self.cameraBoundary = boundary

        #if os(iOS)
        self.insetsLayoutMarginsFromSafeArea = config.insetsLayoutMarginsFromSafeArea

        let margins = config.layoutMargins ?? []

        func extractCGFloat(from element: Any?) -> CGFloat? {
            if let number = element as? NSNumber {
                return CGFloat(number.doubleValue)
            }
            return nil
        }

        let top = extractCGFloat(from: margins.indices.contains(0) ? margins[0] : nil) ?? 0.0
        let left = extractCGFloat(from: margins.indices.contains(1) ? margins[1] : nil) ?? 0.0
        let bottom = extractCGFloat(from: margins.indices.contains(2) ? margins[2] : nil) ?? 0.0
        let right = extractCGFloat(from: margins.indices.contains(3) ? margins[3] : nil) ?? 0.0

        self.layoutMargins = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)

        // `selectableMapFeatures` / `MKMapFeatureOptions` are iOS-only.
        self.selectableMapFeatures = Self.mapFeatureOptions(config.selectableMapFeatures)
        #endif
    }

    private static func zoomRange(_ range: PlatformCameraZoomRange?) throws -> MKMapView.CameraZoomRange? {
        guard let range, range.minCenterCoordinateDistance != nil || range.maxCenterCoordinateDistance != nil else {
            return nil
        }
        guard let zoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: range.minCenterCoordinateDistance ?? MKMapCameraZoomDefault,
            maxCenterCoordinateDistance: range.maxCenterCoordinateDistance ?? MKMapCameraZoomDefault
        ) else {
            throw mapKitError(
                .invalidArgument,
                "MapKit rejects cameraZoomRange min \(String(describing: range.minCenterCoordinateDistance)) "
                    + "max \(String(describing: range.maxCenterCoordinateDistance)).")
        }
        return zoomRange
    }

    /// The `MKMapConfiguration` for a Dart configuration; shared by the live map and snapshots.
    nonisolated static func makeMapConfiguration(
        _ config: PlatformMapConfiguration,
        hidingPointsOfInterest: Bool = false
    ) throws -> MKMapConfiguration {
        let elevationStyle: MKMapConfiguration.ElevationStyle =
            config.elevationStyle == .realistic ? .realistic : .flat
        let filter = hidingPointsOfInterest ? .excludingAll : try poiFilter(from: config.pointOfInterestFilter)

        switch config.kind {
        case .imagery:
            let configuration = MKImageryMapConfiguration()
            configuration.elevationStyle = elevationStyle
            return configuration
        case .hybrid:
            let configuration = MKHybridMapConfiguration()
            configuration.elevationStyle = elevationStyle
            if let filter {
                configuration.pointOfInterestFilter = filter
            }
            configuration.showsTraffic = config.showsTraffic
            return configuration
        case .standard:
            let configuration = MKStandardMapConfiguration()
            configuration.elevationStyle = elevationStyle
            if config.emphasisStyle == .muted {
                configuration.emphasisStyle = .muted
            }
            if let filter {
                configuration.pointOfInterestFilter = filter
            }
            configuration.showsTraffic = config.showsTraffic
            return configuration
        }
    }

    /// `category` maps a wire category to MapKit's (nil when the running OS
    /// predates it); injectable so the unavailable path is testable on any OS.
    nonisolated static func poiFilter(
        from filter: PlatformPointOfInterestFilter?,
        category: (PlatformPointOfInterestCategory) -> MKPointOfInterestCategory? = \.mkCategory
    ) throws -> MKPointOfInterestFilter? {
        guard let filter = filter else { return nil }
        func categories() throws -> [MKPointOfInterestCategory] {
            try filter.categories.map { wire in
                guard let mk = category(wire) else {
                    throw mapKitError(
                        .unavailablePoiCategory,
                        "MKPointOfInterestCategory.\(wire) needs iOS 18 / macOS 15.")
                }
                return mk
            }
        }
        switch filter.mode {
        case .none:
            return MKPointOfInterestFilter.excludingAll
        case .all:
            return MKPointOfInterestFilter.includingAll
        case .including:
            return MKPointOfInterestFilter(including: try categories())
        case .excluding:
            return MKPointOfInterestFilter(excluding: try categories())
        }
    }

    #if os(iOS)
    private static func mapFeatureOptions(_ features: [PlatformMapFeatureOptions]) -> MKMapFeatureOptions {
        var options: MKMapFeatureOptions = []
        for feature in features {
            switch feature {
            case .pointsOfInterest: options.insert(.pointsOfInterest)
            case .territories: options.insert(.territories)
            case .physicalFeatures: options.insert(.physicalFeatures)
            }
        }
        return options
    }
    #endif

    /// Detaches every delegate and drops map content so the view holds nothing after `dispose`.
    func tearDown() {
        delegate = nil
        flutterApi = nil
        showsUserLocation = false
        removeAnnotations(annotations)
        removeOverlays(overlays)
    }

    /// Flutter annotations sorted bottom-to-top, matching their on-map
    /// stacking, for snapshot drawing.
    func getMapViewAnnotations() -> [FlutterAnnotation] {
        let flutter = self.annotations.compactMap { $0 as? FlutterAnnotation }
        return flutter.sorted(by: { $0.zPriority < $1.zPriority })
    }

    // MARK: - Gestures

    private func initialiseTapGestureRecognizers() {
        #if os(iOS)
        // Camera moves arrive via the delegate (`mapViewDidChangeVisibleRegion`).
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: nil)
        doubleTapGesture.numberOfTapsRequired = 2
        let longTapGesture = UILongPressGestureRecognizer(target: self, action: #selector(longTap))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onTap))
        tapGesture.require(toFail: doubleTapGesture)
        self.addGestureRecognizer(longTapGesture)
        self.addGestureRecognizer(doubleTapGesture)
        self.addGestureRecognizer(tapGesture)
        #elseif os(macOS)
        // macOS MKMapView pans/zooms/rotates natively; only tap and long-press
        // need bridging to Flutter. Camera moves arrive via the delegate.
        // Like iOS taps, a click waits out a double-click, which zooms instead.
        let doubleClickGesture = NSClickGestureRecognizer(target: nil, action: nil)
        doubleClickGesture.numberOfClicksRequired = 2
        doubleClickGesture.delegate = self
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(onTap))
        clickGesture.delegate = self
        self.addGestureRecognizer(doubleClickGesture)
        self.addGestureRecognizer(clickGesture)
        let pressGesture = NSPressGestureRecognizer(target: self, action: #selector(longTap))
        pressGesture.delegate = self
        self.addGestureRecognizer(pressGesture)
        #endif
    }

    @objc func longTap(_ sender: PlatformGestureRecognizer) {
        guard sender.state == .began else { return }
        let locationInView = sender.location(in: self)
        let locationOnMap = self.convert(locationInView, toCoordinateFrom: self)
        let coordinate = PlatformCoordinate.from(locationOnMap)
        self.flutterApi?.send { try await $0.onMapLongPress(coordinate: coordinate) }
    }

    @objc func onTap(_ tap: PlatformGestureRecognizer) {
        #if os(iOS)
        guard tap.state == .recognized else { return }
        #endif
        TouchHandler.handleMapTaps(tap: tap, flutterApi: self.flutterApi, in: self)
    }

    func gestureRecognizer(_ gestureRecognizer: PlatformGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: PlatformGestureRecognizer) -> Bool {
        return true
    }

    #if os(macOS)
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        (gestureRecognizer as? NSClickGestureRecognizer)?.numberOfClicksRequired == 1
            && (otherGestureRecognizer as? NSClickGestureRecognizer)?.numberOfClicksRequired == 2
    }
    #endif
}

extension PlatformUserTrackingMode {
    func mkMode() throws -> MKUserTrackingMode {
        switch self {
        case .none: return .none
        case .follow: return .follow
        case .followWithHeading:
            #if os(iOS)
            return .followWithHeading
            #elseif os(macOS)
            throw mapKitError(.unsupportedPlatform, "userTrackingMode followWithHeading is iOS only.")
            #endif
        }
    }

    init(mkMode: MKUserTrackingMode) {
        switch mkMode {
        case .none: self = .none
        case .follow: self = .follow
        #if os(iOS)
        case .followWithHeading: self = .followWithHeading
        #endif
        @unknown default: self = .none
        }
    }
}

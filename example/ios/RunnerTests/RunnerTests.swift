import Flutter
import MapKit
import UIKit
import XCTest
@testable import mapkit_flutter

private func annotation(_ id: String, callout: Bool = false) -> PlatformAnnotation {
    PlatformAnnotation(
        id: id,
        coordinate: PlatformCoordinate(latitude: 1, longitude: 2),
        icon: PlatformAnnotationIcon(type: .marker),
        calloutConsumesTapEvents: callout,
        alpha: 1,
        anchorPointX: 0.5,
        anchorPointY: 1,
        isDraggable: true,
        isHidden: false,
        zPriority: 500
    )
}

@MainActor
final class RunnerTests: XCTestCase {
    func testEvChargerMapsOnEveryOS() {
        XCTAssertEqual(PlatformPointOfInterestCategory.evCharger.mkCategory, .evCharger)
    }

    func testCalloutRecognizerAddedOncePerView() throws {
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        try host.updateAnnotations(toAdd: [annotation("a", callout: true)], toChange: [], idsToRemove: [])
        let view = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)

        host.mapView(host.mapView, didSelect: view)
        host.mapView(host.mapView, didSelect: view)

        let recognizers = (view.gestureRecognizers ?? []).filter { $0 is InfoWindowTapGestureRecognizer }
        XCTAssertEqual(recognizers.count, 1)
    }

    func testMapFeaturePayloadMapsTypeAndCategory() {
        let payload = PlatformMapFeature.make(
            featureType: .territory,
            coordinate: CLLocationCoordinate2D(latitude: 37.32, longitude: -122.03),
            title: "Cupertino",
            category: .evCharger)

        XCTAssertEqual(payload.featureType, .territory)
        XCTAssertEqual(payload.coordinate.latitude, 37.32)
        XCTAssertEqual(payload.coordinate.longitude, -122.03)
        XCTAssertEqual(payload.title, "Cupertino")
        XCTAssertEqual(payload.pointOfInterestCategory, .evCharger)
    }

    func testIOS18CategoryDroppedBeforeIOS18() {
        if #available(iOS 18.0, *) {
            XCTAssertEqual(PlatformPointOfInterestCategory.golf.mkCategory, .golf)
        } else {
            XCTAssertNil(PlatformPointOfInterestCategory.golf.mkCategory)
        }
    }

    /// Run on an iOS 17 simulator to exercise the throw: a filter naming an
    /// iOS 18 category fails instead of silently becoming `including([])`,
    /// which would hide every point of interest.
    func testIOS18CategoryInAFilterFailsBeforeIOS18() throws {
        let filter = PlatformPointOfInterestFilter(mode: .including, categories: [.golf, .cafe])
        if #available(iOS 18.0, *) {
            XCTAssertNotNil(try FlutterMapView.poiFilter(from: filter))
        } else {
            XCTAssertThrowsError(try FlutterMapView.poiFilter(from: filter)) { error in
                XCTAssertEqual((error as? MapKitHostError)?.code, "unavailable-poi-category")
            }
        }
    }

    func testCalloutRecognizerRemovedWhenCalloutDisabled() throws {
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        try host.updateAnnotations(toAdd: [annotation("a", callout: true)], toChange: [], idsToRemove: [])
        let view = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)

        host.mapView(host.mapView, didSelect: view)
        XCTAssertEqual((view.gestureRecognizers ?? []).filter { $0 is InfoWindowTapGestureRecognizer }.count, 1)

        if let flutterAnnotation = host.annotationsById["a"] {
            flutterAnnotation.calloutConsumesTapEvents = false
            host.syncCalloutTapGestureRecognizer(for: flutterAnnotation, on: view)
        }
        XCTAssertEqual((view.gestureRecognizers ?? []).filter { $0 is InfoWindowTapGestureRecognizer }.count, 0)
    }
}

/// A tap recognizer pinned to one location, so tap routing runs without touches.
final class FixedPointTap: UITapGestureRecognizer {
    private let point: CGPoint

    init(at point: CGPoint) {
        self.point = point
        super.init(target: nil, action: nil)
    }

    override func location(in view: UIView?) -> CGPoint { point }
}

@MainActor
final class CameraAndTapTests: XCTestCase {
    func testCameraMoveBeforeFirstLayoutSurvivesIt() throws {
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        try host.initialize(params: PlatformMapViewCreationParams(
            initialCamera: PlatformMapCamera(
                centerCoordinate: PlatformCoordinate(latitude: 10, longitude: 10), distance: 500_000, heading: 0, pitch: 0),
            configuration: PlatformMapConfiguration(
                kind: .standard, emphasisStyle: .standard, elevationStyle: .flat, showsTraffic: false,
                showsCompass: true, showsScale: false, showsUserLocation: false, showsUserTrackingButton: false,
                userTrackingMode: .none, insetsLayoutMarginsFromSafeArea: true, isRotateEnabled: true,
                isScrollEnabled: true, isZoomEnabled: true, isPitchEnabled: true, selectableMapFeatures: []),
            annotations: [], polylines: [], polygons: [], circles: []))
        try host.setCamera(
            camera: PlatformMapCamera(
                centerCoordinate: PlatformCoordinate(latitude: 40, longitude: 20), distance: 50_000, heading: 0, pitch: 0),
            animated: true)

        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.layoutIfNeeded()

        let center = try XCTUnwrap(try host.getCamera()).centerCoordinate
        XCTAssertEqual(center.latitude, 40, accuracy: 0.01)
        XCTAssertEqual(center.longitude, 20, accuracy: 0.01)
    }

    func testTapOnAnAnnotationViewIsNotAMapTap() async throws {
        let messenger = NoopMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let pin = MKAnnotationView(annotation: try FlutterAnnotation(fromPlatform: annotation("a")), reuseIdentifier: nil)
        pin.frame = CGRect(x: 100, y: 100, width: 40, height: 40)
        host.mapView.addSubview(pin)

        TouchHandler.handleMapTaps(tap: FixedPointTap(at: CGPoint(x: 120, y: 120)), flutterApi: host.flutterApi, in: host.mapView)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(messenger.sent("onMapTap"), 0)

        TouchHandler.handleMapTaps(tap: FixedPointTap(at: CGPoint(x: 300, y: 300)), flutterApi: host.flutterApi, in: host.mapView)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(messenger.sent("onMapTap"), 1)
    }
}

@MainActor
final class LookAroundPresentationTests: XCTestCase {
    func testRejectedPresentationFailsInsteadOfHanging() async throws {
        let offscreen = UIViewController()
        let failed = expectation(description: "fails")

        MapKitViewHost.present(UIViewController(), over: offscreen) { result in
            if case .failure(let error as MapKitHostError) = result, error.code == "look-around-failed" {
                failed.fulfill()
            } else {
                XCTFail("expected look-around-failed, got \(result)")
            }
        }

        await fulfillment(of: [failed], timeout: 3)
    }

    func testAcceptedPresentationSucceedsOnce() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        let presented = expectation(description: "presents")
        presented.assertForOverFulfill = true
        let vc = UIViewController()

        MapKitViewHost.present(vc, over: root) { result in
            if case .success(true) = result { presented.fulfill() } else { XCTFail("expected success, got \(result)") }
        }

        await fulfillment(of: [presented], timeout: 3)
        XCTAssertIdentical(root.presentedViewController, vc)
        root.dismiss(animated: false)
    }

    func testPresentationOverAnInFlightPresentationReportsOnce() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        var results: [Result<Bool, Error>] = []

        root.present(UIViewController(), animated: true)
        MapKitViewHost.present(UIViewController(), over: root) { results.append($0) }

        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(results.count, 1, "completions: \(results)")
        guard case .success(true) = results.first else {
            return XCTFail("UIKit presented Look Around but the result is \(results)")
        }
        root.dismiss(animated: false)
    }
}

/// A 400×400 pt ocean map at 0°,0° spanning 1°: 400 points per degree.
@MainActor
final class SnapshotDrawOrderTests: XCTestCase {
    private func oceanHost() -> MapKitViewHost {
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        return host
    }

    private func redIcon() throws -> PlatformAnnotationIcon {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        return PlatformAnnotationIcon(
            type: .image, imageBytes: FlutterStandardTypedData(bytes: try XCTUnwrap(image.pngData())), imagePixelRatio: 1)
    }

    /// RGBA bytes of the snapshot, top row first.
    private func snapshot(_ host: MapKitViewHost) throws -> (bytes: [UInt8], width: Int) {
        let exp = expectation(description: "snapshot")
        var png: Data?
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: true, showsOverlays: true)) { result in
            if case .success(let data) = result { png = data.data }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 20)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(png))?.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
        return (bytes, image.width)
    }

    private func rgb(_ shot: (bytes: [UInt8], width: Int), at coordinate: CLLocationCoordinate2D, in host: MapKitViewHost)
        -> (r: Double, g: Double, b: Double) {
        let point = host.mapView.convert(coordinate, toPointTo: host.mapView)
        let scale = CGFloat(shot.width) / 400
        let i = (Int(point.y * scale) * shot.width + Int(point.x * scale)) * 4
        return (Double(shot.bytes[i]) / 255, Double(shot.bytes[i + 1]) / 255, Double(shot.bytes[i + 2]) / 255)
    }

    func testSnapshotDrawsAnnotationsAboveOverlays() throws {
        let host = oceanHost()
        try host.updatePolygons(toAdd: [PlatformPolygon(
            id: "square",
            coordinates: [
                PlatformCoordinate(latitude: -0.1, longitude: 0.1), PlatformCoordinate(latitude: -0.1, longitude: 0.3),
                PlatformCoordinate(latitude: -0.3, longitude: 0.3), PlatformCoordinate(latitude: -0.3, longitude: 0.1),
            ],
            interiorPolygons: [], fillColorArgb: 0xFF00_FF00, strokeColorArgb: 0xFF00_FF00, lineWidth: 1,
            zIndex: 0, isHidden: false, consumeTapEvents: false, level: .aboveRoads)], toChange: [], idsToRemove: [])
        try host.updateAnnotations(toAdd: [PlatformAnnotation(
            id: "inside", coordinate: PlatformCoordinate(latitude: -0.2, longitude: 0.2), icon: try redIcon(),
            calloutConsumesTapEvents: false, alpha: 1, anchorPointX: 0.5, anchorPointY: 0.5, isDraggable: false,
            isHidden: false, zPriority: 500)], toChange: [], idsToRemove: [])

        let shot = try snapshot(host)

        let pin = rgb(shot, at: CLLocationCoordinate2D(latitude: -0.2, longitude: 0.2), in: host)
        let polygon = rgb(shot, at: CLLocationCoordinate2D(latitude: -0.12, longitude: 0.12), in: host)
        XCTAssertTrue(pin.r > 0.8 && pin.g < 0.3 && pin.b < 0.3, "pin inside the polygon is drawn under it: \(pin)")
        XCTAssertTrue(polygon.g > 0.8 && polygon.r < 0.3, "polygon pixel is \(polygon)")
    }

    func testSnapshotDrawsGradientPolylinesWithTheirGradient() throws {
        let host = oceanHost()
        try host.updatePolylines(toAdd: [PlatformPolyline(
            id: "route",
            coordinates: [PlatformCoordinate(latitude: 0, longitude: -0.4), PlatformCoordinate(latitude: 0, longitude: 0.4)],
            strokeColorArgb: 0xFF00_FF00, lineWidth: 12, lineCap: .butt, lineJoin: .round, isHidden: false,
            consumeTapEvents: false, isGeodesic: false, level: .aboveRoads, zIndex: 0,
            gradientColorsArgb: [0xFFFF_0000, 0xFF00_00FF])], toChange: [], idsToRemove: [])

        let shot = try snapshot(host)

        let start = rgb(shot, at: CLLocationCoordinate2D(latitude: 0, longitude: -0.38), in: host)
        let end = rgb(shot, at: CLLocationCoordinate2D(latitude: 0, longitude: 0.38), in: host)
        XCTAssertTrue(start.r > 0.8 && start.g < 0.3 && start.b < 0.3, "gradient start is \(start)")
        XCTAssertTrue(end.b > 0.8 && end.r < 0.3 && end.g < 0.3, "gradient end is \(end)")
    }
}

/// A callout tap recognizer pinned to one location, in the annotation view's
/// coordinates.
final class FixedPointCalloutTap: InfoWindowTapGestureRecognizer {
    private let point: CGPoint

    init(at point: CGPoint) {
        self.point = point
        super.init(target: nil, action: nil)
    }

    override func location(in view: UIView?) -> CGPoint { point }
}

@MainActor
final class CalloutTests: XCTestCase {
    /// A map in a real window with annotation "a" selected and its callout up.
    private func mapWithSelectedCallout(
        _ messenger: NoopMessenger, subtitle: String? = "Subtitle",
        icon: PlatformAnnotationIcon = PlatformAnnotationIcon(type: .marker)
    ) async throws -> (host: MapKitViewHost, view: MKAnnotationView, callout: UIView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        let host = MapKitViewHost(messenger: messenger, id: 0)
        root.view.addSubview(host.view())
        host.view().frame = root.view.bounds
        host.mapView.frame = root.view.bounds
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        try host.updateAnnotations(
            toAdd: [titledAnnotation("a", title: "Title", subtitle: subtitle, callout: true, icon: icon)],
            toChange: [], idsToRemove: [])
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(try host.selectAnnotation(annotationId: "a"))
        let annotation = try XCTUnwrap(host.annotationsById["a"])
        for _ in 0..<40 {
            if let view = host.mapView.view(for: annotation),
               let callout = view.subviews.first(where: { String(describing: type(of: $0)).contains("Callout") }) {
                return (host, view, callout)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("MapKit showed no callout view")
        throw CancellationError()
    }

    private func tap(_ host: MapKitViewHost, _ view: MKAnnotationView, at point: CGPoint) async throws {
        let recognizer = FixedPointCalloutTap(at: point)
        recognizer.annotationId = "a"
        recognizer.annotationView = view
        host.onCalloutTapped(infoWindowTap: recognizer)
        try await Task.sleep(for: .milliseconds(200))
    }

    func testTappingTheSelectedPinIsNotACalloutTap() async throws {
        let messenger = NoopMessenger()
        let (host, view, callout) = try await mapWithSelectedCallout(messenger)

        try await tap(host, view, at: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
        XCTAssertEqual(messenger.sent("onCalloutTap"), 0, "a tap on the pin fired onCalloutTap")

        try await tap(host, view, at: CGPoint(x: callout.frame.midX, y: callout.frame.midY))
        XCTAssertEqual(messenger.sent("onCalloutTap"), 1, "a tap on the callout must still fire")
    }

    func testATitleOnlyMarkerShowsATappableCallout() async throws {
        let messenger = NoopMessenger()
        let (host, view, callout) = try await mapWithSelectedCallout(messenger, subtitle: nil)

        try await tap(host, view, at: CGPoint(x: callout.frame.midX, y: callout.frame.midY))
        XCTAssertEqual(messenger.sent("onCalloutTap"), 1)
    }

    func testTappingASelectedImagePinIsNotACalloutTap() async throws {
        let messenger = NoopMessenger()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let (host, view, callout) = try await mapWithSelectedCallout(messenger, icon: PlatformAnnotationIcon(
            type: .image, imageBytes: FlutterStandardTypedData(bytes: png), imagePixelRatio: 1))

        try await tap(host, view, at: CGPoint(x: view.bounds.midX, y: view.bounds.midY))
        XCTAssertEqual(messenger.sent("onCalloutTap"), 0)

        try await tap(host, view, at: CGPoint(x: callout.frame.midX, y: callout.frame.midY))
        XCTAssertEqual(messenger.sent("onCalloutTap"), 1)
    }

    /// The pin/callout split above rests on this: an OS release that moves the
    /// callout over the pin must fail here, not silently swallow callout taps.
    func testMapKitKeepsTheCalloutOutsideTheAnnotationViewsBounds() async throws {
        let (_, view, callout) = try await mapWithSelectedCallout(NoopMessenger())

        XCTAssertFalse(
            view.bounds.insetBy(dx: 1, dy: 1).intersects(callout.frame),
            "callout \(callout.frame) overlaps the pin \(view.bounds)")
    }

    func testRecognizerDoesNotKeepItsViewAlive() throws {
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        try host.updateAnnotations(
            toAdd: [titledAnnotation("a", title: "A", callout: true)], toChange: [], idsToRemove: [])
        weak var released: MKAnnotationView?
        autoreleasepool {
            let view = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)
            host.mapView(host.mapView, didSelect: view)
            XCTAssertEqual((view.gestureRecognizers ?? []).filter { $0 is InfoWindowTapGestureRecognizer }.count, 1)
            released = view
        }

        XCTAssertNil(released, "the recognizer retains its view, a cycle only didDeselect broke")
    }

    func testAChangedTitleReachesTheVisibleMarkerLabel() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in window.isHidden = true }
        let host = MapKitViewHost(messenger: NoopMessenger(), id: 0)
        root.view.addSubview(host.view())
        host.view().frame = root.view.bounds
        host.mapView.frame = root.view.bounds
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        try await Task.sleep(for: .seconds(1))
        try host.updateAnnotations(toAdd: [titledAnnotation("a", title: "Alpha")], toChange: [], idsToRemove: [])
        try await Task.sleep(for: .seconds(2))

        func render() -> Data? {
            UIGraphicsImageRenderer(bounds: CGRect(x: 100, y: 330, width: 200, height: 160)).pngData { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        let before = render()
        XCTAssertEqual(before, render(), "the map must be settled to compare renders")

        try host.updateAnnotations(
            toAdd: [], toChange: [titledAnnotation("a", title: "A much longer title")], idsToRemove: [])
        try await Task.sleep(for: .seconds(2))

        XCTAssertNotEqual(before, render(), "the label under the pin still shows the old title")
    }

    func testAChangedTitleReachesTheVisibleCallout() async throws {
        let (host, view, _) = try await mapWithSelectedCallout(NoopMessenger(), subtitle: nil)

        func labels(_ root: UIView) -> [String] {
            root.subviews.flatMap(labels) + [(root as? UILabel)?.text].compactMap { $0 }
        }
        XCTAssertTrue(labels(view).contains("Title"), "\(labels(view))")

        try host.updateAnnotations(
            toAdd: [], toChange: [titledAnnotation("a", title: "Changed", callout: true)], idsToRemove: [])
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(labels(view).contains("Changed"), "stale callout: \(labels(view))")
    }
}

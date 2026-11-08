import Flutter
import ImageIO
import MapKit
import Network
import UIKit
import XCTest
@testable import mapkit_flutter

/// Swallows every message, recording which host -> Dart methods were sent.
final class NoopMessenger: NSObject, FlutterBinaryMessenger {
    private(set) var channels: [String] = []

    func send(onChannel channel: String, message: Data?) {
        channels.append(channel)
    }

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        channels.append(channel)
        callback?(MessagesPigeonCodec.shared.encode([] as [Any?]))
    }

    func sent(_ method: String) -> Int {
        channels.filter { $0.contains(".\(method).") }.count
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        0
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

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

// MARK: - Regression tests shared by iOS and macOS

/// Remembers every handler the way the engine does, so a host retained by its
/// own channel handlers stays alive here too.
final class HandlerRetainingMessenger: NSObject, FlutterBinaryMessenger {
    private(set) var handlers: [FlutterBinaryMessengerConnection: (channel: String, handler: FlutterBinaryMessageHandler)] = [:]
    private var next: FlutterBinaryMessengerConnection = 0

    func send(onChannel channel: String, message: Data?) {}

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        callback?(MessagesPigeonCodec.shared.encode([] as [Any?]))
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        next += 1
        if let handler { handlers[next] = (channel, handler) }
        return next
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
        handlers.removeValue(forKey: connection)
    }

    /// The decoded reply of the host handler for `method`.
    func call(_ method: String, _ args: [Any?]? = nil) -> [Any?]? {
        var reply: [Any?]?
        let message = args.flatMap { MessagesPigeonCodec.shared.encode($0) }
        handlers.values.first { $0.channel.contains(".\(method).") }?.handler(message) { data in
            reply = data.flatMap { MessagesPigeonCodec.shared.decode($0) } as? [Any?]
        }
        return reply
    }
}

/// Answers every host -> Dart event with a canned reply envelope.
final class ReplyingMessenger: NSObject, FlutterBinaryMessenger {
    private let reply: [Any?]?
    init(reply: [Any?]?) { self.reply = reply }

    func send(onChannel channel: String, message: Data?) {}

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        callback?(reply.flatMap { MessagesPigeonCodec.shared.encode($0) })
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

private extension MKMapView {
    var isFlippedForTests: Bool { true }
}

private func titledAnnotation(
    _ id: String, title: String?, subtitle: String? = nil, callout: Bool = false,
    icon: PlatformAnnotationIcon = PlatformAnnotationIcon(type: .marker)
) -> PlatformAnnotation {
    PlatformAnnotation(
        id: id,
        coordinate: PlatformCoordinate(latitude: 0, longitude: 0),
        icon: icon,
        title: title,
        subtitle: subtitle,
        calloutConsumesTapEvents: callout,
        alpha: 1,
        anchorPointX: 0.5,
        anchorPointY: 1,
        isDraggable: false,
        isHidden: false,
        zPriority: 500
    )
}

/// Serves one solid PNG for any tile path and records what was asked for.
/// `hold()` keeps replies back until `release()`.
final class PngTileServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "png-tile-server")
    private let png: Data
    private var connections: [NWConnection] = []
    private var waiting: [NWConnection] = []
    private var held = false
    private var paths: [String] = []

    init(png: Data) throws {
        self.png = png
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.queue.async {
                self.connections.append(connection)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    self.handle(data, on: connection)
                }
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: queue)
        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
    }

    var template: String { "http://127.0.0.1:\(listener.port?.rawValue ?? 0)/{z}/{x}/{y}.png" }

    /// The z of every tile requested so far.
    var requestedZooms: [Int] {
        queue.sync { paths.compactMap { Int($0.split(separator: "/").first ?? "") } }
    }

    func hold() { queue.sync { held = true } }

    func release() {
        queue.sync {
            held = false
            waiting.forEach(reply)
            waiting.removeAll()
        }
    }

    func stop() {
        listener.cancel()
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func handle(_ data: Data?, on connection: NWConnection) {
        let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first ?? ""
        let path = line.split(separator: " ").dropFirst().first?.dropFirst() ?? ""
        paths.append(String(path))
        if held {
            waiting.append(connection)
        } else {
            reply(connection)
        }
    }

    private func reply(_ connection: NWConnection) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(png.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + png, isComplete: true, completion: .contentProcessed { _ in })
    }
}

/// Accepts tile connections and never answers them.
final class StalledTileServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "stalled-tile-server")
    private var connections: [NWConnection] = []

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.queue.async { self.connections.append(connection) }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.start(queue: queue)
        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
    }

    var template: String { "http://127.0.0.1:\(listener.port?.rawValue ?? 0)/{z}/{x}/{y}.png" }

    func stop() {
        listener.cancel()
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}

@MainActor
final class EventDeliveryTests: XCTestCase {
    private func failure(whenReplying reply: [Any?]?) async throws -> MapKitHostError {
        let original = EventDeliveryFailure.report
        defer { EventDeliveryFailure.report = original }
        var reported: Error?
        let delivered = expectation(description: "failure reported")
        EventDeliveryFailure.report = {
            reported = $0
            delivered.fulfill()
        }

        let api = MapKitFlutterApi(binaryMessenger: ReplyingMessenger(reply: reply), messageChannelSuffix: "0")
        api.send { try await $0.onCameraIdle() }

        await fulfillment(of: [delivered], timeout: 2)
        return try XCTUnwrap(reported as? MapKitHostError)
    }

    func testAnErrorReplyIsReportedNotDropped() async throws {
        let error = try await failure(whenReplying: ["wire-failure", "decoding failed", nil])
        XCTAssertEqual(error.code, "wire-failure")
    }

    func testAMissingListenerIsReportedAsAChannelError() async throws {
        let error = try await failure(whenReplying: nil)
        XCTAssertEqual(error.code, "channel-error")
    }
}

@MainActor
final class HostLifetimeTests: XCTestCase {
    func testAHostNobodyDisposesReleasesItselfAndItsHandlers() throws {
        let messenger = HandlerRetainingMessenger()
        weak var released: MapKitViewHost?
        autoreleasepool {
            let host = MapKitViewHost(messenger: messenger, id: 0)
            released = host
            XCTAssertFalse(messenger.handlers.isEmpty)
        }

        XCTAssertNil(released, "channel handlers keep the undisposed host alive")
        XCTAssertTrue(messenger.handlers.isEmpty, "\(messenger.handlers.count) handlers outlived the host")
    }

    func testHandlersReachTheLiveHostUntilItIsDisposed() throws {
        let messenger = HandlerRetainingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)

        XCTAssertEqual(messenger.call("getCamera")?.count, 1)
        XCTAssertEqual(
            messenger.call("selectAnnotation", ["missing"])?.first as? Bool, false)

        XCTAssertEqual(messenger.call("dispose")?.count, 1)
        XCTAssertTrue(messenger.handlers.isEmpty)
        XCTAssertNil(host.mapView.delegate)
    }
}

@MainActor
final class AnnotationUpdateTests: XCTestCase {
    func testChangingAnAnnotationNativeNeverAcceptedAddsIt() throws {
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)

        try host.updateAnnotations(toAdd: [], toChange: [titledAnnotation("a", title: "A")], idsToRemove: [])

        XCTAssertEqual(host.annotationsById["a"]?.title, "A")
        XCTAssertEqual(host.mapView.annotations.count, 1)
    }

    func testTitleAndSubtitleChangesAreObservableByMapKit() throws {
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
        try host.updateAnnotations(
            toAdd: [titledAnnotation("a", title: "A", subtitle: "S")], toChange: [], idsToRemove: [])
        let annotation = try XCTUnwrap(host.annotationsById["a"])
        let title = XCTKVOExpectation(keyPath: "title", object: annotation)
        let subtitle = XCTKVOExpectation(keyPath: "subtitle", object: annotation)

        try host.updateAnnotations(
            toAdd: [], toChange: [titledAnnotation("a", title: "B", subtitle: "T")], idsToRemove: [])

        wait(for: [title, subtitle], timeout: 1)
    }
}

/// Solid-colour tiles on disk behind a `file://` template, so `MKTileOverlay.loadTile`
/// itself runs. All at z = 2: the row just north of the equator is y = 1, the
/// one south y = 2; x = 1 and 2 meet at the prime meridian, x = 3 and 0 at the
/// antimeridian. A 400×400 pt map spanning 1° asks for z = 9, so a `maximumZ` of
/// 2 upscales them and the quadrant colours land predictably around the crossing.
private struct TileFolder {
    let url: URL

    static let northWest: (UInt8, UInt8, UInt8) = (255, 0, 255)
    static let northEast: (UInt8, UInt8, UInt8) = (0, 255, 255)
    static let southWest: (UInt8, UInt8, UInt8) = (255, 255, 0)
    static let southEast: (UInt8, UInt8, UInt8) = (0, 120, 0)

    init(test: XCTestCase) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("tiles-\(UUID().uuidString)")
        let folder = url
        test.addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        for (x, y, color) in [
            (1, 1, Self.northWest), (2, 1, Self.northEast), (1, 2, Self.southWest), (2, 2, Self.southEast),
            (3, 1, Self.northWest), (0, 1, Self.northEast), (3, 2, Self.southWest), (0, 2, Self.southEast),
        ] {
            try write(png(color), z: 2, x: x, y: y)
        }
    }

    var template: String { "file://\(url.path)/{z}/{x}/{y}.png" }

    func write(_ data: Data, z: Int, x: Int, y: Int) throws {
        let folder = url.appendingPathComponent("\(z)/\(x)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("\(y).png"))
    }

    func png(_ color: (UInt8, UInt8, UInt8)) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255, blue: CGFloat(color.2) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// The decoded snapshot as sRGB RGBA bytes, top row first.
private struct SnapshotPixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init(png: Data) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let (w, h) = (image.width, image.height)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drawn)
        bytes = buffer
    }

    /// RGBA at `point`, in points from the top-left of a 400 pt wide map.
    func rgba(at point: CGPoint) -> (r: Int, g: Int, b: Int, a: Int) {
        let scale = CGFloat(width) / 400
        return rgba(atPixel: CGPoint(x: point.x * scale, y: point.y * scale))
    }

    func rgba(atPixel pixel: CGPoint) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (Int(pixel.y) * width + Int(pixel.x)) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
    }
}

@MainActor
final class SnapshotOverlayTests: XCTestCase {
    private func oceanHost(
        latitude: Double = 0, longitude: Double = 0, heading: Double? = nil
    ) -> MapKitViewHost {
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        if let heading {
            host.mapView.setCamera(MKMapCamera(
                lookingAtCenter: host.mapView.centerCoordinate, fromDistance: host.mapView.camera.centerCoordinateDistance,
                pitch: 0, heading: heading), animated: false)
        }
        return host
    }

    private func tiles(
        _ template: String, id: String = "tiles", minimumZ: Int64 = 0, maximumZ: Int64 = 2, tileSize: Int64 = 256,
        alpha: Double = 1, replaces: Bool = false, level: PlatformOverlayLevel = .aboveRoads
    ) -> PlatformTileOverlay {
        PlatformTileOverlay(
            id: id, urlTemplate: template, minimumZ: minimumZ, maximumZ: maximumZ, tileSize: tileSize,
            canReplaceMapContent: replaces, alpha: alpha, level: level)
    }

    private func greenCircle(_ id: String = "circle", radius: Double = 20_000, level: PlatformOverlayLevel = .aboveRoads) -> PlatformCircle {
        PlatformCircle(
            id: id, center: PlatformCoordinate(latitude: 0, longitude: 0), radius: radius,
            fillColorArgb: 0xFF00_FF00, strokeColorArgb: 0xFF00_FF00, lineWidth: 1, zIndex: 0,
            isHidden: false, consumeTapEvents: false, level: level)
    }

    private func snapshotResult(
        _ host: MapKitViewHost, overlays: Bool = true
    ) -> Result<FlutterStandardTypedData, Error> {
        let done = expectation(description: "snapshot")
        var result: Result<FlutterStandardTypedData, Error> = .failure(mapKitError(.snapshotFailed, "never finished"))
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: false, showsOverlays: overlays)) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
    }

    private func snapshot(_ host: MapKitViewHost, overlays: Bool = true) throws -> SnapshotPixels {
        try SnapshotPixels(png: try snapshotResult(host, overlays: overlays).get().data)
    }

    /// Where `coordinate` lands, from the top-left of the map view.
    private func point(_ host: MapKitViewHost, _ latitude: Double, _ longitude: Double) -> CGPoint {
        let p = host.mapView.convert(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude), toPointTo: host.mapView)
        #if os(macOS)
        return CGPoint(x: p.x, y: host.mapView.isFlipped ? p.y : 400 - p.y)
        #else
        return p
        #endif
    }

    private func assertColor(
        _ pixel: (r: Int, g: Int, b: Int, a: Int), _ expected: (UInt8, UInt8, UInt8), _ what: String,
        tolerance: Int = 24, file: StaticString = #filePath, line: UInt = #line
    ) {
        let close = abs(pixel.r - Int(expected.0)) <= tolerance
            && abs(pixel.g - Int(expected.1)) <= tolerance
            && abs(pixel.b - Int(expected.2)) <= tolerance
        XCTAssertTrue(close, "\(what) is \(pixel), expected \(expected)", file: file, line: line)
    }

    private func assertFourQuadrants(_ host: MapKitViewHost, around lon: Double = 0, file: StaticString = #filePath, line: UInt = #line) throws {
        let shot = try snapshot(host)
        assertColor(shot.rgba(at: point(host, 0.2, lon - 0.2)), TileFolder.northWest, "north-west", file: file, line: line)
        assertColor(shot.rgba(at: point(host, 0.2, lon + 0.2)), TileFolder.northEast, "north-east", file: file, line: line)
        assertColor(shot.rgba(at: point(host, -0.2, lon - 0.2)), TileFolder.southWest, "south-west", file: file, line: line)
        assertColor(shot.rgba(at: point(host, -0.2, lon + 0.2)), TileFolder.southEast, "south-east", file: file, line: line)
    }

    func testTilesLandOnTheirCoordinates() throws {
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

        try assertFourQuadrants(host)
    }

    func testTilesFollowARotatedCamera() throws {
        let host = oceanHost(heading: 90)
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

        try assertFourQuadrants(host)
    }

    func testTilesCrossTheAntimeridian() throws {
        let host = oceanHost(longitude: 180)
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

        try assertFourQuadrants(host, around: 180)
    }

    func testPitchedTilesCoverTheWholeViewOnTheirCoordinates() throws {
        for (distance, pitch, heading) in [(100_000.0, 30.0, 30.0), (1500, 60, 20), (500, 70, 200), (200, 89, 30), (200, 89, 225)] {
            let host = oceanHost()
            host.mapView.setCamera(MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 0, longitude: 0), fromDistance: distance,
                pitch: CGFloat(pitch), heading: heading), animated: false)
            XCTAssertGreaterThan(host.mapView.camera.pitch, 5, "this camera must really tilt")
            try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

            let shot = try snapshot(host)

            for row in 0...20 {
                for column in 0...20 {
                    let sample = CGPoint(x: min(399, column * 20), y: min(399, row * 20))
                    let live = CGPoint(x: sample.x, y: host.mapView.isFlippedForTests ? sample.y : 400 - sample.y)
                    let coordinate = host.mapView.convert(live, toCoordinateFrom: host.mapView)
                    let expected = coordinate.latitude >= 0
                        ? (coordinate.longitude < 0 ? TileFolder.northWest : TileFolder.northEast)
                        : (coordinate.longitude < 0 ? TileFolder.southWest : TileFolder.southEast)
                    // Skip the seams: which side a boundary pixel lands on is noise.
                    guard abs(coordinate.latitude) < 85,
                          abs(coordinate.latitude) > 0.002 * max(1, distance / 5000),
                          abs(coordinate.longitude) > 0.002 * max(1, distance / 5000) else { continue }
                    assertColor(
                        shot.rgba(at: sample), expected,
                        "pixel \(sample) of camera (\(distance) m, pitch \(pitch), heading \(heading)) at \(coordinate)")
                }
            }
        }
    }

    func testAWorldViewStillDrawsItsTiles() throws {
        let folder = try TileFolder(test: self)
        for x in 0...1 {
            for y in 0...1 {
                try folder.write(try folder.png(TileFolder.northWest), z: 1, x: x, y: y)
            }
        }
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 200)), animated: false)
        try host.addTileOverlay(overlay: tiles(folder.template, maximumZ: 1))

        let shot = try snapshot(host)

        assertColor(shot.rgba(at: point(host, 0, 0)), TileFolder.northWest, "the map's centre")
        assertColor(shot.rgba(at: point(host, 20, 40)), TileFolder.northWest, "off centre")
    }

    func testTileAlphaBlendsOverTheBaseMap() throws {
        let host = oceanHost()
        let sample = point(host, 0.2, -0.2)
        let base = try snapshot(host).rgba(at: sample)
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template, alpha: 0.5))

        let blended = try snapshot(host).rgba(at: sample)

        assertColor(blended, (
            UInt8((Int(TileFolder.northWest.0) + base.r) / 2),
            UInt8((Int(TileFolder.northWest.1) + base.g) / 2),
            UInt8((Int(TileFolder.northWest.2) + base.b) / 2)), "half-transparent tile over \(base)")
    }

    func testOverlaysDrawInTheirMapOrder() throws {
        let folder = try TileFolder(test: self)
        let center = point(oceanHost(), -0.05, -0.05)

        let tileThenCircle = oceanHost()
        try tileThenCircle.addTileOverlay(overlay: tiles(folder.template))
        try tileThenCircle.updateCircles(toAdd: [greenCircle()], toChange: [], idsToRemove: [])
        assertColor(try snapshot(tileThenCircle).rgba(at: center), (0, 255, 0), "circle added over a tile")

        let circleThenTile = oceanHost()
        try circleThenTile.updateCircles(toAdd: [greenCircle()], toChange: [], idsToRemove: [])
        try circleThenTile.addTileOverlay(overlay: tiles(folder.template))
        assertColor(try snapshot(circleThenTile).rgba(at: center), TileFolder.southWest, "tile added over a circle")

        let labelsOverRoads = oceanHost()
        try labelsOverRoads.addTileOverlay(overlay: tiles(folder.template, level: .aboveLabels))
        try labelsOverRoads.updateCircles(toAdd: [greenCircle()], toChange: [], idsToRemove: [])
        assertColor(
            try snapshot(labelsOverRoads).rgba(at: center), TileFolder.southWest, "aboveLabels tile over an aboveRoads circle")
    }

    func testCanReplaceMapContentDrawsNoBaseMapBeneath() throws {
        let folder = try TileFolder(test: self)
        let plain = oceanHost()
        try plain.addTileOverlay(overlay: tiles(folder.template, alpha: 0.5))
        XCTAssertEqual(try snapshot(plain).rgba(at: point(plain, 0.2, -0.2)).a, 255)

        let replacing = oceanHost()
        try replacing.addTileOverlay(overlay: tiles(folder.template, alpha: 0.5, replaces: true))
        let pixel = try snapshot(replacing).rgba(at: point(replacing, 0.2, -0.2))

        XCTAssertLessThan(abs(pixel.a - 128), 12, "base map shows beneath: \(pixel)")
    }

    func testWithOverlaysOffTilesAreNeitherLoadedNorDrawn() throws {
        let host = oceanHost()
        let base = try snapshot(host, overlays: false).rgba(at: CGPoint(x: 200, y: 200))
        try host.addTileOverlay(overlay: tiles("file:///no/such/tiles/{z}/{x}/{y}.png", replaces: true))

        let off = try snapshot(host, overlays: false).rgba(at: CGPoint(x: 200, y: 200))

        assertColor(off, (UInt8(base.r), UInt8(base.g), UInt8(base.b)), "snapshot without overlays")
    }

    func testBelowMinimumZTheOverlayHasNothingToDraw() throws {
        let host = oceanHost()
        let base = try snapshot(host).rgba(at: CGPoint(x: 200, y: 200))
        try host.addTileOverlay(overlay: tiles("file:///no/such/tiles/{z}/{x}/{y}.png", minimumZ: 15, maximumZ: 19))

        let above = try snapshot(host).rgba(at: CGPoint(x: 200, y: 200))

        assertColor(above, (UInt8(base.r), UInt8(base.g), UInt8(base.b)), "map with no tiles at this zoom")
    }

    private func assertSnapshotFails(_ host: MapKitViewHost, mentioning id: String, file: StaticString = #filePath, line: UInt = #line) {
        switch snapshotResult(host) {
        case .success:
            XCTFail("a tile failure degraded into a successful snapshot", file: file, line: line)
        case .failure(let error as MapKitHostError):
            XCTAssertEqual(error.code, "snapshot-failed", file: file, line: line)
            XCTAssertTrue(error.message?.contains(id) == true, "\(error)", file: file, line: line)
        case .failure(let error):
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    func testAMissingTileFailsTheSnapshot() throws {
        let folder = try TileFolder(test: self)
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(folder.url.appendingPathComponent("gone").absoluteString + "/{z}/{x}/{y}.png", id: "sparse"))

        assertSnapshotFails(host, mentioning: "sparse")
    }

    func testATileThatIsNotAnImageFailsTheSnapshot() throws {
        let folder = try TileFolder(test: self)
        try folder.write(Data("<html>404</html>".utf8), z: 2, x: 1, y: 1)
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(folder.template, id: "broken"))

        assertSnapshotFails(host, mentioning: "broken")
    }

    func testATileViewCrossingTheAntimeridianStaysSmall() throws {
        for (longitude, distance) in [
            (-179.999, 2_000.0), (-179.99, 200_000), (-180, 2_000), (179.999, 2_000), (180, 2_000), (0, 2_000),
        ] {
            let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
            host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
            host.mapView.setCamera(MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: 0, longitude: longitude), fromDistance: distance,
                pitch: 0, heading: 0), animated: false)
            let visible = host.mapView.visibleMapRect

            let coverage = host.tileViewport().coverage

            XCTAssertLessThan(
                coverage.width, visible.width * 1.5,
                "at longitude \(longitude): coverage \(coverage) for a view of \(visible)")
            XCTAssertLessThanOrEqual(try requests(host).count, 16, "at longitude \(longitude)")
        }
    }

    func testTilesLandJustEastOfTheAntimeridian() throws {
        let host = oceanHost(longitude: -179.99)
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

        try assertFourQuadrants(host, around: -179.99)
    }

    func testAViewNeedingTooManyTilesFailsInsteadOfFetchingThem() throws {
        let host = oceanHost()
        fetchOnly(tiles("file:///no/such/tiles/{z}/{x}/{y}.png", id: "tiny", maximumZ: 21, tileSize: 8), on: host)

        assertSnapshotFails(host, mentioning: "more than \(MapKitViewHost.tileLimit) tiles")
    }

    func testACameraMoveDuringTheSnapshotKeepsTheTilesOfTheSnapshottedView() throws {
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))
        let sample = point(host, 0.2, -0.2)
        let done = expectation(description: "snapshot")
        var result: Result<FlutterStandardTypedData, Error>?
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: false, showsOverlays: true)) {
            result = $0
            done.fulfill()
        }
        // Main-actor tasks run in order, so this lands while the first one
        // waits on the snapshotter.
        Task { @MainActor in
            host.mapView.setCenter(CLLocationCoordinate2D(latitude: 40, longitude: 100), animated: false)
        }
        wait(for: [done], timeout: 30)

        let shot = try SnapshotPixels(png: try XCTUnwrap(result).get().data)

        assertColor(shot.rgba(at: sample), TileFolder.northWest, "the snapshotted view's tile")
    }

    private func withTileDeadline(_ seconds: TimeInterval, _ body: () throws -> Void) rethrows {
        let original = MapKitViewHost.tileLoadDeadline
        MapKitViewHost.tileLoadDeadline = seconds
        defer { MapKitViewHost.tileLoadDeadline = original }
        try body()
    }

    func testAStalledTileFailsTheSnapshotAtTheDeadline() throws {
        let server = try StalledTileServer()
        defer { server.stop() }
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(server.template, id: "stalled"))
        let start = Date()

        withTileDeadline(2) {
            assertSnapshotFails(host, mentioning: "stalled")
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testAFailedTileDoesNotWaitForTheOthers() throws {
        let server = try StalledTileServer()
        defer { server.stop() }
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(server.template, id: "stalled"))
        try host.addTileOverlay(overlay: tiles("file:///no/such/tiles/{z}/{x}/{y}.png", id: "missing"))
        let start = Date()

        assertSnapshotFails(host, mentioning: "missing")

        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func testEveryCameraMapKitReportsPassesThePitchCheck() throws {
        let host = oceanHost()
        for pitch in [0, 0.001, 1, 30, 45, 60, 75, 89.9] as [CGFloat] {
            for distance in [500.0, 5_000, 5_000_000] {
                host.mapView.setCamera(MKMapCamera(
                    lookingAtCenter: CLLocationCoordinate2D(latitude: 0, longitude: 0), fromDistance: distance,
                    pitch: pitch, heading: 123), animated: false)
                let reported = try XCTUnwrap(try host.getCamera()).pitch
                XCTAssertTrue(abs(reported) < 90, "pitch \(pitch) at \(distance) m reads back \(reported)")
            }
        }
    }

    func testInitializeWithoutACameraKeepsTheCamera() throws {
        let host = oceanHost()
        let center = PlatformCoordinate(latitude: 12, longitude: 34)
        try host.setCamera(
            camera: PlatformMapCamera(centerCoordinate: center, distance: 50_000, heading: 0, pitch: 0), animated: false)

        try host.initialize(params: PlatformMapViewCreationParams(
            configuration: try XCTUnwrap(minimalConfiguration()), annotations: [], polylines: [], polygons: [], circles: []))

        let camera = try XCTUnwrap(try host.getCamera())
        XCTAssertEqual(camera.centerCoordinate.latitude, 12, accuracy: 0.01)
        XCTAssertEqual(camera.centerCoordinate.longitude, 34, accuracy: 0.01)
    }

    private func minimalConfiguration() -> PlatformMapConfiguration {
        PlatformMapConfiguration(
            kind: .standard, emphasisStyle: .standard, elevationStyle: .flat, showsTraffic: false,
            showsCompass: true, showsScale: false, showsUserLocation: false, showsUserTrackingButton: false,
            userTrackingMode: .none, insetsLayoutMarginsFromSafeArea: true, isRotateEnabled: true,
            isScrollEnabled: true, isZoomEnabled: true, isPitchEnabled: true, selectableMapFeatures: [])
    }

    private func tileViewportHost(
        width: CGFloat, height: CGFloat, distance: Double, heading: Double = 30, latitude: Double = 37.33,
        longitude: Double = -122
    ) -> MapKitViewHost {
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.mapView.setCamera(MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), fromDistance: distance,
            pitch: 89, heading: heading), animated: false)
        return host
    }

    private func requests(_ host: MapKitViewHost, tileSize: Int64 = 256, maximumZ: Int64 = 21, minimumZ: Int64 = 0) throws -> [TileRequest] {
        try FlutterTileOverlay(fromPlatform: tiles(
            "https://tile.example.com/{z}/{x}/{y}.png", minimumZ: minimumZ, maximumZ: maximumZ, tileSize: tileSize)
        ).tileRequests(in: host.tileViewport(), contentScale: 1, limit: MapKitViewHost.tileLimit) {
            host.mapView.convert($0.coordinate, toPointTo: host.mapView)
        }
    }

    /// An overlay `takeSnapshot` fetches for, but the live map doesn't know about,
    /// so nothing else asks its source for tiles. It fetches but never draws.
    private func fetchOnly(_ overlay: PlatformTileOverlay, on host: MapKitViewHost) {
        host.tileOverlays[overlay.id] = FlutterTileOverlay(fromPlatform: overlay)
    }

    /// MapKit caps pitch by distance and view size; asking for 89 gets the cap.
    func testAViewAtThePitchCapNeedsFarFewerTilesThanTheLimit() throws {
        for (width, height) in [(390.0, 844.0), (820, 1180)] as [(CGFloat, CGFloat)] {
            let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
            host.mapView.frame = CGRect(x: 0, y: 0, width: width, height: height)
            for distance in [100.0, 200, 300, 500] {
                for heading in [0.0, 30, 137] {
                    host.mapView.setCamera(MKMapCamera(
                        lookingAtCenter: CLLocationCoordinate2D(latitude: 37.33, longitude: -122), fromDistance: distance,
                        pitch: 89, heading: heading), animated: false)
                    XCTAssertGreaterThanOrEqual(host.mapView.camera.pitch, 69, "\(width)x\(height) at \(distance) m")

                    let found = try requests(host)

                    XCTAssertLessThanOrEqual(found.count, 256, "\(width)x\(height) at \(distance) m, heading \(heading)")
                    let (nearest, farthest) = (found.map(\.path.z).max() ?? 0, found.map(\.path.z).min() ?? 99)
                    XCTAssertGreaterThanOrEqual(nearest, 18, "the near ground needs full detail")
                    XCTAssertLessThanOrEqual(farthest, nearest - 3, "the far ground needs only coarser tiles")
                }
            }
        }
    }

    func testTheNearGroundOfASteepViewGetsTheZoomItsWidthCallsFor() throws {
        let found = try requests(tileViewportHost(width: 390, height: 844, distance: 200, heading: 0))

        XCTAssertEqual(found.map(\.path.z).max(), 21, "by area alone this ground goes a zoom softer")
    }

    func testAFlatViewAsksForTheZoomOfItsResolution() throws {
        let host = oceanHost()

        let found = try requests(host)

        XCTAssertEqual(Set(found.map(\.path.z)), [9], "400 pt over 1 degree is 144,000 pt around the world")
        XCTAssertLessThanOrEqual(found.count, 16)
    }

    func testASnapshotRequestsTheZoomOfItsResolution() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        let host = oceanHost()
        fetchOnly(tiles(server.template, maximumZ: 21), on: host)

        _ = try snapshot(host)

        XCTAssertEqual(Set(server.requestedZooms), [9])
        XCTAssertLessThanOrEqual(server.requestedZooms.count, 16)
    }

    func testASnapshotAtThePitchCapFetchesWhatItsTilesCallFor() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        let host = tileViewportHost(width: 390, height: 844, distance: 200)
        fetchOnly(tiles(server.template, maximumZ: 21), on: host)

        _ = try snapshot(host)

        XCTAssertLessThanOrEqual(server.requestedZooms.count, 256)
        XCTAssertLessThan(server.requestedZooms.min() ?? 99, 10, "the horizon needs only coarse tiles")
    }

    func testAViewNeedingTooManyTilesFailsBeforeBuildingThem() throws {
        let host = tileViewportHost(width: 820, height: 1180, distance: 300)
        let overlay = FlutterTileOverlay(fromPlatform: tiles(
            "https://tile.example.com/{z}/{x}/{y}.png", maximumZ: 21, tileSize: 1))
        var projections = 0

        XCTAssertThrowsError(try overlay.tileRequests(
            in: host.tileViewport(), contentScale: 1, limit: MapKitViewHost.tileLimit
        ) { point in
            projections += 1
            return host.mapView.convert(point.coordinate, toPointTo: host.mapView)
        }) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "snapshot-failed")
        }

        XCTAssertLessThan(projections, 100_000, "it walked every tile before checking the limit")
    }

    func testTheLimitAllowsExactlyThatManyTiles() throws {
        let host = tileViewportHost(width: 390, height: 844, distance: 200)
        let overlay = FlutterTileOverlay(fromPlatform: tiles("https://tile.example.com/{z}/{x}/{y}.png", maximumZ: 21))
        let project: (MKMapPoint) -> CGPoint = { host.mapView.convert($0.coordinate, toPointTo: host.mapView) }
        let needed = try overlay.tileRequests(in: host.tileViewport(), contentScale: 1, limit: 1024, project: project).count

        XCTAssertEqual(
            try overlay.tileRequests(in: host.tileViewport(), contentScale: 1, limit: needed, project: project).count, needed)
        XCTAssertThrowsError(
            try overlay.tileRequests(in: host.tileViewport(), contentScale: 1, limit: needed - 1, project: project))
    }

    func testTheLimitCountsEveryOverlayTogether() throws {
        let host = tileViewportHost(width: 820, height: 1180, distance: 300)
        let template = "file:///no/such/tiles/{z}/{x}/{y}.png"
        let tileSize = try XCTUnwrap(([32, 48, 64, 96, 128] as [Int64]).first { size in
            guard let needed = try? requests(host, tileSize: size).count else { return false }
            return needed > MapKitViewHost.tileLimit / 2
        })
        XCTAssertNoThrow(try requests(host, tileSize: tileSize), "one overlay alone must fit")
        fetchOnly(tiles(template, id: "first", maximumZ: 21, tileSize: tileSize), on: host)
        fetchOnly(tiles(template, id: "second", maximumZ: 21, tileSize: tileSize), on: host)

        assertSnapshotFails(host, mentioning: "more than \(MapKitViewHost.tileLimit) tiles")
    }

    func testBelowMinimumZTheFarGroundGoesWithoutTiles() throws {
        let host = tileViewportHost(width: 390, height: 844, distance: 200)

        let found = try requests(host, minimumZ: 18)

        XCTAssertFalse(found.isEmpty)
        XCTAssertGreaterThanOrEqual(found.map(\.path.z).min() ?? 0, 18)
    }

    /// Points of the view showing ground the tile grid reaches, but not the tile.
    private func pointsWithoutTiles(_ shot: SnapshotPixels, _ host: MapKitViewHost, width: CGFloat, height: CGFloat) -> [CGPoint] {
        let pixelsPerPoint = CGFloat(shot.width) / width
        var missing: [CGPoint] = []
        for y in stride(from: 2, to: height - 1, by: 4) {
            for x in stride(from: 1, to: width - 1, by: 4) {
                let view = CGPoint(x: x, y: host.mapView.isFlippedForTests ? y : height - y)
                let coordinate = host.mapView.convert(view, toCoordinateFrom: host.mapView)
                guard abs(coordinate.latitude) < 85.04 else { continue }
                let pixel = shot.rgba(atPixel: CGPoint(x: x * pixelsPerPoint, y: y * pixelsPerPoint))
                if !(pixel.r > 200 && pixel.g < 60 && pixel.b > 200) {
                    missing.append(CGPoint(x: x, y: y))
                }
            }
        }
        return missing
    }

    private func assertSteepSnapshotHasNoHoles(
        width: CGFloat, height: CGFloat, latitude: Double, longitude: Double = -122, distance: Double, heading: Double,
        maximumZ: Int64 = 21, tileSize: Int64 = 256, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        let host = tileViewportHost(
            width: width, height: height, distance: distance, heading: heading, latitude: latitude, longitude: longitude)
        try host.addTileOverlay(overlay: tiles(server.template, maximumZ: maximumZ, tileSize: tileSize))

        let missing = pointsWithoutTiles(try snapshot(host), host, width: width, height: height)

        XCTAssertEqual(
            missing.count, 0,
            "\(width)x\(height) lat \(latitude) \(distance) m heading \(heading) maximumZ \(maximumZ) tileSize \(tileSize): "
                + "\(missing.prefix(4))",
            file: file, line: line)
    }

    func testTheGroundFollowsTheEdgesOfTheViewPastTheEdgeOfTheMercatorWorld() throws {
        let world = MKMapSize.world.width
        let host = MapKitViewHost(messenger: HandlerRetainingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 820, height: 1180)
        for latitude in [-70.0, -60, 0, 37.33, 60, 70, 84.5] {
            for distance in [200.0, 300, 500] {
                for heading in stride(from: 0.0, to: 360, by: 15) {
                    host.mapView.setCamera(MKMapCamera(
                        lookingAtCenter: CLLocationCoordinate2D(latitude: latitude, longitude: -122), fromDistance: distance,
                        pitch: 89, heading: heading), animated: false)
                    let ground = host.tileViewport().ground
                    for (near, far, x) in [(ground[0], ground[1], 0.0), (ground[3], ground[2], 820.0)] as [(MKMapPoint, MKMapPoint, CGFloat)] {
                        let midway = MapKitViewHost.straightMapPoint(
                            host.mapView.convert(CGPoint(x: x, y: 590), toCoordinateFrom: host.mapView))
                        let (toMidwayX, toMidwayY) = (
                            midway.x + ((near.x - midway.x) / world).rounded() * world - near.x, midway.y - near.y
                        )
                        let (toFarX, toFarY) = (far.x - near.x, far.y - near.y)
                        let sine = abs(toMidwayX * toFarY - toMidwayY * toFarX)
                            / (hypot(toMidwayX, toMidwayY) * hypot(toFarX, toFarY))
                        XCTAssertLessThan(
                            sine, 0.01,
                            "lat \(latitude) \(distance) m heading \(heading) edge x \(x): near \(near) far \(far) midway \(midway)")
                    }
                }
            }
        }
    }

    /// A painter over one 1,000-point-square tile well inside the ground, with an
    /// injected projection that counts its calls.
    private func painter(
        deepestSplit: Int = 40, project: @escaping (Int, MKMapPoint) -> CGPoint
    ) throws -> (paint: () throws -> Void, calls: () -> Int) {
        let middle = MKMapSize.world.width / 2
        let tile = MKMapRect(x: middle, y: middle, width: 1000, height: 1000)
        let around = tile.insetBy(dx: -1000, dy: -1000)
        let viewport = MapKitViewHost.TileViewport(
            coverage: around, center: MKMapPoint(x: tile.midX, y: tile.midY).coordinate,
            ground: [
                MKMapPoint(x: around.minX, y: around.minY), MKMapPoint(x: around.maxX, y: around.minY),
                MKMapPoint(x: around.maxX, y: around.maxY), MKMapPoint(x: around.minX, y: around.maxY),
            ])
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        var calls = 0
        var painter = TilePainter(
            viewport: viewport, context: context, deepestSplit: deepestSplit,
            patchBudget: TilePainter.patchBudget(forViewOf: CGSize(width: 390, height: 844))
        ) { point in
            calls += 1
            precondition(calls < 10_000_000, "the painter is still splitting after ten million projections")
            return project(calls, point)
        }
        return ({ try painter.paint(SnapshotTiles.Tile(mapRect: tile, image: image), covering: around) }, { calls })
    }

    private func assertPainterGivesUp(
        _ projection: @escaping (Int, MKMapPoint) -> CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let painter = try painter(project: projection)

        XCTAssertThrowsError(try painter.paint(), file: file, line: line) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "snapshot-failed", file: file, line: line)
        }
        XCTAssertLessThan(
            painter.calls(), TilePainter.patchBudget(forViewOf: CGSize(width: 390, height: 844)) * 4 + 4,
            "it gave up only after splitting on", file: file, line: line)
    }

    func testAProjectionThatNeverSettlesFailsInsteadOfSplittingForever() throws {
        try assertPainterGivesUp { _, _ in CGPoint(x: CGFloat.nan, y: .nan) }
        // Twisted along the tile's middle column, at a scale where patches straddling
        // the twist stay above a pixel for 38 splits: a line of them, breeding.
        let middle = MKMapSize.world.width / 2 + 500
        try assertPainterGivesUp { _, point in
            let across = (point.x - middle) * 17_000_000
            return CGPoint(x: across, y: (point.y - middle + 1_000) * 17_000_000 * (across < 0 ? -1 : 1))
        }
    }

    private func assertPainterDrawsNothingAndFinishes(
        _ projection: @escaping (Int, MKMapPoint) -> CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let painter = try painter(project: projection)

        XCTAssertNoThrow(try painter.paint(), file: file, line: line)
        XCTAssertLessThan(painter.calls(), 100, file: file, line: line)
    }

    func testPatchesThatFaceAwayOrHaveNoSizeHaveNothingToDraw() throws {
        try assertPainterDrawsNothingAndFinishes { _, _ in CGPoint(x: 10, y: 10) }
        // The first three calls set the handedness; everything after comes back mirrored.
        try assertPainterDrawsNothingAndFinishes { call, point in
            CGPoint(x: (call <= 3 ? 1 : -1) * point.x / 1_000, y: point.y / 1_000)
        }
    }

    /// Along the Mercator world's edge MapKit projects patches with no area.
    func testAViewOfTheWorldsEdgeDrawsItsTilesAndFinishes() throws {
        try assertSteepSnapshotHasNoHoles(
            width: 390, height: 844, latitude: 85.05, longitude: 0, distance: 200, heading: 0, maximumZ: 3)
    }

    func testThePatchBudgetIsWellAboveWhatALargeViewNeeds() {
        XCTAssertGreaterThan(TilePainter.patchBudget(forViewOf: CGSize(width: 2560, height: 1440)), 87_404 * 5)
    }

    func testATileThatWontSettleFailsTheSnapshot() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        let host = tileViewportHost(width: 390, height: 844, distance: 200)
        try host.addTileOverlay(overlay: tiles(server.template, id: "coarse"))
        let original = MapKitViewHost.deepestPatchSplit
        MapKitViewHost.deepestPatchSplit = 1
        defer { MapKitViewHost.deepestPatchSplit = original }

        assertSnapshotFails(host, mentioning: "didn't settle")
    }

    func testTilesFillAViewAtThePitchCap() throws {
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 37.33, distance: 200, heading: 30)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 37.33, distance: 300, heading: 30)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 37.33, distance: 500, heading: 30)
    }

    func testTilesFillAViewWhoseFarGroundPassesTheEdgeOfTheMercatorWorld() throws {
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 70, distance: 200, heading: 30)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 60, distance: 300, heading: 330)
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 60, distance: 200, heading: 330)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: -60, distance: 300, heading: 160)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 84.5, distance: 300, heading: 0)
    }

    func testCoarseTilesFillASteepViewRightUpToTheCamera() throws {
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 37.33, distance: 1000, heading: 30, maximumZ: 12)
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 37.33, distance: 1000, heading: 30, maximumZ: 14)
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 37.33, distance: 200, heading: 30, maximumZ: 16)
        try assertSteepSnapshotHasNoHoles(width: 820, height: 1180, latitude: 37.33, distance: 500, heading: 30, maximumZ: 14)
        try assertSteepSnapshotHasNoHoles(width: 390, height: 844, latitude: 37.33, distance: 200, heading: 30, tileSize: 1024)
    }

    func testBelowMinimumZASnapshotShowsTheBaseMapOnTheFarGround() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        let host = tileViewportHost(width: 390, height: 844, distance: 200)
        try host.addTileOverlay(overlay: tiles(server.template, minimumZ: 18, maximumZ: 21))

        let shot = try snapshot(host)

        let pixelsPerPoint = CGFloat(shot.width) / 390
        func pixel(_ y: CGFloat) -> (r: Int, g: Int, b: Int, a: Int) {
            shot.rgba(atPixel: CGPoint(x: 195 * pixelsPerPoint, y: y * pixelsPerPoint))
        }
        assertColor(pixel(830), TileFolder.northWest, "the near ground")
        assertSkyIsUncovered(pixel(60), "the far ground, which would need tiles below minimumZ")
    }

    private func assertSkyIsUncovered(_ pixel: (r: Int, g: Int, b: Int, a: Int), _ what: String) {
        XCTAssertFalse(pixel.r > 230 && pixel.g < 30 && pixel.b > 230, "\(what) is covered by a tile: \(pixel)")
    }

    private func disposeDuringTheSnapshot(of host: MapKitViewHost) -> Result<FlutterStandardTypedData, Error> {
        let done = expectation(description: "snapshot")
        var result: Result<FlutterStandardTypedData, Error> = .failure(mapKitError(.snapshotFailed, "never finished"))
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: true, showsOverlays: true)) {
            result = $0
            done.fulfill()
        }
        // Main-actor tasks run in order, so this lands while the first one
        // waits on the snapshotter.
        Task { @MainActor in try? host.dispose() }
        wait(for: [done], timeout: 30)
        return result
    }

    private func assertDisposalFailed(_ result: Result<FlutterStandardTypedData, Error>, file: StaticString = #filePath, line: UInt = #line) {
        switch result {
        case .success:
            XCTFail("a disposed map's snapshot came back as a success", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual((error as? MapKitHostError)?.code, "snapshot-failed", file: file, line: line)
            XCTAssertTrue((error as? MapKitHostError)?.message?.contains("disposed") == true, "\(error)", file: file, line: line)
        }
    }

    func testDisposeDuringATileSnapshotFailsIt() throws {
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(try TileFolder(test: self).template))

        assertDisposalFailed(disposeDuringTheSnapshot(of: host))
    }

    func testDisposeDuringASnapshotOfOverlaysAndAnnotationsFailsIt() throws {
        let host = oceanHost()
        try host.updateCircles(toAdd: [greenCircle()], toChange: [], idsToRemove: [])
        try host.updateAnnotations(toAdd: [titledAnnotation("a", title: "A")], toChange: [], idsToRemove: [])

        assertDisposalFailed(disposeDuringTheSnapshot(of: host))
    }

    func testDisposeWhileTilesLoadFailsTheSnapshot() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        server.hold()
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(server.template))
        let done = expectation(description: "snapshot")
        var result: Result<FlutterStandardTypedData, Error> = .failure(mapKitError(.snapshotFailed, "never finished"))
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: false, showsOverlays: true)) {
            result = $0
            done.fulfill()
        }
        let deadline = Date().addingTimeInterval(20)
        while server.requestedZooms.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertFalse(server.requestedZooms.isEmpty, "tiles never started loading")

        try host.dispose()
        server.release()
        wait(for: [done], timeout: 20)

        assertDisposalFailed(result)
    }

    func testABatchLetsGoOfItsBytesOnceItsOutcomeIsKnown() async throws {
        let folder = try TileFolder(test: self)
        let overlay = FlutterTileOverlay(fromPlatform: tiles(folder.template))
        let request = TileRequest(
            overlay: overlay, path: MKTileOverlayPath(x: 1, y: 1, z: 2, contentScaleFactor: 1),
            mapRect: MKMapRect(x: 0, y: 0, width: 1, height: 1))
        weak var released: TileBatch?

        let loaded: [Data] = try await withCheckedThrowingContinuation { continuation in
            let batch = TileBatch(requests: [request], continuation: continuation)
            released = batch
            batch.start(deadline: 3600)
        }

        XCTAssertEqual(loaded.count, 1)
        for _ in 0..<40 where released != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(released, "the deadline timer keeps the batch and its bytes alive")
    }

    func testAFailedBatchLetsGoOfTheBytesItAlreadyHas() async throws {
        let server = try StalledTileServer()
        defer { server.stop() }
        let folder = try TileFolder(test: self)
        func request(_ template: String) -> TileRequest {
            TileRequest(
                overlay: FlutterTileOverlay(fromPlatform: tiles(template)),
                path: MKTileOverlayPath(x: 1, y: 1, z: 2, contentScaleFactor: 1),
                mapRect: MKMapRect(x: 0, y: 0, width: 1, height: 1))
        }
        var batch: TileBatch?

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                let started = TileBatch(requests: [request(folder.template), request(server.template)], continuation: continuation)
                batch = started
                started.start(deadline: 1)
            } as [Data]
            XCTFail("a stalled tile must fail the batch")
        } catch {
            XCTAssertTrue("\(error)".isEmpty == false)
        }

        XCTAssertEqual(batch?.heldBytes, 0)
    }

    func testATileArrivingAfterTheOutcomeIsIgnored() throws {
        let server = try PngTileServer(png: try TileFolder(test: self).png(TileFolder.northWest))
        defer { server.stop() }
        server.hold()
        let host = oceanHost()
        try host.addTileOverlay(overlay: tiles(server.template, id: "late"))
        try host.addTileOverlay(overlay: tiles("file:///no/such/tiles/{z}/{x}/{y}.png", id: "missing"))

        assertSnapshotFails(host, mentioning: "missing")
        server.release()

        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

    func testCircleKeepsItsRadiusUnderARotatedCamera() throws {
        for heading in [0.0, 45, 90] {
            let host = oceanHost(heading: heading)
            try host.updateCircles(toAdd: [greenCircle(radius: 20_000)], toChange: [], idsToRemove: [])
            let radiusInDegrees = 20_000.0 / 111_320

            let shot = try snapshot(host)

            for (lat, lon) in [(0.8, 0.0), (-0.8, 0.0), (0.0, 0.8), (0.0, -0.8)] {
                assertColor(
                    shot.rgba(at: point(host, lat * radiusInDegrees, lon * radiusInDegrees)), (0, 255, 0),
                    "inside the circle at heading \(heading) (\(lat), \(lon))")
                let outside = shot.rgba(at: point(host, lat * 1.5 * radiusInDegrees, lon * 1.5 * radiusInDegrees))
                XCTAssertFalse(
                    outside.g > 200 && outside.r < 60 && outside.b < 60,
                    "outside the circle at heading \(heading) (\(lat), \(lon)) is \(outside)")
            }
        }
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

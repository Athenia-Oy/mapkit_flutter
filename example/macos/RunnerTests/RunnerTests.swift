import Cocoa
import FlutterMacOS
import MapKit
import XCTest
@testable import mapkit_flutter

/// Records every host -> Dart message and answers with pigeon's success envelope.
final class RecordingMessenger: NSObject, FlutterBinaryMessenger {
    private(set) var sent: [(channel: String, args: [Any?])] = []
    private var pending: [(method: String, expectation: XCTestExpectation)] = []

    func send(onChannel channel: String, message: Data?) {
        record(channel, message)
    }

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        record(channel, message)
        callback?(MessagesPigeonCodec.shared.encode([] as [Any?]))
    }

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        0
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}

    func args(of method: String) -> [[Any?]] {
        sent.filter { $0.channel.contains(".\(method).") }.map(\.args)
    }

    func expectation(for method: String, in test: XCTestCase) -> XCTestExpectation {
        let expectation = test.expectation(description: method)
        expectation.assertForOverFulfill = false
        pending.append((method, expectation))
        return expectation
    }

    private func record(_ channel: String, _ message: Data?) {
        let args = MessagesPigeonCodec.shared.decode(message) as? [Any?] ?? []
        sent.append((channel, args))
        for entry in pending where channel.contains(".\(entry.method).") {
            entry.expectation.fulfill()
        }
    }
}

/// Hands out a fresh connection per handler and tracks which are still registered.
final class ConnectionCountingMessenger: NSObject, FlutterBinaryMessenger {
    private(set) var live: Set<FlutterBinaryMessengerConnection> = []
    private var next: FlutterBinaryMessengerConnection = 0

    func send(onChannel channel: String, message: Data?) {}

    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}

    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection {
        next += 1
        live.insert(next)
        return next
    }

    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
        live.remove(connection)
    }
}

private func annotation(_ id: String, title: String? = nil, callout: Bool = false) -> PlatformAnnotation {
    PlatformAnnotation(
        id: id,
        coordinate: PlatformCoordinate(latitude: 1, longitude: 2),
        icon: PlatformAnnotationIcon(type: .marker),
        title: title,
        calloutConsumesTapEvents: callout,
        alpha: 1,
        anchorPointX: 0.5,
        anchorPointY: 1,
        isDraggable: true,
        isHidden: false,
        zPriority: 500
    )
}

/// A real PNG (MapKit must decode it), `width`×`height` points at ratio 1.
private func pngIcon(width: CGFloat = 20, height: CGFloat = 40) -> PlatformAnnotationIcon {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    return PlatformAnnotationIcon(type: .image, imageBytes: FlutterStandardTypedData(bytes: png), imagePixelRatio: 1)
}

private func configuration(
    scale: Bool = false,
    tracking: PlatformUserTrackingMode = .none,
    kind: PlatformMapKind = .standard,
    trackingButton: Bool = false,
    userLocation: Bool = false
) -> PlatformMapConfiguration {
    PlatformMapConfiguration(
        kind: kind,
        emphasisStyle: .standard,
        elevationStyle: .flat,
        showsTraffic: false,
        showsCompass: true,
        showsScale: scale,
        showsUserLocation: userLocation,
        showsUserTrackingButton: trackingButton,
        userTrackingMode: tracking,
        insetsLayoutMarginsFromSafeArea: true,
        isRotateEnabled: true,
        isScrollEnabled: true,
        isZoomEnabled: true,
        isPitchEnabled: true,
        selectableMapFeatures: []
    )
}

private func circle(
    _ id: String, zIndex: Int64 = 0, hidden: Bool = false, level: PlatformOverlayLevel = .aboveRoads
) -> PlatformCircle {
    PlatformCircle(
        id: id,
        center: PlatformCoordinate(latitude: 0, longitude: 0),
        radius: 50_000,
        fillColorArgb: 0xFF00_00FF,
        strokeColorArgb: 0xFF00_00FF,
        lineWidth: 1,
        zIndex: zIndex,
        isHidden: hidden,
        consumeTapEvents: true,
        level: level
    )
}

@MainActor
final class RunnerTests: XCTestCase {
    func testDisposeRemovesEveryHandler() throws {
        let messenger = ConnectionCountingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.showsUserLocation = true
        XCTAssertFalse(messenger.live.isEmpty)

        try host.dispose()

        XCTAssertEqual(messenger.live, [])
        XCTAssertNil(host.mapView.delegate)
        XCTAssertFalse(host.mapView.showsUserLocation)
    }

    func testGeodesicPolylineIsSafeToStyle() {
        let polyline = makeStyledPolyline(fromPlatform: PlatformPolyline(
            id: "arc",
            coordinates: [
                PlatformCoordinate(latitude: 40.6, longitude: -73.8),
                PlatformCoordinate(latitude: 51.5, longitude: -0.1),
            ],
            strokeColorArgb: 0xFF00_00FF,
            lineWidth: 2,
            lineCap: .round,
            lineJoin: .round,
            isHidden: false,
            consumeTapEvents: false,
            isGeodesic: true,
            level: .aboveRoads,
            zIndex: 0,
            lineDashPattern: [6, 3]
        ))

        XCTAssertEqual(polyline.dashPattern, [6, 3])
        XCTAssertGreaterThan(polyline.pointCount, 2)
    }

    func testPolygonSnapshotOutlineIsOneClosedRing() {
        let polygon = FlutterPolygon(fromPlatform: PlatformPolygon(
            id: "triangle",
            coordinates: [
                PlatformCoordinate(latitude: 0, longitude: 0),
                PlatformCoordinate(latitude: 1, longitude: 0),
                PlatformCoordinate(latitude: 0, longitude: 1),
            ],
            interiorPolygons: [],
            fillColorArgb: 0xFF00_00FF,
            strokeColorArgb: 0xFF00_00FF,
            lineWidth: 1,
            zIndex: 0,
            isHidden: false,
            consumeTapEvents: false,
            level: .aboveRoads
        ))
        var elements: [String] = []

        polygon.outlinePath { CGPoint(x: $0.longitude, y: $0.latitude) }.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: elements.append("M\(e.points[0].x),\(e.points[0].y)")
            case .addLineToPoint: elements.append("L\(e.points[0].x),\(e.points[0].y)")
            case .closeSubpath: elements.append("Z")
            default: elements.append("?")
            }
        }

        XCTAssertEqual(elements, ["M0.0,0.0", "L0.0,1.0", "L1.0,0.0", "Z"])
    }

    func testCalloutToggleReachesNative() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.updateAnnotations(toAdd: [annotation("a")], toChange: [], idsToRemove: [])

        try host.updateAnnotations(toAdd: [], toChange: [annotation("a", callout: true)], idsToRemove: [])

        XCTAssertEqual(host.annotationsById["a"]?.calloutConsumesTapEvents, true)
    }

    func testFirstUpdateAfterDragApplies() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.updateAnnotations(toAdd: [annotation("a", title: "A")], toChange: [], idsToRemove: [])
        let view = MKAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)
        host.mapView(host.mapView, annotationView: view, didChange: .ending, fromOldState: .dragging)

        try host.updateAnnotations(toAdd: [], toChange: [annotation("a", title: "B")], idsToRemove: [])

        XCTAssertEqual(host.annotationsById["a"]?.title, "B")
    }

    func testCalloutOffsetIgnoresViewPosition() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let flutterAnnotation = try FlutterAnnotation(fromPlatform: annotation("a"))
        let view = MKAnnotationView(annotation: flutterAnnotation, reuseIdentifier: nil)
        view.frame = CGRect(x: 300, y: 120, width: 40, height: 40)

        host.initInfoWindow(annotation: flutterAnnotation, annotationView: view)

        XCTAssertEqual(view.calloutOffset, .zero)
    }

    func testHiddenOverlayDoesNotConsumeTap() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateCircles(toAdd: [circle("hidden", hidden: true)], toChange: [], idsToRemove: [])
        let mapTap = messenger.expectation(for: "onMapTap", in: self)

        TouchHandler.handleMapTap(
            at: CLLocationCoordinate2D(latitude: 0, longitude: 0), flutterApi: host.flutterApi, in: host.mapView)

        await fulfillment(of: [mapTap], timeout: 2)
        XCTAssertTrue(messenger.args(of: "onCircleTap").isEmpty)
    }

    func testOnlyTopMostOverlayReceivesTap() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateCircles(
            toAdd: [circle("high", zIndex: 1), circle("low", zIndex: 0)], toChange: [], idsToRemove: [])
        let circleTap = messenger.expectation(for: "onCircleTap", in: self)

        TouchHandler.handleMapTap(
            at: CLLocationCoordinate2D(latitude: 0, longitude: 0), flutterApi: host.flutterApi, in: host.mapView)

        await fulfillment(of: [circleTap], timeout: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(messenger.args(of: "onCircleTap").map { $0.compactMap { $0 as? String } }, [["high"]])
    }

    func testTrackingModeReappliedOnlyWhenItChanges() throws {
        let view = CountingMapView()

        try view.apply(configuration: configuration(tracking: .follow))
        try view.apply(configuration: configuration(scale: true, tracking: .follow))
        XCTAssertEqual(view.trackingModeSets, 1)

        try view.apply(configuration: configuration(scale: true, tracking: .none))
        XCTAssertEqual(view.trackingModeSets, 2)
    }

    func testLabelsLevelOverlayTakesTapBeforeRoadsLevel() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateCircles(
            toAdd: [circle("roads", zIndex: 5, level: .aboveRoads), circle("labels", zIndex: 0, level: .aboveLabels)],
            toChange: [], idsToRemove: [])
        let circleTap = messenger.expectation(for: "onCircleTap", in: self)

        TouchHandler.handleMapTap(
            at: CLLocationCoordinate2D(latitude: 0, longitude: 0), flutterApi: host.flutterApi, in: host.mapView)

        await fulfillment(of: [circleTap], timeout: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(messenger.args(of: "onCircleTap").map { $0.compactMap { $0 as? String } }, [["labels"]])
    }

    func testSnapshotInputCarriesMapConfigurationAndAppearance() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        try host.mapView.apply(configuration: configuration(kind: .imagery))
        host.mapView.appearance = NSAppearance(named: .darkAqua)

        let input = host.snapshotInput(PlatformSnapshotOptions(
            showsPointsOfInterest: true, showsAnnotations: false, showsOverlays: false))
        let options = try MapKitViewHost.makeSnapshotOptions(input)

        XCTAssertTrue(options.preferredConfiguration is MKImageryMapConfiguration)
        XCTAssertEqual(options.appearance?.name, .darkAqua)
    }

    func testAddingATileOverlayIdTwiceThrowsAndKeepsTheFirst() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let tiles = PlatformTileOverlay(
            id: "osm",
            urlTemplate: "https://tile.example.com/{z}/{x}/{y}.png",
            minimumZ: 0,
            maximumZ: 19,
            tileSize: 256,
            canReplaceMapContent: false,
            alpha: 1,
            level: .aboveRoads
        )

        try host.addTileOverlay(overlay: tiles)
        XCTAssertThrowsError(try host.addTileOverlay(overlay: tiles)) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "duplicate-id")
        }

        XCTAssertEqual(host.mapView.overlays.count, 1)
        XCTAssertTrue(try host.removeTileOverlay(tileOverlayId: "osm"))
        XCTAssertFalse(try host.removeTileOverlay(tileOverlayId: "osm"))
        XCTAssertEqual(host.mapView.overlays.count, 0)
    }

    func testTrackingButtonAppliesOnMacOS() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)

        try host.mapView.apply(configuration: configuration(trackingButton: true))

        XCTAssertTrue(host.mapView.showsUserTrackingButton)
    }

    func testSnapshotOptionsFollowMapStyleCameraAndAppearance() throws {
        let input = MapKitViewHost.SnapshotInput(
            region: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.0),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)),
            size: CGSize(width: 200, height: 200),
            displayScale: 0,
            camera: PlatformMapCamera(
                centerCoordinate: PlatformCoordinate(latitude: 37.33, longitude: -122.0),
                distance: 2000,
                heading: 90,
                pitch: 30),
            configuration: configuration(kind: .imagery),
            isDark: true,
            options: PlatformSnapshotOptions(
                showsPointsOfInterest: true, showsAnnotations: false, showsOverlays: false))

        let options = try MapKitViewHost.makeSnapshotOptions(input)

        XCTAssertTrue(options.preferredConfiguration is MKImageryMapConfiguration)
        XCTAssertEqual(options.camera.heading, 90, accuracy: 0.001)
        XCTAssertEqual(options.appearance?.name, .darkAqua)
    }

    func testSelectAndDeselectReachDart() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateAnnotations(toAdd: [annotation("a")], toChange: [], idsToRemove: [])
        let view = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)
        let selected = messenger.expectation(for: "onAnnotationSelect", in: self)
        let deselected = messenger.expectation(for: "onAnnotationDeselect", in: self)

        host.mapView(host.mapView, didSelect: view)
        host.mapView(host.mapView, didDeselect: view)

        await fulfillment(of: [selected, deselected], timeout: 2, enforceOrder: true)
        XCTAssertNil(host.currentlySelectedAnnotation)
    }

    func testVisibleRegionChangeStreamsCamera() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        try await Task.sleep(for: .milliseconds(200))
        let before = messenger.args(of: "onCameraMove").count
        let moved = messenger.expectation(for: "onCameraMove", in: self)

        (host as MKMapViewDelegate).mapViewDidChangeVisibleRegion?(host.mapView)

        await fulfillment(of: [moved], timeout: 2)
        XCTAssertEqual(messenger.args(of: "onCameraMove").count, before + 1)
    }

    func testCrossTypeOverlaysShareIdIndependently() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let poly = PlatformPolyline(
            id: "zone",
            coordinates: [
                PlatformCoordinate(latitude: 0, longitude: 0),
                PlatformCoordinate(latitude: 1, longitude: 1),
            ],
            strokeColorArgb: 0xFF00_00FF,
            lineWidth: 2,
            lineCap: .round,
            lineJoin: .round,
            isHidden: false,
            consumeTapEvents: false,
            isGeodesic: false,
            level: .aboveRoads,
            zIndex: 0
        )
        let gon = PlatformPolygon(
            id: "zone",
            coordinates: [
                PlatformCoordinate(latitude: 0, longitude: 0),
                PlatformCoordinate(latitude: 1, longitude: 0),
                PlatformCoordinate(latitude: 0, longitude: 1),
            ],
            interiorPolygons: [],
            fillColorArgb: 0xFF00_00FF,
            strokeColorArgb: 0xFF00_00FF,
            lineWidth: 1,
            zIndex: 0,
            isHidden: false,
            consumeTapEvents: false,
            level: .aboveRoads
        )

        try host.updatePolylines(toAdd: [poly], toChange: [], idsToRemove: [])
        try host.updatePolygons(toAdd: [gon], toChange: [], idsToRemove: [])
        try host.updateCircles(toAdd: [circle("zone")], toChange: [], idsToRemove: [])
        XCTAssertEqual(host.mapView.overlays.count, 3)

        try host.updatePolylines(toAdd: [], toChange: [], idsToRemove: ["zone"])
        XCTAssertEqual(host.mapView.overlays.count, 2)
        XCTAssertNil(host.polylinesById["zone"])
        XCTAssertNotNil(host.polygonsById["zone"])
        XCTAssertNotNil(host.circlesById["zone"])
    }

    func testPolygonOutlineIncludesInteriorHoleAndEvenOddFillRule() {
        let polygon = FlutterPolygon(fromPlatform: PlatformPolygon(
            id: "donut",
            coordinates: [
                PlatformCoordinate(latitude: 0, longitude: 0),
                PlatformCoordinate(latitude: 4, longitude: 0),
                PlatformCoordinate(latitude: 0, longitude: 4),
            ],
            interiorPolygons: [
                [
                    PlatformCoordinate(latitude: 1, longitude: 1),
                    PlatformCoordinate(latitude: 2, longitude: 1),
                    PlatformCoordinate(latitude: 1, longitude: 2),
                ],
            ],
            fillColorArgb: 0xFF00_00FF,
            strokeColorArgb: 0xFF00_00FF,
            lineWidth: 1,
            zIndex: 0,
            isHidden: false,
            consumeTapEvents: false,
            level: .aboveRoads
        ))
        var elements: [String] = []
        polygon.outlinePath { CGPoint(x: $0.longitude, y: $0.latitude) }.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: elements.append("M\(e.points[0].x),\(e.points[0].y)")
            case .addLineToPoint: elements.append("L\(e.points[0].x),\(e.points[0].y)")
            case .closeSubpath: elements.append("Z")
            default: elements.append("?")
            }
        }

        XCTAssertEqual(
            elements,
            ["M0.0,0.0", "L0.0,4.0", "L4.0,0.0", "Z", "M1.0,1.0", "L1.0,2.0", "L2.0,1.0", "Z"]
        )
    }

    func testSelectionReportsWhetherItTook() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        var hidden = annotation("hidden")
        hidden = PlatformAnnotation(
            id: hidden.id,
            coordinate: hidden.coordinate,
            icon: hidden.icon,
            calloutConsumesTapEvents: false,
            alpha: 1,
            anchorPointX: 0.5,
            anchorPointY: 1,
            isDraggable: false,
            isHidden: true,
            zPriority: 500
        )
        try host.updateAnnotations(
            toAdd: [hidden, annotation("unattached"), annotation("visible")], toChange: [], idsToRemove: [])

        XCTAssertFalse(try host.selectAnnotation(annotationId: "hidden"))
        XCTAssertNil(host.currentlySelectedAnnotation)
        XCTAssertFalse(try host.selectAnnotation(annotationId: "missing"))

        if let unattached = host.annotationsById["unattached"] {
            host.mapView.removeAnnotation(unattached)
        }
        XCTAssertFalse(try host.selectAnnotation(annotationId: "unattached"))

        XCTAssertTrue(try host.selectAnnotation(annotationId: "visible"))
        XCTAssertTrue(try host.isAnnotationSelected(annotationId: "visible"))
        XCTAssertTrue(try host.deselectAnnotation(annotationId: "visible"))
        XCTAssertFalse(try host.isAnnotationSelected(annotationId: "visible"))
        XCTAssertFalse(try host.deselectAnnotation(annotationId: "missing"))
    }

    func testIconTypeSwapWhileSelectedSuppressesSelectionCallbacks() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateAnnotations(toAdd: [annotation("a", title: "Pin")], toChange: [], idsToRemove: [])
        let initialView = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)
        let initialSelected = messenger.expectation(for: "onAnnotationSelect", in: self)
        host.mapView(host.mapView, didSelect: initialView)
        await fulfillment(of: [initialSelected], timeout: 2)

        let selectCountBefore = messenger.args(of: "onAnnotationSelect").count
        let deselectCountBefore = messenger.args(of: "onAnnotationDeselect").count

        let customIcon = PlatformAnnotation(
            id: "a",
            coordinate: PlatformCoordinate(latitude: 1, longitude: 2),
            icon: pngIcon(),
            title: "Pin",
            calloutConsumesTapEvents: false,
            alpha: 1,
            anchorPointX: 0.5,
            anchorPointY: 1,
            isDraggable: true,
            isHidden: false,
            zPriority: 500
        )
        try host.updateAnnotations(toAdd: [], toChange: [customIcon], idsToRemove: [])
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(messenger.args(of: "onAnnotationSelect").count, selectCountBefore)
        XCTAssertEqual(messenger.args(of: "onAnnotationDeselect").count, deselectCountBefore)
        XCTAssertNil(host.suppressSelectionCallbacksForAnnotationId)
    }

    func testIconTypeSwapToHiddenSendsDeselect() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        try host.updateAnnotations(toAdd: [annotation("a", title: "Pin")], toChange: [], idsToRemove: [])
        let initialView = MKMarkerAnnotationView(annotation: host.annotationsById["a"], reuseIdentifier: nil)
        let initialSelected = messenger.expectation(for: "onAnnotationSelect", in: self)
        host.mapView(host.mapView, didSelect: initialView)
        await fulfillment(of: [initialSelected], timeout: 2)

        let deselected = messenger.expectation(for: "onAnnotationDeselect", in: self)
        let hiddenCustomIcon = PlatformAnnotation(
            id: "a",
            coordinate: PlatformCoordinate(latitude: 1, longitude: 2),
            icon: pngIcon(),
            title: "Pin",
            calloutConsumesTapEvents: false,
            alpha: 1,
            anchorPointX: 0.5,
            anchorPointY: 1,
            isDraggable: true,
            isHidden: true,
            zPriority: 500
        )
        try host.updateAnnotations(toAdd: [], toChange: [hiddenCustomIcon], idsToRemove: [])
        await fulfillment(of: [deselected], timeout: 2)

        XCTAssertEqual(messenger.args(of: "onAnnotationDeselect").count, 1)
        XCTAssertNil(host.currentlySelectedAnnotation)
    }

    func testTakeSnapshotRejectsZeroSizedMapView() {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        host.mapView.frame = .zero
        let exp = expectation(description: "snapshot fails on zero size")

        host.takeSnapshot(
            options: PlatformSnapshotOptions(
                showsPointsOfInterest: true,
                showsAnnotations: true,
                showsOverlays: true
            )
        ) { result in
            switch result {
            case .success:
                XCTFail("Expected failure for zero-sized map view")
            case .failure(let error as MapKitHostError):
                XCTAssertEqual(error.code, "snapshot-failed")
            case .failure(let error):
                XCTFail("Unexpected error type: \(error)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
    }
}

@MainActor
final class NaturalApiTests: XCTestCase {
    func testShowsUserLocationAppliesWithoutPrompting() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.mapView.apply(configuration: configuration(userLocation: true))
        XCTAssertTrue(host.mapView.showsUserLocation)
        try host.mapView.apply(configuration: configuration(userLocation: false))
        XCTAssertFalse(host.mapView.showsUserLocation)
    }

    private func polylineHost(lineWidth: Double) throws -> (MapKitViewHost, RecordingMessenger) {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        let line = PlatformPolyline(
            id: "line",
            coordinates: [PlatformCoordinate(latitude: 0, longitude: -0.4), PlatformCoordinate(latitude: 0, longitude: 0.4)],
            strokeColorArgb: 0xFF00_00FF, lineWidth: lineWidth, lineCap: .round, lineJoin: .round, isHidden: false,
            consumeTapEvents: true, isGeodesic: false, level: .aboveRoads, zIndex: 0)
        try host.updatePolylines(toAdd: [line], toChange: [], idsToRemove: [])
        return (host, messenger)
    }

    private func tap(_ host: MapKitViewHost, pointsBelowLine offset: CGFloat) -> CLLocationCoordinate2D {
        let center = host.mapView.convert(CLLocationCoordinate2D(latitude: 0, longitude: 0), toPointTo: host.mapView)
        return host.mapView.convert(CGPoint(x: center.x, y: center.y + offset), toCoordinateFrom: host.mapView)
    }

    func testWidePolylineTakesTapsAcrossItsVisibleStroke() async throws {
        let (host, messenger) = try polylineHost(lineWidth: 40)
        let polylineTap = messenger.expectation(for: "onPolylineTap", in: self)
        TouchHandler.handleMapTap(at: tap(host, pointsBelowLine: 15), flutterApi: host.flutterApi, in: host.mapView)
        await fulfillment(of: [polylineTap], timeout: 2)
        XCTAssertTrue(messenger.args(of: "onMapTap").isEmpty)
    }

    func testThinPolylineKeepsTheEightPointMinimum() async throws {
        let (host, messenger) = try polylineHost(lineWidth: 2)
        let mapTap = messenger.expectation(for: "onMapTap", in: self)
        TouchHandler.handleMapTap(at: tap(host, pointsBelowLine: 15), flutterApi: host.flutterApi, in: host.mapView)
        await fulfillment(of: [mapTap], timeout: 2)
        XCTAssertTrue(messenger.args(of: "onPolylineTap").isEmpty)
        let polylineTap = messenger.expectation(for: "onPolylineTap", in: self)
        TouchHandler.handleMapTap(at: tap(host, pointsBelowLine: 6), flutterApi: host.flutterApi, in: host.mapView)
        await fulfillment(of: [polylineTap], timeout: 2)
    }

    func testClickOnAnAnnotationViewIsNotAMapTap() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        let pin = MKAnnotationView(annotation: try FlutterAnnotation(fromPlatform: annotation("a")), reuseIdentifier: nil)
        pin.frame = CGRect(x: 100, y: 100, width: 40, height: 40)
        host.mapView.addSubview(pin)
        let noMapTap = messenger.expectation(for: "onMapTap", in: self)
        noMapTap.isInverted = true

        TouchHandler.handleMapTaps(tap: FixedPointClick(at: CGPoint(x: 120, y: 120)), flutterApi: host.flutterApi, in: host.mapView)

        await fulfillment(of: [noMapTap], timeout: 0.5)
        let mapTap = messenger.expectation(for: "onMapTap", in: self)
        TouchHandler.handleMapTaps(tap: FixedPointClick(at: CGPoint(x: 300, y: 300)), flutterApi: host.flutterApi, in: host.mapView)
        await fulfillment(of: [mapTap], timeout: 2)
    }

    private func clickWindow(_ host: MapKitViewHost) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host.mapView
        window.orderBack(nil)
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    private func click(_ window: NSWindow, count: Int) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 200, y: 200), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: count, pressure: 1)))
        }
    }

    func testSingleClickIsAMapTap() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        let window = clickWindow(host)
        let mapTap = messenger.expectation(for: "onMapTap", in: self)

        try click(window, count: 1)

        await fulfillment(of: [mapTap], timeout: NSEvent.doubleClickInterval + 2)
    }

    func testDoubleClickIsNotAMapTap() async throws {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        let window = clickWindow(host)
        let noMapTap = messenger.expectation(for: "onMapTap", in: self)
        noMapTap.isInverted = true

        try click(window, count: 1)
        try click(window, count: 2)

        await fulfillment(of: [noMapTap], timeout: NSEvent.doubleClickInterval + 1)
    }

    func testDoubleClickStillZoomsTheMap() async throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let window = clickWindow(host)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)), animated: false)
        let before = host.mapView.camera.centerCoordinateDistance

        try click(window, count: 1)
        try click(window, count: 2)
        try await Task.sleep(for: .seconds(1.5))

        XCTAssertLessThan(host.mapView.camera.centerCoordinateDistance, before * 0.9)
    }

    func testUndecodableImageBytesFailTheWholeUpdate() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let broken = PlatformAnnotation(
            id: "broken", coordinate: PlatformCoordinate(latitude: 0, longitude: 0),
            icon: PlatformAnnotationIcon(type: .image, imageBytes: FlutterStandardTypedData(bytes: Data([1, 2, 3]))),
            calloutConsumesTapEvents: false, alpha: 1, anchorPointX: 0.5, anchorPointY: 1,
            isDraggable: false, isHidden: false, zPriority: 500)
        XCTAssertThrowsError(
            try host.updateAnnotations(toAdd: [annotation("ok"), broken], toChange: [], idsToRemove: [])
        ) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "invalid-icon")
        }
        XCTAssertTrue(host.annotationsById.isEmpty)
        XCTAssertTrue(host.mapView.annotations.isEmpty)
    }

    func testUnknownSymbolFailsInsteadOfDrawingAPlainMarker() {
        XCTAssertThrowsError(try AnnotationIcon(fromPlatform: PlatformAnnotationIcon(
            type: .marker, glyphSystemImage: "no.such.symbol.xyz"))
        ) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "invalid-icon")
        }
        XCTAssertNoThrow(try AnnotationIcon(fromPlatform: PlatformAnnotationIcon(
            type: .marker, glyphSystemImage: "cup.and.saucer.fill")))
    }

    func testOpenLookAroundIsUnsupportedOnMacOS() {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let done = expectation(description: "look around")
        host.openLookAround(coordinate: PlatformCoordinate(latitude: 0, longitude: 0)) { result in
            switch result {
            case .success(let value): XCTFail("expected unsupported-platform, got \(value)")
            case .failure(let error): XCTAssertEqual((error as? MapKitHostError)?.code, "unsupported-platform")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testRejectedZoomRangeThrowsAndLeavesTheMapUnchanged() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.mapView.apply(configuration: configuration(scale: false))
        var invalid = configuration(scale: true)
        invalid.cameraZoomRange = PlatformCameraZoomRange(minCenterCoordinateDistance: 10, maxCenterCoordinateDistance: 5)
        XCTAssertThrowsError(try host.mapView.apply(configuration: invalid)) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "invalid-argument")
        }
        XCTAssertFalse(host.mapView.showsScale)
    }

    func testRejectedCameraBoundaryThrows() {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        let before = host.mapView.cameraBoundary
        var invalid = configuration()
        invalid.cameraBoundary = PlatformCoordinateRegion(
            center: PlatformCoordinate(latitude: .nan, longitude: 0),
            span: PlatformCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
        XCTAssertThrowsError(try host.mapView.apply(configuration: invalid)) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "invalid-argument")
        }
        XCTAssertTrue(host.mapView.cameraBoundary === before)
    }

    func testFollowWithHeadingIsUnsupportedOnMacOS() {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        XCTAssertThrowsError(try host.mapView.apply(configuration: configuration(tracking: .followWithHeading))) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "unsupported-platform")
        }
        XCTAssertEqual(host.mapView.userTrackingMode, .none)
    }

    func testCameraAndRegionAreNilBeforeLayout() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        XCTAssertNil(try host.getCamera())
        XCTAssertNil(try host.getRegion())

        host.mapView.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertGreaterThan(try XCTUnwrap(try host.getCamera()).distance, 0)
        XCTAssertGreaterThan(try XCTUnwrap(try host.getRegion()).span.latitudeDelta, 0)
    }

    private func creationParams(center: PlatformCoordinate) -> PlatformMapViewCreationParams {
        PlatformMapViewCreationParams(
            initialCamera: PlatformMapCamera(centerCoordinate: center, distance: 500_000, heading: 0, pitch: 0),
            configuration: configuration(), annotations: [], polylines: [], polygons: [], circles: [])
    }

    private func layOut(_ host: MapKitViewHost) {
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.needsLayout = true
        host.mapView.layoutSubtreeIfNeeded()
    }

    func testInitialCameraAppliesAtFirstLayout() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.initialize(params: creationParams(center: PlatformCoordinate(latitude: 10, longitude: 10)))

        layOut(host)

        let center = try XCTUnwrap(try host.getCamera()).centerCoordinate
        XCTAssertEqual(center.latitude, 10, accuracy: 0.01)
        XCTAssertEqual(center.longitude, 10, accuracy: 0.01)
    }

    func testCameraMovesBeforeFirstLayoutSurviveIt() throws {
        let target = PlatformCoordinate(latitude: 40, longitude: 20)
        let moves: [(String, (MapKitViewHost) throws -> Void)] = [
            ("setCamera", {
                try $0.setCamera(
                    camera: PlatformMapCamera(centerCoordinate: target, distance: 50_000, heading: 0, pitch: 0), animated: true)
            }),
            ("setRegion", {
                try $0.setRegion(
                    region: PlatformCoordinateRegion(
                        center: target, span: PlatformCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)),
                    animated: true)
            }),
            ("setCenter", { try $0.setCenter(coordinate: target, animated: true) }),
        ]
        for (name, move) in moves {
            let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
            try host.initialize(params: creationParams(center: PlatformCoordinate(latitude: 10, longitude: 10)))
            try move(host)

            layOut(host)

            let center = try XCTUnwrap(try host.getCamera()).centerCoordinate
            XCTAssertEqual(center.latitude, 40, accuracy: 0.01, name)
            XCTAssertEqual(center.longitude, 20, accuracy: 0.01, name)
        }
    }

    func testSetCenterBeforeFirstLayoutKeepsTheInitialDistance() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.initialize(params: creationParams(center: PlatformCoordinate(latitude: 10, longitude: 10)))
        try host.setCenter(coordinate: PlatformCoordinate(latitude: 40, longitude: 20), animated: false)

        layOut(host)

        XCTAssertEqual(try XCTUnwrap(try host.getCamera()).distance, 500_000, accuracy: 5_000)
    }

    func testCameraMoveBetweenResizeAndFirstLayoutWins() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        try host.initialize(params: creationParams(center: PlatformCoordinate(latitude: 10, longitude: 10)))
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        try host.setCamera(
            camera: PlatformMapCamera(
                centerCoordinate: PlatformCoordinate(latitude: 40, longitude: 20), distance: 50_000, heading: 0, pitch: 0),
            animated: false)

        layOut(host)

        let center = try XCTUnwrap(try host.getCamera()).centerCoordinate
        XCTAssertEqual(center.latitude, 40, accuracy: 0.01)
        XCTAssertEqual(center.longitude, 20, accuracy: 0.01)
    }

    func testCameraMovesWhileZeroSizedStayBoundedAndKeepTheirEffect() throws {
        let camera = PlatformMapCamera(
            centerCoordinate: PlatformCoordinate(latitude: 30, longitude: 30), distance: 80_000, heading: 0, pitch: 0)
        let region = PlatformCoordinateRegion(
            center: PlatformCoordinate(latitude: 35, longitude: 25), span: PlatformCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2))
        func moves(_ host: MapKitViewHost) throws {
            for i in 0..<50 {
                try host.setCenter(coordinate: PlatformCoordinate(latitude: Double(i % 7), longitude: 1), animated: false)
                try host.setRegion(region: region, animated: false)
                try host.setCamera(camera: camera, animated: false)
            }
            try host.setRegion(region: region, animated: false)
            try host.setCenter(coordinate: PlatformCoordinate(latitude: 41, longitude: 21), animated: false)
        }
        let reference = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        layOut(reference)
        try moves(reference)
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        layOut(host)
        host.mapView.frame = .zero

        try moves(host)
        XCTAssertLessThanOrEqual(host.mapView.pendingMoves.count, 3)
        layOut(host)

        let want = try XCTUnwrap(try reference.getCamera())
        let got = try XCTUnwrap(try host.getCamera())
        XCTAssertEqual(got.centerCoordinate.latitude, 41, accuracy: 0.01)
        XCTAssertEqual(got.centerCoordinate.longitude, 21, accuracy: 0.01)
        XCTAssertEqual(got.distance, want.distance, accuracy: want.distance * 0.01)
    }

    func testImageAnchorPointIsHonoredOnMacOS() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        func pin(_ anchorY: Double) -> PlatformAnnotation {
            PlatformAnnotation(
                id: "img", coordinate: PlatformCoordinate(latitude: 0, longitude: 0), icon: pngIcon(width: 20, height: 40),
                calloutConsumesTapEvents: false, alpha: 1, anchorPointX: 0.5, anchorPointY: anchorY,
                isDraggable: false, isHidden: false, zPriority: 500)
        }
        try host.updateAnnotations(toAdd: [pin(1)], toChange: [], idsToRemove: [])
        let bottomCenter = host.getAnnotationView(annotation: try XCTUnwrap(host.annotationsById["img"]))
        XCTAssertEqual(bottomCenter.centerOffset, CGPoint(x: 0, y: -20))

        try host.updateAnnotations(toAdd: [], toChange: [pin(0.5)], idsToRemove: [])
        let centered = host.getAnnotationView(annotation: try XCTUnwrap(host.annotationsById["img"]))
        XCTAssertEqual(centered.centerOffset, .zero)
    }

    func testUserTrackingModeChangeReachesDart() async {
        let messenger = RecordingMessenger()
        let host = MapKitViewHost(messenger: messenger, id: 0)
        let changed = messenger.expectation(for: "onUserTrackingModeChanged", in: self)

        host.mapView(host.mapView, didChange: .none, animated: true)

        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(
            messenger.args(of: "onUserTrackingModeChanged").first?.first as? PlatformUserTrackingMode, PlatformUserTrackingMode.none)
    }

    func testUnavailablePointOfInterestCategoryThrowsInsteadOfDropping() throws {
        let filter = PlatformPointOfInterestFilter(mode: .including, categories: [.castle])
        XCTAssertThrowsError(try FlutterMapView.poiFilter(from: filter, category: { _ in nil })) { error in
            XCTAssertEqual((error as? MapKitHostError)?.code, "unavailable-poi-category")
        }
        XCTAssertNotNil(try FlutterMapView.poiFilter(from: filter))
    }
}

@MainActor
final class SnapshotCompositingTests: XCTestCase {
    /// A 400×400 pt map over open ocean at 0°,0° with a red image pin centred
    /// at 0.25°N 0.25°W (upper-left quadrant) and a green polygon around
    /// 0.2°S 0.2°E (lower-right quadrant).
    private func compositingHost() throws -> MapKitViewHost {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        try host.updateAnnotations(toAdd: [PlatformAnnotation(
            id: "pin", coordinate: PlatformCoordinate(latitude: 0.25, longitude: -0.25),
            icon: pngIcon(width: 30, height: 30), calloutConsumesTapEvents: false, alpha: 1,
            anchorPointX: 0.5, anchorPointY: 0.5, isDraggable: false, isHidden: false, zPriority: 500)],
            toChange: [], idsToRemove: [])
        try host.updatePolygons(toAdd: [PlatformPolygon(
            id: "square",
            coordinates: [
                PlatformCoordinate(latitude: -0.1, longitude: 0.1),
                PlatformCoordinate(latitude: -0.1, longitude: 0.3),
                PlatformCoordinate(latitude: -0.3, longitude: 0.3),
                PlatformCoordinate(latitude: -0.3, longitude: 0.1),
            ],
            interiorPolygons: [], fillColorArgb: 0xFF00_FF00, strokeColorArgb: 0xFF00_FF00, lineWidth: 1,
            zIndex: 0, isHidden: false, consumeTapEvents: false, level: .aboveRoads)],
            toChange: [], idsToRemove: [])
        return host
    }

    private func snapshot(_ host: MapKitViewHost, annotations: Bool, overlays: Bool) throws -> NSBitmapImageRep {
        let exp = expectation(description: "snapshot")
        var bytes: Data?
        host.takeSnapshot(options: PlatformSnapshotOptions(
            showsPointsOfInterest: false, showsAnnotations: annotations, showsOverlays: overlays)) { result in
            if case .success(let data) = result { bytes = data.data }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 20)
        return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(bytes)))
    }

    /// The pixel at `point` (in snapshot points, origin top-left) of `rep`.
    private func color(_ rep: NSBitmapImageRep, at point: CGPoint) throws -> NSColor {
        let scale = CGFloat(rep.pixelsWide) / 400
        let pixel = try XCTUnwrap(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return try XCTUnwrap(pixel.usingColorSpace(.sRGB))
    }

    private func isRed(_ c: NSColor) -> Bool { c.redComponent > 0.8 && c.greenComponent < 0.3 && c.blueComponent < 0.3 }
    private func isGreen(_ c: NSColor) -> Bool { c.greenComponent > 0.8 && c.redComponent < 0.3 && c.blueComponent < 0.3 }

    func testMacOSSnapshotCompositesAnnotationsAndOverlays() throws {
        let host = try compositingHost()
        let pin = host.mapView.convert(CLLocationCoordinate2D(latitude: 0.25, longitude: -0.25), toPointTo: host.mapView)
        let square = host.mapView.convert(CLLocationCoordinate2D(latitude: -0.2, longitude: 0.2), toPointTo: host.mapView)
        // MKMapView on macOS is unflipped; snapshot pixels run top-down.
        let pinTop = CGPoint(x: pin.x, y: host.mapView.isFlipped ? pin.y : 400 - pin.y)
        let squareTop = CGPoint(x: square.x, y: host.mapView.isFlipped ? square.y : 400 - square.y)

        let rep = try snapshot(host, annotations: true, overlays: true)

        let pinColor = try color(rep, at: pinTop)
        let squareColor = try color(rep, at: squareTop)
        XCTAssertTrue(isRed(pinColor), "pin pixel at \(pinTop) is \(pinColor)")
        XCTAssertTrue(isGreen(squareColor), "polygon pixel at \(squareTop) is \(squareColor)")
        let mirrored = try color(rep, at: CGPoint(x: pinTop.x, y: 400 - pinTop.y))
        XCTAssertFalse(isRed(mirrored), "pin drawn upside down at \(400 - pinTop.y)")
    }

    func testMacOSSnapshotDrawsMarkerAnnotations() throws {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        try host.updateAnnotations(toAdd: [PlatformAnnotation(
            id: "marker", coordinate: PlatformCoordinate(latitude: 0.25, longitude: -0.25),
            icon: PlatformAnnotationIcon(type: .marker, markerTintArgb: 0xFFFF_0000), calloutConsumesTapEvents: false,
            alpha: 1, anchorPointX: 0.5, anchorPointY: 1, isDraggable: false, isHidden: false, zPriority: 500)],
            toChange: [], idsToRemove: [])
        let pin = host.mapView.convert(CLLocationCoordinate2D(latitude: 0.25, longitude: -0.25), toPointTo: host.mapView)
        let pinTop = CGPoint(x: pin.x, y: host.mapView.isFlipped ? pin.y : 400 - pin.y)

        let rep = try snapshot(host, annotations: true, overlays: false)

        var reddish = 0
        for dy in stride(from: -20, through: 20, by: 2) {
            for dx in stride(from: -20, through: 20, by: 2) {
                let c = try color(rep, at: CGPoint(x: pinTop.x + CGFloat(dx), y: pinTop.y + CGFloat(dy)))
                if c.redComponent > 0.7 && c.greenComponent < 0.4 && c.blueComponent < 0.4 { reddish += 1 }
            }
        }
        XCTAssertGreaterThan(reddish, 10, "red marker balloon pixels around \(pinTop)")
    }

    func testMacOSSnapshotDrawsAnnotationsAboveOverlays() throws {
        let host = try compositingHost()
        try host.updateAnnotations(toAdd: [PlatformAnnotation(
            id: "inside", coordinate: PlatformCoordinate(latitude: -0.2, longitude: 0.2),
            icon: pngIcon(width: 30, height: 30), calloutConsumesTapEvents: false, alpha: 1,
            anchorPointX: 0.5, anchorPointY: 0.5, isDraggable: false, isHidden: false, zPriority: 500)],
            toChange: [], idsToRemove: [])
        let inside = host.mapView.convert(CLLocationCoordinate2D(latitude: -0.2, longitude: 0.2), toPointTo: host.mapView)
        let insideTop = CGPoint(x: inside.x, y: host.mapView.isFlipped ? inside.y : 400 - inside.y)

        let rep = try snapshot(host, annotations: true, overlays: true)

        let c = try color(rep, at: insideTop)
        XCTAssertTrue(isRed(c), "pin inside the polygon is drawn under it: \(c)")
    }

    private func oceanHost() -> MapKitViewHost {
        let host = MapKitViewHost(messenger: RecordingMessenger(), id: 0)
        host.mapView.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        host.mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        return host
    }

    private func topLeft(_ host: MapKitViewHost, _ latitude: Double, _ longitude: Double) -> CGPoint {
        let p = host.mapView.convert(CLLocationCoordinate2D(latitude: latitude, longitude: longitude), toPointTo: host.mapView)
        return CGPoint(x: p.x, y: host.mapView.isFlipped ? p.y : 400 - p.y)
    }

    private func isBlue(_ c: NSColor) -> Bool { c.blueComponent > 0.8 && c.redComponent < 0.3 && c.greenComponent < 0.3 }

    func testSnapshotDrawsGradientPolylinesWithTheirGradient() throws {
        let host = oceanHost()
        try host.updatePolylines(toAdd: [PlatformPolyline(
            id: "route",
            coordinates: [PlatformCoordinate(latitude: 0, longitude: -0.4), PlatformCoordinate(latitude: 0, longitude: 0.4)],
            strokeColorArgb: 0xFF00_FF00, lineWidth: 12, lineCap: .butt, lineJoin: .round, isHidden: false,
            consumeTapEvents: false, isGeodesic: false, level: .aboveRoads, zIndex: 0,
            gradientColorsArgb: [0xFFFF_0000, 0xFF00_00FF])], toChange: [], idsToRemove: [])

        let rep = try snapshot(host, annotations: false, overlays: true)

        let start = try color(rep, at: topLeft(host, 0, -0.38))
        let end = try color(rep, at: topLeft(host, 0, 0.38))
        let middle = try color(rep, at: topLeft(host, 0, 0))
        XCTAssertTrue(isRed(start), "gradient start is \(start)")
        XCTAssertTrue(isBlue(end), "gradient end is \(end)")
        XCTAssertFalse(isGreen(middle), "gradient line drawn in its plain stroke color: \(middle)")
        XCTAssertGreaterThan(middle.redComponent, 0.3, "middle \(middle)")
        XCTAssertGreaterThan(middle.blueComponent, 0.3, "middle \(middle)")
    }

    func testSnapshotPaintsSharpMiterJoinTipsOfGradientPolylines() throws {
        let host = oceanHost()
        try host.updatePolylines(toAdd: [PlatformPolyline(
            id: "spike",
            coordinates: [
                PlatformCoordinate(latitude: 0.3, longitude: -0.08), PlatformCoordinate(latitude: -0.3, longitude: 0),
                PlatformCoordinate(latitude: 0.3, longitude: 0.08),
            ],
            strokeColorArgb: 0xFF00_FF00, lineWidth: 12, lineCap: .butt, lineJoin: .miter, isHidden: false,
            consumeTapEvents: false, isGeodesic: false, level: .aboveRoads, zIndex: 0,
            gradientColorsArgb: [0xFFFF_0000, 0xFF00_00FF])], toChange: [], idsToRemove: [])
        let joint = topLeft(host, -0.3, 0)

        let rep = try snapshot(host, annotations: false, overlays: true)

        // The miter tip reaches 6 / sin(7.6°) ≈ 45 pt below the joint; the segment strokes end ~13 pt below it.
        let tip = try color(rep, at: CGPoint(x: joint.x, y: joint.y + 30))
        XCTAssertGreaterThan(tip.redComponent, 0.3, "miter tip \(tip)")
        XCTAssertGreaterThan(tip.blueComponent, 0.3, "miter tip \(tip)")
        XCTAssertLessThan(tip.greenComponent, 0.3, "miter tip left unpainted: \(tip)")
    }

    func testSnapshotLeavesPolygonHolesOpen() throws {
        let host = oceanHost()
        try host.updatePolygons(toAdd: [PlatformPolygon(
            id: "donut",
            coordinates: [
                PlatformCoordinate(latitude: 0.3, longitude: -0.3), PlatformCoordinate(latitude: 0.3, longitude: 0.3),
                PlatformCoordinate(latitude: -0.3, longitude: 0.3), PlatformCoordinate(latitude: -0.3, longitude: -0.3),
            ],
            interiorPolygons: [[
                PlatformCoordinate(latitude: 0.1, longitude: -0.1), PlatformCoordinate(latitude: 0.1, longitude: 0.1),
                PlatformCoordinate(latitude: -0.1, longitude: 0.1), PlatformCoordinate(latitude: -0.1, longitude: -0.1),
            ]],
            fillColorArgb: 0xFF00_FF00, strokeColorArgb: 0xFF00_FF00, lineWidth: 1,
            zIndex: 0, isHidden: false, consumeTapEvents: false, level: .aboveRoads)], toChange: [], idsToRemove: [])

        let rep = try snapshot(host, annotations: false, overlays: true)

        let ring = try color(rep, at: topLeft(host, 0.2, 0.2))
        let hole = try color(rep, at: topLeft(host, 0, 0))
        XCTAssertTrue(isGreen(ring), "polygon ring is \(ring)")
        XCTAssertFalse(isGreen(hole), "polygon hole is filled: \(hole)")
    }

    func testMacOSSnapshotLeavesThemOutWhenTurnedOff() throws {
        let host = try compositingHost()
        let pin = host.mapView.convert(CLLocationCoordinate2D(latitude: 0.25, longitude: -0.25), toPointTo: host.mapView)
        let square = host.mapView.convert(CLLocationCoordinate2D(latitude: -0.2, longitude: 0.2), toPointTo: host.mapView)
        let pinTop = CGPoint(x: pin.x, y: host.mapView.isFlipped ? pin.y : 400 - pin.y)
        let squareTop = CGPoint(x: square.x, y: host.mapView.isFlipped ? square.y : 400 - square.y)

        let rep = try snapshot(host, annotations: false, overlays: false)

        XCTAssertFalse(isRed(try color(rep, at: pinTop)))
        XCTAssertFalse(isGreen(try color(rep, at: squareTop)))
    }
}

/// A click recognizer pinned to one location, so tap routing runs without events.
final class FixedPointClick: NSClickGestureRecognizer {
    private let point: CGPoint

    init(at point: CGPoint) {
        self.point = point
        super.init(target: nil, action: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func location(in view: NSView?) -> NSPoint { point }
}

final class CountingMapView: FlutterMapView {
    var trackingModeSets = 0
    override func setUserTrackingMode(_ mode: MKUserTrackingMode, animated: Bool) { trackingModeSets += 1 }
}

import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// What the generated channel handlers hold instead of the host. They live
/// until `cleanUpConnection`, and holding the host would keep it (and its
/// `MKMapView`) alive whenever `dispose` never arrives.
///
/// `@preconcurrency`: the engine calls handlers on the platform thread, as for
/// the host's own conformance.
@MainActor
final class WeakMapKitHostApi: @preconcurrency MapKitHostApi {
    private weak var host: MapKitViewHost?

    init(_ host: MapKitViewHost) { self.host = host }

    /// The same answer Dart gets from a channel with no handler.
    private func live() throws -> MapKitViewHost {
        guard let host else {
            throw MapKitHostError(code: "channel-error", message: "The map view is gone.", details: nil)
        }
        return host
    }

    func initialize(params: PlatformMapViewCreationParams) throws { try live().initialize(params: params) }

    func setCamera(camera: PlatformMapCamera, animated: Bool) throws {
        try live().setCamera(camera: camera, animated: animated)
    }

    func setRegion(region: PlatformCoordinateRegion, animated: Bool) throws {
        try live().setRegion(region: region, animated: animated)
    }

    func setCenter(coordinate: PlatformCoordinate, animated: Bool) throws {
        try live().setCenter(coordinate: coordinate, animated: animated)
    }

    func getCamera() throws -> PlatformMapCamera? { try live().getCamera() }

    func getRegion() throws -> PlatformCoordinateRegion? { try live().getRegion() }

    func convertToPoint(coordinate: PlatformCoordinate) throws -> PlatformPoint? {
        try live().convertToPoint(coordinate: coordinate)
    }

    func convertToCoordinate(point: PlatformPoint) throws -> PlatformCoordinate? {
        try live().convertToCoordinate(point: point)
    }

    func updateAnnotations(toAdd: [PlatformAnnotation], toChange: [PlatformAnnotation], idsToRemove: [String]) throws {
        try live().updateAnnotations(toAdd: toAdd, toChange: toChange, idsToRemove: idsToRemove)
    }

    func updatePolylines(toAdd: [PlatformPolyline], toChange: [PlatformPolyline], idsToRemove: [String]) throws {
        try live().updatePolylines(toAdd: toAdd, toChange: toChange, idsToRemove: idsToRemove)
    }

    func updatePolygons(toAdd: [PlatformPolygon], toChange: [PlatformPolygon], idsToRemove: [String]) throws {
        try live().updatePolygons(toAdd: toAdd, toChange: toChange, idsToRemove: idsToRemove)
    }

    func updateCircles(toAdd: [PlatformCircle], toChange: [PlatformCircle], idsToRemove: [String]) throws {
        try live().updateCircles(toAdd: toAdd, toChange: toChange, idsToRemove: idsToRemove)
    }

    func updateMapConfiguration(configuration: PlatformMapConfiguration) throws {
        try live().updateMapConfiguration(configuration: configuration)
    }

    func selectAnnotation(annotationId: String) throws -> Bool { try live().selectAnnotation(annotationId: annotationId) }

    func deselectAnnotation(annotationId: String) throws -> Bool {
        try live().deselectAnnotation(annotationId: annotationId)
    }

    func isAnnotationSelected(annotationId: String) throws -> Bool {
        try live().isAnnotationSelected(annotationId: annotationId)
    }

    func takeSnapshot(
        options: PlatformSnapshotOptions, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
    ) {
        do {
            try live().takeSnapshot(options: options, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func openLookAround(coordinate: PlatformCoordinate, completion: @escaping (Result<Bool, Error>) -> Void) {
        do {
            try live().openLookAround(coordinate: coordinate, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func addTileOverlay(overlay: PlatformTileOverlay) throws { try live().addTileOverlay(overlay: overlay) }

    func removeTileOverlay(tileOverlayId: String) throws -> Bool {
        try live().removeTileOverlay(tileOverlayId: tileOverlayId)
    }

    func dispose() throws { try live().dispose() }
}

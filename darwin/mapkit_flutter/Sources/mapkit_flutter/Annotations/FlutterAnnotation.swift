import Foundation
import MapKit

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

class FlutterAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let id: String
    @objc dynamic var title: String?
    @objc dynamic var subtitle: String?
    var calloutConsumesTapEvents: Bool
    var alpha: Double
    var anchorPoint: CGPoint
    var isDraggable: Bool
    var isHidden: Bool
    var zPriority: Double
    var icon: AnnotationIcon
    var clusteringIdentifier: String?

    init(fromPlatform annotation: PlatformAnnotation) throws {
        self.coordinate = annotation.coordinate.clCoordinate
        self.id = annotation.id
        self.title = annotation.title
        self.subtitle = annotation.subtitle
        self.calloutConsumesTapEvents = annotation.calloutConsumesTapEvents
        self.isHidden = annotation.isHidden
        self.isDraggable = annotation.isDraggable
        self.zPriority = annotation.zPriority
        self.alpha = annotation.alpha
        self.anchorPoint = CGPoint(x: annotation.anchorPointX, y: annotation.anchorPointY)
        self.icon = try AnnotationIcon(fromPlatform: annotation.icon)
        self.clusteringIdentifier = annotation.clusteringIdentifier
        super.init()
    }

    // Change detection for `annotationsToChange` keys off this — every wire
    // field must participate or updates silently stop applying.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FlutterAnnotation else { return false }
        return id == other.id
            && title == other.title
            && subtitle == other.subtitle
            && alpha == other.alpha
            && isDraggable == other.isDraggable
            && isHidden == other.isHidden
            && icon == other.icon
            && coordinate.latitude == other.coordinate.latitude
            && coordinate.longitude == other.coordinate.longitude
            && calloutConsumesTapEvents == other.calloutConsumesTapEvents
            && anchorPoint == other.anchorPoint
            && zPriority == other.zPriority
            && clusteringIdentifier == other.clusteringIdentifier
    }

    override var hash: Int {
        id.hashValue
    }
}

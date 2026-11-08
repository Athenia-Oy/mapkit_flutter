import CoreLocation
import Foundation
import MapKit

final class FlutterCircle: MKCircle, FlutterOverlay, @unchecked Sendable {
    var strokeColor: PlatformColor?
    var fillColor: PlatformColor?
    var isConsumingTapEvents: Bool = false
    var lineWidth: CGFloat = 1
    var isHidden: Bool = false
    var id: String = ""
    var zIndex: Int = 0
    var overlayLevel: MKOverlayLevel = .aboveRoads

    convenience init(fromPlatform data: PlatformCircle) {
        self.init(center: data.center.clCoordinate, radius: data.radius)
        self.strokeColor = PlatformColor(argb: data.strokeColorArgb)
        self.fillColor = PlatformColor(argb: data.fillColorArgb)
        self.isConsumingTapEvents = data.consumeTapEvents
        self.lineWidth = CGFloat(data.lineWidth)
        self.id = data.id
        self.isHidden = data.isHidden
        self.zIndex = Int(data.zIndex)
        self.overlayLevel = data.level.mkLevel
    }

    func makeRenderer() -> MKOverlayRenderer {
        let renderer = MKCircleRenderer(circle: self)
        if isHidden {
            renderer.strokeColor = .clear
            renderer.lineWidth = 0.0
        } else {
            renderer.strokeColor = strokeColor
            renderer.fillColor = fillColor
            renderer.lineWidth = lineWidth
        }
        return renderer
    }

    func getCAShapeLayer(snapshot: MKMapSnapshotter.Snapshot) -> CAShapeLayer {
        let shapeLayer = CAShapeLayer()

        if isHidden {
            return shapeLayer
        }
        let centerPoint = snapshot.point(for: coordinate)
        let offsetPoint = snapshot.point(for: coordinate.offsetLatitude(byMeters: radius))
        let radiusInPoints = hypot(centerPoint.x - offsetPoint.x, centerPoint.y - offsetPoint.y)

        let circlePath = CGMutablePath()
        circlePath.addArc(center: centerPoint, radius: radiusInPoints, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        shapeLayer.path = circlePath
        shapeLayer.lineWidth = lineWidth
        shapeLayer.strokeColor = strokeColor?.cgColor ?? PlatformColor.clear.cgColor
        shapeLayer.fillColor = fillColor?.cgColor ?? PlatformColor.clear.cgColor
        return shapeLayer
    }
}

public extension MKCircle {
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        let center = CLLocation(latitude: self.coordinate.latitude, longitude: self.coordinate.longitude)
        let tap = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return center.distance(from: tap) <= self.radius
    }
}

private extension CLLocationCoordinate2D {
    /// A coordinate shifted north by `meters`, using the standard
    /// ~111,320 m-per-degree-of-latitude approximation. Used to size the
    /// circle in points when rendering map snapshots.
    func offsetLatitude(byMeters meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude + meters / 111_320, longitude: longitude)
    }
}

import Foundation
import MapKit

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

extension MapKitViewHost {

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        #if os(iOS)
        if let feature = view.annotation as? MKMapFeatureAnnotation {
            let payload = PlatformMapFeature.from(feature)
            self.flutterApi.send { try await $0.onMapFeatureSelected(feature: payload) }
            return
        }
        #endif
        guard let annotation = view.annotation as? FlutterAnnotation else { return }
        let id = annotation.id
        self.currentlySelectedAnnotation = id
        #if os(iOS)
        self.syncCalloutTapGestureRecognizer(for: annotation, on: view)
        #endif
        if self.suppressSelectionCallbacksForAnnotationId == id {
            return
        }
        self.flutterApi.send { try await $0.onAnnotationSelect(annotationId: id) }
    }

    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        guard let annotation = view.annotation as? FlutterAnnotation else { return }
        let id = annotation.id
        if self.currentlySelectedAnnotation == id {
            self.currentlySelectedAnnotation = nil
        }
        #if os(iOS)
        for recognizer in view.gestureRecognizers ?? [] where recognizer is InfoWindowTapGestureRecognizer {
            view.removeGestureRecognizer(recognizer)
        }
        #endif
        if self.suppressSelectionCallbacksForAnnotationId == id {
            return
        }
        self.flutterApi.send { try await $0.onAnnotationDeselect(annotationId: id) }
    }

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        } else if let cluster = annotation as? MKClusterAnnotation {
            return self.getClusterAnnotationView(cluster: cluster)
        } else if let flutterAnnotation = annotation as? FlutterAnnotation {
            return self.getAnnotationView(annotation: flutterAnnotation)
        }
        return nil
    }

    // Annotation drag lifecycle.
    public func mapView(_ mapView: MKMapView,
                        annotationView view: MKAnnotationView,
                        didChange newState: MKAnnotationView.DragState,
                        fromOldState oldState: MKAnnotationView.DragState) {
        guard let annotation = view.annotation as? FlutterAnnotation else { return }
        let id = annotation.id
        let coordinate = PlatformCoordinate.from(annotation.coordinate)
        switch newState {
        case .starting:
            self.flutterApi.send { try await $0.onAnnotationDragStart(annotationId: id, coordinate: coordinate) }
        case .ending, .canceling:
            self.flutterApi.send { try await $0.onAnnotationDragEnd(annotationId: id, coordinate: coordinate) }
        default:
            break
        }
    }

    private func getClusterAnnotationView(cluster: MKClusterAnnotation) -> MKAnnotationView {
        let id = "mapkit.cluster"
        let view = self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: cluster) as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: id)
        view.markerTintColor = .systemBlue
        view.glyphText = "\(cluster.memberAnnotations.count)"
        view.canShowCallout = false
        return view
    }

    func getAnnotationView(annotation: FlutterAnnotation) -> MKAnnotationView {
        let view: MKAnnotationView
        if annotation.icon.isCustomImage {
            let customView = self.mapView.dequeueReusableAnnotationView(withIdentifier: "FlutterCustomAnnotationView", for: annotation)
            customView.image = annotation.icon.image
            Self.applyAnchor(annotation, to: customView)
            view = customView
        } else {
            let markerView = self.mapView.dequeueReusableAnnotationView(withIdentifier: "FlutterMarkerAnnotationView", for: annotation) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "FlutterMarkerAnnotationView")
            self.applyMarkerStyle(markerView, annotation.icon)
            view = markerView
        }
        self.initInfoWindow(annotation: annotation, annotationView: view)
        view.annotation = annotation
        view.isHidden = annotation.isHidden
        view.zPriority = MKAnnotationViewZPriority(rawValue: Float(annotation.zPriority))
        view.canShowCallout = true
        view.platformAlpha = CGFloat(annotation.alpha)
        view.isDraggable = annotation.isDraggable
        view.clusteringIdentifier = annotation.clusteringIdentifier

        return view
    }

    func annotationsToAdd(_ toAdd: [FlutterAnnotation]) {
        let stale = toAdd.compactMap { self.annotationsById.removeValue(forKey: $0.id) }
        if !stale.isEmpty {
            self.mapView.removeAnnotations(stale)
        }
        for annotation in toAdd {
            self.annotationsById[annotation.id] = annotation
        }
        self.mapView.addAnnotations(toAdd)
    }

    func annotationsToChange(_ annotations: [FlutterAnnotation]) {
        for newAnnotation in annotations {
            guard let annotationToChange = self.getAnnotation(with: newAnnotation.id) else {
                self.addAnnotation(newAnnotation)
                continue
            }
            if annotationToChange != newAnnotation {
                updateAnnotation(annotation: newAnnotation)
            }
        }
    }

    func annotationsToRemove(_ annotationIds: [String]) {
        let toRemove = annotationIds.compactMap { self.annotationsById.removeValue(forKey: $0) }
        if !toRemove.isEmpty {
            self.mapView.removeAnnotations(toRemove)
        }
    }

    /// Whether the annotation ended up selected: `false` for an id that is
    /// not on the map or a hidden annotation, which MapKit can't select.
    @discardableResult
    func selectAnnotation(with id: String) -> Bool {
        guard let annotation = self.getAnnotation(with: id), !annotation.isHidden else { return false }
        self.mapView.selectAnnotation(annotation, animated: true)
        return self.isAnnotationSelected(with: id)
    }

    /// `false` when the id is not on the map.
    @discardableResult
    func deselectAnnotation(with id: String) -> Bool {
        guard let annotation = self.getAnnotation(with: id) else { return false }
        self.mapView.deselectAnnotation(annotation, animated: true)
        return true
    }

    func isAnnotationSelected(with id: String) -> Bool {
        return self.mapView.selectedAnnotations.contains(where: { annotation in return (annotation as? FlutterAnnotation)?.id == id })
    }

    private func removeAnnotation(id: String) {
        if let flutterAnnotation: FlutterAnnotation = self.getAnnotation(with: id) {
            self.annotationsById.removeValue(forKey: id)
            self.mapView.removeAnnotation(flutterAnnotation)
        }
    }

    func initInfoWindow(annotation: FlutterAnnotation, annotationView: MKAnnotationView) {
        // MapKit centers the callout on the view; `anchorPoint` already moves the view.
        annotationView.calloutOffset = .zero
        #if os(iOS)
        // The multi-line subtitle accessory is built with UIKit; macOS uses
        // MapKit's default callout (title/subtitle).
        if let lines = annotation.subtitle?.split(whereSeparator: { $0.isNewline }) {
            let customCallout = UIStackView()
            customCallout.axis = .vertical
            customCallout.alignment = .fill
            customCallout.distribution = .fill
            for line in lines {
                let subtitle = UILabel()
                subtitle.text = String(line)
                customCallout.addArrangedSubview(subtitle)
            }
            annotationView.detailCalloutAccessoryView = customCallout
        } else if annotation.calloutConsumesTapEvents, annotation.title != nil {
            // A marker draws a lone title as its own label and refuses a callout
            // until it has an accessory; a consumed tap needs a callout to land on.
            annotationView.detailCalloutAccessoryView = UIView()
        } else {
            // Clear a stale accessory when the subtitle is removed on update.
            annotationView.detailCalloutAccessoryView = nil
        }
        #endif
    }

    #if os(iOS)
    /// The recognizer sits on the annotation view, which also hosts the
    /// callout as a subview outside its own bounds: a touch inside the bounds
    /// is the pin, not the callout.
    @objc func onCalloutTapped(infoWindowTap: InfoWindowTapGestureRecognizer) {
        if let view = infoWindowTap.annotationView,
           view.bounds.contains(infoWindowTap.location(in: view)) {
            return
        }
        guard let annotationId = infoWindowTap.annotationId,
              self.currentlySelectedAnnotation == annotationId,
              let annotation = self.getAnnotation(with: annotationId),
              annotation.calloutConsumesTapEvents else {
            infoWindowTap.annotationView?.removeGestureRecognizer(infoWindowTap)
            return
        }
        self.flutterApi.send { try await $0.onCalloutTap(annotationId: annotationId) }
    }

    func syncCalloutTapGestureRecognizer(for annotation: FlutterAnnotation, on view: MKAnnotationView) {
        // Callout tap forwarding is bridged via a tap recognizer on iOS;
        // the macOS callout uses MapKit's default behavior. One recognizer
        // per view: reselecting must not stack another.
        if annotation.calloutConsumesTapEvents, self.currentlySelectedAnnotation == annotation.id {
            if !(view.gestureRecognizers ?? []).contains(where: { $0 is InfoWindowTapGestureRecognizer }) {
                let tapGestureRecognizer = InfoWindowTapGestureRecognizer(target: self, action: #selector(onCalloutTapped))
                tapGestureRecognizer.annotationId = annotation.id
                tapGestureRecognizer.annotationView = view
                view.addGestureRecognizer(tapGestureRecognizer)
            }
        } else {
            for recognizer in view.gestureRecognizers ?? [] where recognizer is InfoWindowTapGestureRecognizer {
                view.removeGestureRecognizer(recognizer)
            }
        }
    }
    #endif

    private func getAnnotation(with id: String) -> FlutterAnnotation? {
        return self.annotationsById[id]
    }

    private func annotationExists(with id: String) -> Bool {
        return self.getAnnotation(with: id) != nil
    }

    /**
     Checks if an Annotation with the same id exists and removes it before adding if necessary
     - Parameter annotation: the FlutterAnnotation that should be added
     */
    private func addAnnotation(_ annotation: FlutterAnnotation) {
        if self.annotationExists(with: annotation.id) {
            self.removeAnnotation(id: annotation.id)
        }
        self.annotationsById[annotation.id] = annotation
        self.mapView.addAnnotation(annotation)
    }

    private func updateAnnotation(annotation: FlutterAnnotation) {
        guard let oldAnnotation = self.getAnnotation(with: annotation.id) else { return }
        // A change of icon variant (system marker <-> custom image) needs a
        // different annotation-view class, which an in-place update can't swap.
        // Replace the annotation so the delegate builds a fresh view of the
        // correct kind instead of forcing an image onto a marker view.
        if oldAnnotation.icon.iconType != annotation.icon.iconType {
            let wasSelected = self.isAnnotationSelected(with: annotation.id) || self.currentlySelectedAnnotation == annotation.id
            let shouldReselect = wasSelected && !annotation.isHidden
            if shouldReselect {
                self.suppressSelectionCallbacksForAnnotationId = annotation.id
            }
            defer {
                self.suppressSelectionCallbacksForAnnotationId = nil
            }
            self.removeAnnotation(id: annotation.id)
            self.addAnnotation(annotation)
            if shouldReselect {
                self.selectAnnotation(with: annotation.id)
            } else if wasSelected && self.currentlySelectedAnnotation == annotation.id {
                self.currentlySelectedAnnotation = nil
                let id = annotation.id
                self.flutterApi.send { try await $0.onAnnotationDeselect(annotationId: id) }
            }
            return
        }
        // `coordinate`, `title` and `subtitle` are KVO-observable, which is how
        // MapKit refreshes a visible pin, label or callout; the rest are plain
        // properties. Only a coordinate change animates, so it alone sits in
        // the animation block.
        #if os(iOS)
        UIView.animate(withDuration: 0.32) {
            oldAnnotation.coordinate = annotation.coordinate
        }
        #elseif os(macOS)
        oldAnnotation.coordinate = annotation.coordinate
        #endif
        oldAnnotation.zPriority = annotation.zPriority
        oldAnnotation.anchorPoint = annotation.anchorPoint
        oldAnnotation.alpha = annotation.alpha
        oldAnnotation.isHidden = annotation.isHidden
        oldAnnotation.isDraggable = annotation.isDraggable
        oldAnnotation.calloutConsumesTapEvents = annotation.calloutConsumesTapEvents
        oldAnnotation.title = annotation.title
        oldAnnotation.subtitle = annotation.subtitle
        oldAnnotation.clusteringIdentifier = annotation.clusteringIdentifier
        oldAnnotation.icon = annotation.icon

        if annotation.isHidden && self.isAnnotationSelected(with: annotation.id) {
            self.deselectAnnotation(with: annotation.id)
        }

        // Re-apply the view-level properties the annotation view captured at
        // creation time.
        if let view = self.mapView.view(for: oldAnnotation) {
            view.platformAlpha = CGFloat(annotation.alpha)
            view.isHidden = annotation.isHidden
            view.isDraggable = annotation.isDraggable
            view.zPriority = MKAnnotationViewZPriority(rawValue: Float(annotation.zPriority))
            view.clusteringIdentifier = annotation.clusteringIdentifier
            if annotation.icon.isCustomImage {
                view.image = annotation.icon.image
                Self.applyAnchor(annotation, to: view)
            }
            if let marker = view as? MKMarkerAnnotationView {
                self.applyMarkerStyle(marker, annotation.icon)
            }
            self.initInfoWindow(annotation: annotation, annotationView: view)
            #if os(iOS)
            self.syncCalloutTapGestureRecognizer(for: oldAnnotation, on: view)
            #endif
        }
    }

    /// Pins the image's normalized `anchorPoint` to the coordinate: natively on
    /// iOS (`MKAnnotationView.anchorPoint`), via `centerOffset` on macOS where
    /// `anchorPoint` doesn't exist (both platforms move the view down for a
    /// positive y offset).
    static func applyAnchor(_ annotation: FlutterAnnotation, to view: MKAnnotationView) {
        #if os(iOS)
        view.anchorPoint = annotation.anchorPoint
        #elseif os(macOS)
        let size = annotation.icon.image?.size ?? .zero
        view.centerOffset = CGPoint(
            x: size.width * (0.5 - annotation.anchorPoint.x),
            y: size.height * (0.5 - annotation.anchorPoint.y))
        #endif
    }

    /// Applies marker styling to `view`, assigning each property directly —
    /// including `nil` — so a value cleared between updates resets to MapKit's
    /// default (`markerTintColor = nil` → system red, `glyphTintColor = nil` →
    /// white). Shared by the create, reuse, and in-place-update paths so they
    /// cannot drift.
    private func applyMarkerStyle(_ view: MKMarkerAnnotationView, _ icon: AnnotationIcon) {
        view.markerTintColor = icon.markerTint
        view.glyphText = icon.glyphText
        view.glyphImage = icon.glyphImage
        view.glyphTintColor = icon.glyphTint
    }

}

#if os(iOS)
class InfoWindowTapGestureRecognizer: UITapGestureRecognizer {
    weak var annotationView: UIView?
    var annotationId: String?
}
#endif

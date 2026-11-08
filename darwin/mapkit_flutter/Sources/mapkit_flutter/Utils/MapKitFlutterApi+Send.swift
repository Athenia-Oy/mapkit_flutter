import os

extension MapKitFlutterApi {
    /// Fire-and-forget host -> Dart event. Main-actor tasks start in creation order.
    @MainActor
    func send(_ event: @escaping @MainActor (MapKitFlutterApi) async throws -> Void) {
        Task { @MainActor in
            do {
                try await event(self)
            } catch {
                EventDeliveryFailure.report(error)
            }
        }
    }
}

/// An event that failed to arrive. Exceptions from Flutter callbacks never get
/// here: Dart reports those itself and replies with success. What is left is
/// the channel: no listener in the moments a view is being wired up or disposed
/// (`channel-error`, expected), or a message Dart could not decode, which a
/// released plugin should never see. Neither is the app's misuse and neither can
/// be reported to Dart over the channel that failed, so both are logged.
@MainActor
enum EventDeliveryFailure {
    private static let log = Logger(subsystem: "dev.mapkit.flutter", category: "events")

    /// Replaced by tests to observe failures.
    static var report: (Error) -> Void = { error in
        if (error as? MapKitHostError)?.code == "channel-error" {
            log.debug("Event not delivered: \(String(describing: error), privacy: .public)")
        } else {
            log.error("Event failed: \(String(describing: error), privacy: .public)")
        }
    }
}

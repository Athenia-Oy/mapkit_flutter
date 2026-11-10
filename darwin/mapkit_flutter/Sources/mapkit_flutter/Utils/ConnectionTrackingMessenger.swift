import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Forwards to `base` and records every handler connection, so a disposed view can drop its handlers
/// via `cleanUpConnection`. Never `setMessageHandler(nil)`: on macOS the engine stores the nil handler
/// and crashes on the next message to that channel. `@unchecked`: only used on the platform thread,
/// the host's `deinit` included.
final class ConnectionTrackingMessenger: NSObject, FlutterBinaryMessenger, @unchecked Sendable {
    private let base: FlutterBinaryMessenger
    private var connections: [FlutterBinaryMessengerConnection] = []
    init(_ base: FlutterBinaryMessenger) { self.base = base }
    func send(onChannel channel: String, message: Data?) { base.send(onChannel: channel, message: message) }
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        base.send(onChannel: channel, message: message, binaryReply: callback)
    }
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        let connection = base.setMessageHandlerOnChannel(channel, binaryMessageHandler: handler)
        connections.append(connection)
        return connection
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { base.cleanUpConnection(connection) }
    func removeAllHandlers() {
        connections.forEach(base.cleanUpConnection)
        connections.removeAll()
    }
}

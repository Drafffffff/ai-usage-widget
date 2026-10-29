import Foundation
import Network

/// Tiny LAN server used by the iOS app and widget. It serves the same snapshot
/// that feeds the desktop widget, so the phone can refresh without the Mac app
/// being opened.
final class LocalServer {
    static let shared = LocalServer()
    static let port: UInt16 = 48765

    static var url: String? {
        let host = ProcessInfo.processInfo.hostName
        guard !host.isEmpty else { return nil }
        return "http://\(host):\(Self.port)/usage.json"
    }

    private let queue = DispatchQueue(label: "Headroom.LocalServer")
    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.service = NWListener.Service(name: "Headroom", type: "_headroom._tcp")
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    NSLog("Headroom local server ready on \(Self.port)")
                case .failed(let error):
                    NSLog("Headroom local server failed: \(error)")
                    Self.shared.listener = nil
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Headroom local server start error: \(error)")
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        NSLog("Headroom local server accepted connection")
        respond(on: connection)
    }

    private func respond(on connection: NWConnection) {
        let base = WidgetData.load()
        let snapshot = CachedSnapshot(
            providers: base?.providers ?? [],
            savedAt: base?.savedAt ?? Date(),
            syncURL: Self.url
        )
        let body = WidgetData.encode(snapshot) ?? Data("{\"providers\":[],\"savedAt\":\"\(ISO8601DateFormatter().string(from: Date()))\"}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        response.append(body)
        NSLog("Headroom local server sending \(body.count) bytes")
        connection.send(content: response, completion: .contentProcessed { error in
            if let error { NSLog("Headroom local server send error: \(error)") }
            connection.cancel()
        })
    }
}

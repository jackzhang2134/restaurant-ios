import Foundation
import Network

protocol TCPServerDelegate: AnyObject {
    func serverDidUpdateClients(count: Int)
    func serverDidReceiveOrder(_ order: Order, items: [OrderItem])
    func serverDidReceivePayment(_ payment: Payment)
    func serverDidReceiveSummary(_ summary: DailySalesSummary)
    func serverDidRegisterDevice(_ deviceMac: String)
}

class TCPServer {
    static let shared = TCPServer()
    weak var delegate: TCPServerDelegate?
    private var listener: NWListener?
    private(set) var connectedClients: Set<String> = []
    private let queue = DispatchQueue(label: "tcp.server", qos: .background)
    private let decoder = JSONDecoder()

    var isRunning: Bool { listener != nil }

    func start() {
        guard !isRunning else { return }
        do {
            let options = NWProtocolTCP.Options()
            options.enableKeepalive = true
            let params = NWParameters(tls: nil, tcp: options)
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 9876)!)
            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener?.start(queue: queue)
            print("=== TCP Server started on port 9876 ===")
        } catch {
            print("=== Server start failed: \(error) ===")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connectedClients.removeAll()
        delegate?.serverDidUpdateClients(count: 0)
    }

    private func handleConnection(_ conn: NWConnection) {
        let clientId = UUID().uuidString
        connectedClients.insert(clientId)
        DispatchQueue.main.async {
            self.delegate?.serverDidUpdateClients(count: self.connectedClients.count)
        }

        conn.start(queue: queue)
        readLoop(conn, clientId: clientId)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed(_):
                self?.connectedClients.remove(clientId)
                DispatchQueue.main.async {
                    self?.delegate?.serverDidUpdateClients(count: self?.connectedClients.count ?? 0)
                }
            default: break
            }
        }
    }

    private func readLoop(_ conn: NWConnection, clientId: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self else { return }
            if let data = data, data.count > 0, let text = String(data: data, encoding: .utf8) {
                self.processMessage(text.trimmingCharacters(in: .whitespacesAndNewlines), conn: conn)
            }
            if error == nil {
                self.readLoop(conn, clientId: clientId)
            }
        }
    }

    private func processMessage(_ json: String, conn: NWConnection) {
        guard let dict = try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any],
              let type = dict["type"] as? String else {
            sendReply(conn, "{\"result\":\"invalid\"}")
            return
        }

        let deviceMac = dict["deviceMac"] as? String ?? ""
        let payloadStr = dict["payload"] as? String ?? ""

        DispatchQueue.main.async {
            let db = DatabaseManager.shared
            var result = "OK"

            switch type {
            case "REGISTER":
                db.saveSubDevice(SubDevice(deviceMac: deviceMac, deviceName: "子机-\(deviceMac.suffix(8))"))
                self.delegate?.serverDidRegisterDevice(deviceMac)

            case "HEARTBEAT":
                db.updateLastSeen(deviceMac)

            case "UPLOAD_ORDER":
                if let payload = self.decodePayload(payloadStr, as: OrderWithItems.self) {
                    db.saveOrder(payload.order)
                    payload.items.forEach { db.saveOrderItem($0) }
                    self.delegate?.serverDidReceiveOrder(payload.order, items: payload.items)
                } else {
                    result = "parse_error"
                }

            case "UPLOAD_PAYMENT":
                if let payment: Payment = self.decodePayload(payloadStr) {
                    db.savePayment(payment)
                    self.delegate?.serverDidReceivePayment(payment)
                }

            case "UPLOAD_DAILY_SUMMARY":
                if let summary: DailySalesSummary = self.decodePayload(payloadStr) {
                    db.saveSummary(summary)
                    self.delegate?.serverDidReceiveSummary(summary)
                }

            default:
                result = "unknown"
            }

            self.sendReply(conn, "{\"result\":\"\(result)\"}")
        }
    }

    private func sendReply(_ conn: NWConnection, _ json: String) {
        let msg = json + "\n"
        conn.send(content: msg.data(using: .utf8), completion: .idempotent)
    }

    private func decodePayload<T: Decodable>(_ json: String, as type: T.Type = T.self) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func getLocalIP() -> String {
        var addr = "0.0.0.0"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return addr }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee, interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  let name = String(cString: interface.ifa_name, encoding: .utf8),
                  name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            addr = String(cString: hostname)
        }
        freeifaddrs(ifaddr)
        return addr
    }
}

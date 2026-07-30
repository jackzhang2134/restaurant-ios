import Foundation
import Network

protocol TCPServerDelegate: AnyObject {
    func serverDidUpdateClients(count: Int)
    func serverDidReceiveOrder(_ order: Order, items: [OrderItem])
    func serverDidReceivePayment(_ payment: Payment)
    func serverDidReceiveSummary(_ summary: DailySalesSummary)
    func serverDidRegisterDevice(_ deviceMac: String)
}

struct OrderWithItems: Codable {
    var order: Order
    var items: [OrderItem]
}

class TCPServer {
    static let shared = TCPServer()
    weak var delegate: TCPServerDelegate?
    private var listener: NWListener?
    private(set) var connectedClients: Set<String> = []
    private let queue = DispatchQueue(label: "tcp.server", qos: .background)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isRunning: Bool { listener != nil }

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: 9876)
            listener?.newConnectionHandler = { [weak self] conn in self?.handleConnection(conn) }
            listener?.start(queue: queue)
        } catch {
            print("Failed to start server: \(error)")
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
        DispatchQueue.main.async { self.delegate?.serverDidUpdateClients(count: self.connectedClients.count) }

        conn.start(queue: queue)
        receiveData(conn, clientId: clientId)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed(_):
                self?.connectedClients.remove(clientId)
                DispatchQueue.main.async { self?.delegate?.serverDidUpdateClients(count: self?.connectedClients.count ?? 0) }
            default: break
            }
        }
    }

    private func receiveData(_ conn: NWConnection, clientId: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil else { return }
            self.processMessage(String(data: data, encoding: .utf8) ?? "{}", conn: conn)
            self.receiveData(conn, clientId: clientId)
        }
    }

    private func processMessage(_ json: String, conn: NWConnection) {
        guard let dict = try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any],
              let type = dict["type"] as? String else { return }

        let deviceMac = dict["deviceMac"] as? String ?? ""
        let payloadStr = dict["payload"] as? String ?? ""

        DispatchQueue.main.async {
            let db = DatabaseManager.shared
            switch type {
            case "REGISTER":
                db.saveSubDevice(SubDevice(deviceMac: deviceMac, deviceName: "子机-\(deviceMac.suffix(8))"))
                self.delegate?.serverDidRegisterDevice(deviceMac)
                self.sendAck(conn, message: "OK")

            case "HEARTBEAT":
                db.updateLastSeen(deviceMac)
                self.sendAck(conn, message: "OK")

            case "UPLOAD_ORDER":
                if let payload = self.decodePayload(payloadStr, as: OrderWithItems.self) {
                    db.saveOrder(payload.order)
                    payload.items.forEach { db.saveOrderItem($0) }
                    self.delegate?.serverDidReceiveOrder(payload.order, items: payload.items)
                    self.sendAck(conn, message: "order received")
                }

            case "UPLOAD_PAYMENT":
                if let payment: Payment = self.decodePayload(payloadStr) {
                    db.savePayment(payment)
                    self.delegate?.serverDidReceivePayment(payment)
                    self.sendAck(conn, message: "payment received")
                }

            case "UPLOAD_DAILY_SUMMARY":
                if let summary: DailySalesSummary = self.decodePayload(payloadStr) {
                    db.saveSummary(summary)
                    self.delegate?.serverDidReceiveSummary(summary)
                    self.sendAck(conn, message: "summary received")
                }

            default:
                self.sendAck(conn, message: "unknown type")
            }
        }
    }

    private func sendAck(_ conn: NWConnection, message: String) {
        let msg = "{\"type\":\"ACK\",\"message\":\"\(message)\"}"
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

import Foundation

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
    private var serverSocket: Int32 = -1
    private(set) var connectedClients: Set<String> = []
    private let queue = DispatchQueue(label: "http.server", qos: .background)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isServerRunning = false

    var isRunning: Bool { isServerRunning }

    func start() {
        guard !isRunning else { return }
        isServerRunning = true

        queue.async { [weak self] in
            self?.runServer()
        }
    }

    func stop() {
        isServerRunning = false
        close(serverSocket)
        serverSocket = -1
        connectedClients.removeAll()
        DispatchQueue.main.async { self.delegate?.serverDidUpdateClients(count: 0) }
    }

    private func runServer() {
        // Create socket
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("Socket creation failed")
            isServerRunning = false; return
        }

        // Allow reuse
        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to port 9876
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(9876).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("Bind failed: \(String(cString: strerror(errno)))")
            isServerRunning = false; return
        }

        // Listen
        guard listen(serverSocket, 10) == 0 else {
            print("Listen failed")
            isServerRunning = false; return
        }

        print("=== HTTP Server listening on port 9876 ===")

        while isServerRunning {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &len)
                }
            }

            guard clientFd >= 0 else {
                if errno != EINTR { print("Accept failed") }
                continue
            }

            let clientId = UUID().uuidString
            DispatchQueue.main.async {
                self.connectedClients.insert(clientId)
                self.delegate?.serverDidUpdateClients(count: self.connectedClients.count)
            }

            queue.async { [weak self] in
                self?.handleHTTPClient(clientFd, clientId: clientId)
            }
        }
    }

    private func handleHTTPClient(_ fd: Int32, clientId: String) {
        defer {
            close(fd)
            DispatchQueue.main.async {
                self.connectedClients.remove(clientId)
                self.delegate?.serverDidUpdateClients(count: self.connectedClients.count)
            }
        }

        var buf = [UInt8](repeating: 0, count: 65536)
        let size = read(fd, &buf, buf.count)
        guard size > 0 else { return }

        let request = String(bytes: buf[0..<Int(size)], encoding: .utf8) ?? ""

        // Parse HTTP: extract body after \r\n\r\n
        guard let bodyStart = request.range(of: "\r\n\r\n") else {
            sendHTTPResponse(fd, status: 400, body: "Bad Request")
            return
        }

        let body = String(request[bodyStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let jsonData = body.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = dict["type"] as? String else {
            sendHTTPResponse(fd, status: 400, body: "Invalid JSON")
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
                if let payload: OrderWithItems = self.decodePayload(payloadStr) {
                    db.saveOrder(payload.order)
                    payload.items.forEach { db.saveOrderItem($0) }
                    self.delegate?.serverDidReceiveOrder(payload.order, items: payload.items)
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

            default: result = "unknown"
            }

            self.sendHTTPResponse(fd, status: 200, body: result)
        }
    }

    private func sendHTTPResponse(_ fd: Int32, status: Int, body: String) {
        let response = """
        HTTP/1.1 \(status) OK\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
        _ = response.withCString { write(fd, $0, strlen($0)) }
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

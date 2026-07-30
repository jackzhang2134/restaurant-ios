import UIKit

class DashboardViewController: UITableViewController, TCPServerDelegate {
    private let db = DatabaseManager.shared
    private let server = TCPServer.shared
    private var clients = 0
    private var summaries: [DailySalesSummary] = []
    private var openOrders: [Order] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "仪表盘"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        server.delegate = self
        refreshData()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshData() }
    }

    private func refreshData() {
        summaries = db.getSummaryByDate(todayStr())
        openOrders = db.getOpenOrders()
        clients = server.connectedClients.count
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["服务器状态", "今日概览", "各设备销售"][section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 1
        case 2: return max(summaries.count, 1)
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.selectionStyle = .none

        switch indexPath.section {
        case 0:
            cell.textLabel?.numberOfLines = 0
            let ip = server.getLocalIP()
            cell.textLabel?.text = "状态: \(server.isRunning ? "运行中" : "已停止")\n已连接: \(clients) 台子机\nIP: \(ip)"
            cell.backgroundColor = server.isRunning ? UIColor(red: 0.9, green: 0.95, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.9, blue: 0.9, alpha: 1)
        case 1:
            let total = summaries.reduce(0) { $0 + $1.totalAmount }
            cell.textLabel?.text = "营业收入: \(formatMoney(total))  |  订单: \(openOrders.count)  |  设备: \(summaries.count)"
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        case 2:
            if summaries.isEmpty {
                cell.textLabel?.text = "暂无销售记录"
                cell.textLabel?.textColor = .gray
            } else {
                let s = summaries[indexPath.row]
                cell.textLabel?.numberOfLines = 0
                cell.textLabel?.text = "设备: \(s.deviceMac.suffix(8))\n订单: \(s.totalOrders)单  成人: \(s.totalAdults)人  儿童: \(s.totalChildren)人\n现金: \(formatMoney(s.cashAmount))  刷卡: \(formatMoney(s.cardAmount))  合计: \(formatMoney(s.totalAmount))"
            }
        default: break
        }
        return cell
    }

    func serverDidUpdateClients(count: Int) { DispatchQueue.main.async { self.refreshData() } }
    func serverDidReceiveOrder(_ order: Order, items: [OrderItem]) { DispatchQueue.main.async { self.refreshData() } }
    func serverDidReceivePayment(_ payment: Payment) { DispatchQueue.main.async { self.refreshData() } }
    func serverDidReceiveSummary(_ summary: DailySalesSummary) { DispatchQueue.main.async { self.refreshData() } }
    func serverDidRegisterDevice(_ deviceMac: String) { DispatchQueue.main.async { self.refreshData() } }
}

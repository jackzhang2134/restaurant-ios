import UIKit

class ZoneTableViewController: UITableViewController {
    private let db = DatabaseManager.shared
    private var zones: [Zone] = []
    private var tables: [String: [RestaurantTable]] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "区域桌位"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addZone))
        loadData()
    }

    private func loadData() {
        zones = db.getAllZones()
        var t: [String: [RestaurantTable]] = [:]
        for z in zones { t[z.zoneId] = db.getTablesByZone(z.zoneId) }
        tables = t
        tableView.reloadData()
    }

    override func numberOfSections(in: UITableView) -> Int { zones.count }
    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? { "\(zones[section].name) (\(zones[section].zoneType.rawValue))" }
    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int { tables[zones[section].zoneId]?.count ?? 0 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .value1, reuseIdentifier: "cell")
        if let t = tables[zones[indexPath.section].zoneId]?[indexPath.row] {
            cell.textLabel?.text = "桌号: \(t.tableNumber)"
            cell.detailTextLabel?.text = "\(t.defaultCapacity)人"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, let t = tables[zones[indexPath.section].zoneId]?[indexPath.row] {
            db.deleteTable(t.tableId)
            loadData()
        }
    }

    @objc private func addZone() {
        let alert = UIAlertController(title: "添加区域", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "区域名称" }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text, !name.isEmpty else { return }
            let zone = Zone(name: name, sortOrder: self?.zones.count ?? 0)
            self?.db.saveZone(zone)
            self?.loadData()
            self?.addTable(to: zone.zoneId)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func addTable(to zoneId: String) {
        let alert = UIAlertController(title: "添加桌位", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "桌位号" }
        alert.addTextField { $0.placeholder = "容量"; $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let num = alert.textFields?[0].text, let cap = alert.textFields?[1].text, !num.isEmpty else { return }
            self?.db.saveTable(RestaurantTable(zoneId: zoneId, tableNumber: num, defaultCapacity: Int(cap) ?? 4))
            self?.loadData()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

import UIKit

class PriceConfigViewController: UITableViewController {
    private let db = DatabaseManager.shared
    private var config: PriceConfig { db.getPriceConfig() ?? PriceConfig() }
    private let fields: [(String, WritableKeyPath<PriceConfig, Double>)] = [
        ("午餐成人", \.lunchAdultPrice), ("午餐儿童", \.lunchChildPrice),
        ("晚餐成人", \.dinnerAdultPrice), ("晚餐儿童", \.dinnerChildPrice),
        ("节日成人", \.holidayAdultPrice), ("节日儿童", \.holidayChildPrice)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "价格配置"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(save))
    }

    override func numberOfSections(in: UITableView) -> Int { 4 }
    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["午餐", "晚餐", "节日", "模式"][section]
    }
    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int { section < 3 ? 2 : 1 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        if indexPath.section < 3 {
            let idx = indexPath.section * 2 + indexPath.row
            let (label, kp) = fields[idx]
            cell.textLabel?.text = "\(label): \(formatMoney(config[keyPath: kp]))"
        } else {
            cell.textLabel?.text = "节日模式: \(config.isHolidayMode ? "开启" : "关闭")"
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section < 3 {
            let idx = indexPath.section * 2 + indexPath.row
            let (label, _) = fields[idx]
            promptNumber(label) { val in
                var c = self.config
                c[keyPath: self.fields[idx].1] = val
                self.db.savePriceConfig(c)
                self.tableView.reloadData()
            }
        } else {
            var c = config
            c.isHolidayMode.toggle()
            db.savePriceConfig(c)
            tableView.reloadData()
        }
    }

    private func promptNumber(_ title: String, completion: @escaping (Double) -> Void) {
        let alert = UIAlertController(title: title, message: "输入新价格", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .decimalPad; $0.text = "0" }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            if let text = alert.textFields?[0].text, let val = Double(text) { completion(val) }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func save() {}
}

class BeverageViewController: UITableViewController {
    private let db = DatabaseManager.shared
    private var beverages: [Beverage] { db.getActiveBeverages() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "酒水管理"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addBeverage))
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func tableView(_: UITableView, numberOfRowsInSection: Int) -> Int { beverages.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .value1, reuseIdentifier: "cell")
        let b = beverages[indexPath.row]
        cell.textLabel?.text = b.name
        cell.detailTextLabel?.text = "\(b.category)  \(formatMoney(b.price))"
        return cell
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete { db.deleteBeverage(beverages[indexPath.row].beverageId); tableView.reloadData() }
    }
    @objc private func addBeverage() {
        let alert = UIAlertController(title: "添加酒水", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "名称" }
        alert.addTextField { $0.placeholder = "价格"; $0.keyboardType = .decimalPad }
        alert.addTextField { $0.placeholder = "分类"; $0.text = "软饮" }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text, !name.isEmpty,
                  let price = Double(alert.textFields?[1].text ?? "0") else { return }
            let cat = alert.textFields?[2].text ?? ""
            self?.db.saveBeverage(Beverage(name: name, price: price, category: cat))
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

class ExpiryAuthViewController: UIViewController {
    private let db = DatabaseManager.shared
    private let security = SecurityManager.shared
    private let statusLabel = UILabel()
    private let datePicker = UIDatePicker()
    private let passwordField = UITextField()
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "有效期授权"
        view.backgroundColor = .white

        statusLabel.frame = CGRect(x: 20, y: 100, width: view.bounds.width - 40, height: 60)
        statusLabel.numberOfLines = 0
        view.addSubview(statusLabel)

        datePicker.frame = CGRect(x: 20, y: 180, width: view.bounds.width - 40, height: 44)
        datePicker.datePickerMode = .date
        view.addSubview(datePicker)

        passwordField.frame = CGRect(x: 20, y: 240, width: view.bounds.width - 40, height: 44)
        passwordField.borderStyle = .roundedRect
        passwordField.placeholder = "卖家授权密码"
        passwordField.isSecureTextEntry = true
        view.addSubview(passwordField)

        saveButton.frame = CGRect(x: 20, y: 300, width: view.bounds.width - 40, height: 44)
        saveButton.setTitle("保存设置", for: .normal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        view.addSubview(saveButton)

        refreshStatus()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refreshStatus() }
    private func refreshStatus() {
        if let lic = db.getLicense() {
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let exp = df.string(from: Date(timeIntervalSince1970: lic.validUntil))
            let expired = Date().timeIntervalSince1970 > lic.validUntil
            statusLabel.text = "有效期至: \(exp)\n\(expired ? "已过期" : "正常使用中")"
            statusLabel.textColor = expired ? .red : .black
        } else { statusLabel.text = "未设置有效期" }
    }
    @objc private func saveTapped() {
        guard security.verifySeller(passwordField.text ?? "") else {
            let alert = UIAlertController(title: "错误", message: "卖家密码错误", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: datePicker.date)!
        db.saveLicense(AppLicense(validUntil: endOfDay.timeIntervalSince1970, lastVerifiedAt: Date().timeIntervalSince1970))
        passwordField.text = ""
        refreshStatus()
    }
}

class SalesRecordViewController: UITableViewController {
    private let db = DatabaseManager.shared
    private var selectedDate = todayStr()
    private var orders: [Order] = []
    private var payments: [Payment] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "销售记录"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "日期", style: .plain, target: self, action: #selector(changeDate))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        loadData()
    }

    private func loadData() {
        orders = db.getOrdersByDate(selectedDate)
        payments = db.getPaymentsByDate(selectedDate)
        tableView.reloadData()
    }

    override func numberOfSections(in: UITableView) -> Int { 2 }
    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "订单 (\(orders.count))" : "支付记录 (\(payments.count))"
    }
    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? orders.count : payments.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        if indexPath.section == 0 {
            let o = orders[indexPath.row]
            cell.textLabel?.text = "桌\(o.tableNumber) \(o.mealPeriod.rawValue)  \(formatMoney(o.totalAmount))  \(o.status.rawValue)"
        } else {
            let p = payments[indexPath.row]
            cell.textLabel?.text = "\(p.method.rawValue) \(formatMoney(p.amount))"
        }
        return cell
    }
    @objc private func changeDate() {
        let alert = UIAlertController(title: "选择日期", message: "\n\n\n\n\n\n", preferredStyle: .alert)
        let picker = UIDatePicker(frame: CGRect(x: 0, y: 50, width: 270, height: 162))
        picker.datePickerMode = .date
        alert.view.addSubview(picker)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            self?.selectedDate = df.string(from: picker.date)
            self?.loadData()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

class DeviceManageViewController: UITableViewController {
    private let db = DatabaseManager.shared
    private var devices: [SubDevice] { db.getAllSubDevices() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设备管理"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tableView.reloadData() }
    override func tableView(_: UITableView, numberOfRowsInSection: Int) -> Int { devices.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let d = devices[indexPath.row]
        cell.textLabel?.text = "设备: \(d.deviceMac.suffix(8))"
        cell.detailTextLabel?.text = d.deviceName
        return cell
    }
}

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?

    private init() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("restaurant.sqlite")
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Failed to open database")
        }
        createTables()
        seedDefaults()
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS zones (zoneId TEXT PRIMARY KEY, name TEXT, type TEXT, sortOrder INTEGER, json TEXT);
        CREATE TABLE IF NOT EXISTS tables_data (tableId TEXT PRIMARY KEY, zoneId TEXT, tableNumber TEXT, defaultCapacity INTEGER, isActive INTEGER, sortOrder INTEGER, json TEXT);
        CREATE TABLE IF NOT EXISTS price_config (configId TEXT PRIMARY KEY, lunchAdult REAL, lunchChild REAL, dinnerAdult REAL, dinnerChild REAL, holidayAdult REAL, holidayChild REAL, isHoliday INTEGER, updatedAt REAL, json TEXT);
        CREATE TABLE IF NOT EXISTS beverages (beverageId TEXT PRIMARY KEY, name TEXT, price REAL, category TEXT, isActive INTEGER, sortOrder INTEGER, json TEXT);
        CREATE TABLE IF NOT EXISTS orders (orderId TEXT PRIMARY KEY, tableId TEXT, tableNumber TEXT, zoneId TEXT, deviceMac TEXT, mealPeriod TEXT, adultCount INTEGER, childCount INTEGER, totalAmount REAL, paidAmount REAL, status TEXT, dateStr TEXT, createdAt REAL, updatedAt REAL, json TEXT);
        CREATE TABLE IF NOT EXISTS order_items (itemId TEXT PRIMARY KEY, orderId TEXT, itemType TEXT, description TEXT, unitPrice REAL, quantity INTEGER, amount REAL, isPaid INTEGER, paidAt REAL, paymentMethod TEXT, json TEXT);
        CREATE TABLE IF NOT EXISTS payments (paymentId TEXT PRIMARY KEY, orderId TEXT, orderItemId TEXT, amount REAL, method TEXT, deviceMac TEXT, dateStr TEXT, paidAt REAL, json TEXT);
        CREATE TABLE IF NOT EXISTS daily_summary (summaryId TEXT PRIMARY KEY, deviceMac TEXT, dateStr TEXT, totalOrders INTEGER, totalAdults INTEGER, totalChildren INTEGER, cashAmount REAL, cardAmount REAL, totalAmount REAL, updatedAt REAL, json TEXT);
        CREATE TABLE IF NOT EXISTS app_license (licenseId TEXT PRIMARY KEY, validUntil REAL, lastVerifiedAt REAL, json TEXT);
        CREATE TABLE IF NOT EXISTS sub_devices (deviceMac TEXT PRIMARY KEY, deviceName TEXT, registeredAt REAL, lastSeenAt REAL, json TEXT);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func seedDefaults() {
        if getAllZones().isEmpty {
            saveZone(Zone(name: "大厅", zoneType: .mainHall, sortOrder: 0))
            saveZone(Zone(name: "包间", zoneType: .privateRoom, sortOrder: 1))
            saveZone(Zone(name: "露台", zoneType: .terrace, sortOrder: 2))
            let zones = getAllZones()
            if let zone1 = zones.first { for i in 1...8 { saveTable(RestaurantTable(zoneId: zone1.zoneId, tableNumber: "A\(i)", sortOrder: i)) } }
            if zones.count > 1 { for i in 1...4 { saveTable(RestaurantTable(zoneId: zones[1].zoneId, tableNumber: "B\(i)", defaultCapacity: 8, sortOrder: i)) } }
            if zones.count > 2 { for i in 1...3 { saveTable(RestaurantTable(zoneId: zones[2].zoneId, tableNumber: "C\(i)", defaultCapacity: 2, sortOrder: i)) } }
            savePriceConfig(PriceConfig())
            saveBeverage(Beverage(name: "矿泉水", price: 3, category: "软饮"))
            saveBeverage(Beverage(name: "可乐", price: 4, category: "软饮"))
            saveBeverage(Beverage(name: "啤酒", price: 8, category: "酒类"))
            saveBeverage(Beverage(name: "红酒", price: 28, category: "酒类"))
        }
    }

    func exec(_ query: String, _ params: [Any] = []) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            for (i, p) in params.enumerated() {
                if let s = p as? String { sqlite3_bind_text(stmt, Int32(i+1), s, -1, nil) }
                else if let d = p as? Double { sqlite3_bind_double(stmt, Int32(i+1), d) }
                else if let n = p as? Int { sqlite3_bind_int(stmt, Int32(i+1), Int32(n)) }
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func query(_ sql: String, _ params: [Any] = []) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (i, p) in params.enumerated() {
                if let s = p as? String { sqlite3_bind_text(stmt, Int32(i+1), s, -1, nil) }
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for i in 0..<sqlite3_column_count(stmt) {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    let type = sqlite3_column_type(stmt, i)
                    switch type {
                    case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                    case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                    case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int(stmt, i))
                    default: row[name] = NSNull()
                    }
                }
                result.append(row)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func saveZone(_ z: Zone) { exec("INSERT OR REPLACE INTO zones VALUES(?,?,?,?,?)", [z.zoneId, z.name, z.zoneType.rawValue, z.sortOrder, encode(z)]) }
    func getAllZones() -> [Zone] { query("SELECT * FROM zones ORDER BY sortOrder").compactMap { decode(from: $0) } }
    func deleteZone(_ zoneId: String) { exec("DELETE FROM zones WHERE zoneId=?", [zoneId]); exec("DELETE FROM tables_data WHERE zoneId=?", [zoneId]) }

    func saveTable(_ t: RestaurantTable) { exec("INSERT OR REPLACE INTO tables_data VALUES(?,?,?,?,?,?,?)", [t.tableId, t.zoneId, t.tableNumber, t.defaultCapacity, t.isActive, t.sortOrder, encode(t)]) }
    func getTablesByZone(_ zoneId: String) -> [RestaurantTable] { query("SELECT * FROM tables_data WHERE zoneId=? ORDER BY sortOrder", [zoneId]).compactMap { decode(from: $0) } }
    func getAllTables() -> [RestaurantTable] { query("SELECT * FROM tables_data ORDER BY sortOrder").compactMap { decode(from: $0) } }
    func deleteTable(_ tableId: String) { exec("DELETE FROM tables_data WHERE tableId=?", [tableId]) }

    func savePriceConfig(_ p: PriceConfig) { exec("INSERT OR REPLACE INTO price_config VALUES(?,?,?,?,?,?,?,?,?,?)", [p.configId, p.lunchAdultPrice, p.lunchChildPrice, p.dinnerAdultPrice, p.dinnerChildPrice, p.holidayAdultPrice, p.holidayChildPrice, p.isHolidayMode, p.updatedAt, encode(p)]) }
    func getPriceConfig() -> PriceConfig? { decode(from: query("SELECT * FROM price_config WHERE configId='default'").first) }

    func saveBeverage(_ b: Beverage) { exec("INSERT OR REPLACE INTO beverages VALUES(?,?,?,?,?,?,?)", [b.beverageId, b.name, b.price, b.category, b.isActive, b.sortOrder, encode(b)]) }
    func getActiveBeverages() -> [Beverage] { query("SELECT * FROM beverages WHERE isActive=1 ORDER BY sortOrder").compactMap { decode(from: $0) } }
    func deleteBeverage(_ id: String) { exec("DELETE FROM beverages WHERE beverageId=?", [id]) }

    func saveOrder(_ o: Order) { exec("INSERT OR REPLACE INTO orders VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [o.orderId, o.tableId, o.tableNumber, o.zoneId, o.deviceMac, o.mealPeriod.rawValue, o.adultCount, o.childCount, o.totalAmount, o.paidAmount, o.status.rawValue, o.dateStr, o.createdAt, o.updatedAt, encode(o)]) }
    func getOrdersByDate(_ dateStr: String) -> [Order] { query("SELECT * FROM orders WHERE dateStr=? ORDER BY createdAt DESC", [dateStr]).compactMap { decode(from: $0) } }
    func getOpenOrders() -> [Order] { query("SELECT * FROM orders WHERE status != '已结清' AND status != '已取消' ORDER BY updatedAt DESC").compactMap { decode(from: $0) } }

    func saveOrderItem(_ item: OrderItem) { exec("INSERT OR REPLACE INTO order_items VALUES(?,?,?,?,?,?,?,?,?,?,?)", [item.itemId, item.orderId, item.itemType, item.description, item.unitPrice, item.quantity, item.amount, item.isPaid, item.paidAt, item.paymentMethod?.rawValue as Any, encode(item)]) }
    func getOrderItems(_ orderId: String) -> [OrderItem] { query("SELECT * FROM order_items WHERE orderId=?", [orderId]).compactMap { decode(from: $0) } }

    func savePayment(_ p: Payment) { exec("INSERT OR REPLACE INTO payments VALUES(?,?,?,?,?,?,?,?,?)", [p.paymentId, p.orderId, p.orderItemId, p.amount, p.method.rawValue, p.deviceMac, p.dateStr, p.paidAt, encode(p)]) }
    func getPaymentsByDate(_ dateStr: String) -> [Payment] { query("SELECT * FROM payments WHERE dateStr=? ORDER BY paidAt DESC", [dateStr]).compactMap { decode(from: $0) } }

    func saveSummary(_ s: DailySalesSummary) { exec("INSERT OR REPLACE INTO daily_summary VALUES(?,?,?,?,?,?,?,?,?,?,?)", [s.summaryId, s.deviceMac, s.dateStr, s.totalOrders, s.totalAdults, s.totalChildren, s.cashAmount, s.cardAmount, s.totalAmount, s.updatedAt, encode(s)]) }
    func getSummaryByDate(_ dateStr: String) -> [DailySalesSummary] { query("SELECT * FROM daily_summary WHERE dateStr=?", [dateStr]).compactMap { decode(from: $0) } }
    func getAllSummaries() -> [DailySalesSummary] { query("SELECT * FROM daily_summary ORDER BY dateStr DESC").compactMap { decode(from: $0) } }

    func saveLicense(_ l: AppLicense) { exec("INSERT OR REPLACE INTO app_license VALUES(?,?,?,?)", [l.licenseId, l.validUntil, l.lastVerifiedAt, encode(l)]) }
    func getLicense() -> AppLicense? { decode(from: query("SELECT * FROM app_license WHERE licenseId='default'").first) }

    func saveSubDevice(_ d: SubDevice) { exec("INSERT OR REPLACE INTO sub_devices VALUES(?,?,?,?,?)", [d.deviceMac, d.deviceName, d.registeredAt, d.lastSeenAt, encode(d)]) }
    func getAllSubDevices() -> [SubDevice] { query("SELECT * FROM sub_devices ORDER BY registeredAt").compactMap { decode(from: $0) } }
    func updateLastSeen(_ mac: String) { exec("UPDATE sub_devices SET lastSeenAt=? WHERE deviceMac=?", [Date().timeIntervalSince1970, mac]) }

    func clearAllData() {
        for table in ["orders", "order_items", "payments", "daily_summary"] { exec("DELETE FROM \(table)") }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func encode<T: Encodable>(_ value: T) -> String {
        (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }

    private func decode<T: Decodable>(from row: [String: Any]?) -> T? {
        guard let json = row?["json"] as? String, let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

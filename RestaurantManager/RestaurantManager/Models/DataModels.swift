import Foundation

enum MealPeriod: String, CaseIterable, Codable {
    case lunch = "午餐"
    case dinner = "晚餐"
}

enum PaymentMethod: String, CaseIterable, Codable {
    case cash = "现金"
    case card = "刷卡"
}

enum OrderStatus: String, Codable {
    case open = "进行中"
    case partial = "部分结账"
    case closed = "已结清"
    case cancelled = "已取消"
}

enum ZoneType: String, CaseIterable, Codable {
    case mainHall = "大厅"
    case privateRoom = "包间"
    case terrace = "露台"
    case bar = "吧台"
    case custom = "自定义"
}

struct Zone: Codable {
    var zoneId = UUID().uuidString
    var name: String
    var zoneType: ZoneType = .mainHall
    var sortOrder: Int = 0
}

struct RestaurantTable: Codable {
    var tableId = UUID().uuidString
    var zoneId: String
    var tableNumber: String
    var defaultCapacity: Int = 4
    var isActive: Bool = true
    var sortOrder: Int = 0
}

struct PriceConfig: Codable {
    var configId = "default"
    var lunchAdultPrice: Double = 18
    var lunchChildPrice: Double = 10
    var dinnerAdultPrice: Double = 25
    var dinnerChildPrice: Double = 15
    var holidayAdultPrice: Double = 35
    var holidayChildPrice: Double = 20
    var isHolidayMode: Bool = false
    var updatedAt: TimeInterval = Date().timeIntervalSince1970
}

struct Beverage: Codable {
    var beverageId = UUID().uuidString
    var name: String
    var price: Double
    var category: String = ""
    var isActive: Bool = true
    var sortOrder: Int = 0
}

struct Order: Codable {
    var orderId = UUID().uuidString
    var tableId: String
    var tableNumber: String
    var zoneId: String
    var deviceMac: String
    var mealPeriod: MealPeriod = .lunch
    var adultCount: Int = 0
    var childCount: Int = 0
    var totalAmount: Double = 0
    var paidAmount: Double = 0
    var status: OrderStatus = .open
    var dateStr: String
    var createdAt: TimeInterval = Date().timeIntervalSince1970
    var updatedAt: TimeInterval = Date().timeIntervalSince1970
}

struct OrderItem: Codable {
    var itemId = UUID().uuidString
    var orderId: String
    var itemType: String = "buffet"
    var description: String
    var unitPrice: Double
    var quantity: Int
    var amount: Double
    var isPaid: Bool = false
    var paidAt: TimeInterval = 0
    var paymentMethod: PaymentMethod?
}

struct Payment: Codable {
    var paymentId = UUID().uuidString
    var orderId: String
    var orderItemId: String
    var amount: Double
    var method: PaymentMethod = .cash
    var deviceMac: String
    var dateStr: String
    var paidAt: TimeInterval = Date().timeIntervalSince1970
}

struct DailySalesSummary: Codable {
    var summaryId: String
    var deviceMac: String
    var dateStr: String
    var totalOrders: Int = 0
    var totalAdults: Int = 0
    var totalChildren: Int = 0
    var cashAmount: Double = 0
    var cardAmount: Double = 0
    var totalAmount: Double = 0
    var updatedAt: TimeInterval = Date().timeIntervalSince1970
}

struct AppLicense: Codable {
    var licenseId = "default"
    var validUntil: TimeInterval = 0
    var lastVerifiedAt: TimeInterval = 0
}

struct SubDevice: Codable {
    var deviceMac: String
    var deviceName: String
    var registeredAt: TimeInterval = Date().timeIntervalSince1970
    var lastSeenAt: TimeInterval = Date().timeIntervalSince1970
}

struct OrderWithItems: Codable {
    var order: Order
    var items: [OrderItem]
}

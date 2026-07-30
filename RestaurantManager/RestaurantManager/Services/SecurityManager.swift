import Foundation

class SecurityManager {
    static let shared = SecurityManager()
    private let defaults = UserDefaults.standard
    private let managerPasswordKey = "manager_password"
    private let sellerPasswordKey = "seller_password"

    var managerPassword: String {
        defaults.string(forKey: managerPasswordKey) ?? "888888"
    }

    var sellerPassword: String {
        defaults.string(forKey: sellerPasswordKey) ?? "SELLER2024"
    }

    func verifyManager(_ input: String) -> Bool { input == managerPassword }
    func verifySeller(_ input: String) -> Bool { input == sellerPassword }
    func setManagerPassword(_ new: String) { defaults.set(new, forKey: managerPasswordKey) }
    func setSellerPassword(_ new: String) { defaults.set(new, forKey: sellerPasswordKey) }
}

func todayStr() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

func formatMoney(_ amount: Double) -> String {
    String(format: "%.2f", amount)
}

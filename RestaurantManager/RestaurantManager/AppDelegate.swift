import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = MainTabBarController()
        window?.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
}

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let dashboard = UINavigationController(rootViewController: DashboardViewController())
        dashboard.tabBarItem = UITabBarItem(title: "仪表盘", image: nil, tag: 0)

        let zoneTable = UINavigationController(rootViewController: ZoneTableViewController())
        zoneTable.tabBarItem = UITabBarItem(title: "区域桌位", image: nil, tag: 1)

        let price = UINavigationController(rootViewController: PriceConfigViewController())
        price.tabBarItem = UITabBarItem(title: "价格", image: nil, tag: 2)

        let beverage = UINavigationController(rootViewController: BeverageViewController())
        beverage.tabBarItem = UITabBarItem(title: "酒水", image: nil, tag: 3)

        let expiry = UINavigationController(rootViewController: ExpiryAuthViewController())
        expiry.tabBarItem = UITabBarItem(title: "有效期", image: nil, tag: 4)

        let sales = UINavigationController(rootViewController: SalesRecordViewController())
        sales.tabBarItem = UITabBarItem(title: "销售", image: nil, tag: 5)

        let devices = UINavigationController(rootViewController: DeviceManageViewController())
        devices.tabBarItem = UITabBarItem(title: "设备", image: nil, tag: 6)

        viewControllers = [dashboard, zoneTable, price, beverage, expiry, sales, devices]

        // 自动启动服务器
        TCPServer.shared.start()
    }
}

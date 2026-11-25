import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let library = LibraryViewController()
        let navigation = ReaderNavigationController(rootViewController: library)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window

        UIScreen.main.brightness = ReaderSettings.shared.brightness
        NightAutoScheduler.shared.start()
        return true
    }

    /// 启动密码：每次回到前台都要重新验证（原版「启动密码」）。
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard AppLock.shared.isEnabled,
              window?.rootViewController?.presentedViewController == nil else { return }
        let gate = AppLockGateViewController()
        let navigation = UINavigationController(rootViewController: gate)
        window?.rootViewController?.present(navigation, animated: false, completion: nil)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        ReadingClock.shared.stop()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        ReadingClock.shared.stop()
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard url.isFileURL else { return false }
        _ = BookStore.shared.importFile(from: url)
        NotificationCenter.default.post(name: .libraryChanged, object: nil)
        return true
    }
}

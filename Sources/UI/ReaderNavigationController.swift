import UIKit

/// Lets the visible reader control the status bar (hidden in immersive mode,
/// light content in dark themes) instead of the navigation bar's default.
final class ReaderNavigationController: UINavigationController {

    override var childForStatusBarHidden: UIViewController? {
        return topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        return topViewController
    }
}

extension UINavigationController {

    func applyReaderTheme(_ theme: ReaderTheme) {
        navigationBar.barTintColor = theme.barBackground
        navigationBar.tintColor = theme.accent
        navigationBar.titleTextAttributes = [.foregroundColor: theme.text]
        navigationBar.barStyle = theme.isDark ? .black : .default
    }

    func resetReaderTheme() {
        navigationBar.barTintColor = nil
        navigationBar.tintColor = nil
        navigationBar.titleTextAttributes = nil
        navigationBar.barStyle = .default
    }
}

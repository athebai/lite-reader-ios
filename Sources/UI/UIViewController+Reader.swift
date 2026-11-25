import UIKit

extension UIViewController {

    /// True when the reader is actually being popped or its navigation stack dismissed,
    /// as opposed to a settings panel being presented on top of it.
    var isLeavingReader: Bool {
        if isMovingFromParent { return true }
        if let navigation = navigationController, navigation.isBeingDismissed { return true }
        if isBeingDismissed { return true }
        return false
    }
}

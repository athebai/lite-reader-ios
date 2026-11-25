import UIKit

enum ReaderTheme: Int, CaseIterable {
    case day = 0
    case sepia = 1
    case paper = 2
    case night = 3
    case black = 4

    var title: String {
        switch self {
        case .day:   return "日间"
        case .sepia: return "护眼"
        case .paper: return "羊皮纸"
        case .night: return "夜间"
        case .black: return "纯黑"
        }
    }

    var isDark: Bool {
        return self == .night || self == .black
    }

    var background: UIColor {
        switch self {
        case .day:
            return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
        case .sepia:
            return UIColor(red: 0.96, green: 0.93, blue: 0.83, alpha: 1.0)
        case .paper:
            return UIColor(red: 0.93, green: 0.89, blue: 0.79, alpha: 1.0)
        case .night:
            return UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)
        case .black:
            return UIColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.0)
        }
    }

    var text: UIColor {
        switch self {
        case .day:
            return UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        case .sepia:
            return UIColor(red: 0.30, green: 0.24, blue: 0.14, alpha: 1.0)
        case .paper:
            return UIColor(red: 0.27, green: 0.21, blue: 0.12, alpha: 1.0)
        case .night:
            return UIColor(red: 0.80, green: 0.80, blue: 0.82, alpha: 1.0)
        case .black:
            return UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0)
        }
    }

    var secondary: UIColor {
        return text.withAlphaComponent(0.55)
    }

    var barBackground: UIColor {
        switch self {
        case .day:
            return UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
        case .sepia, .paper:
            return background
        case .night:
            return UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
        case .black:
            return UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1.0)
        }
    }

    var accent: UIColor {
        switch self {
        case .day:
            return UIColor(red: 0.31, green: 0.38, blue: 0.50, alpha: 1.0)
        case .sepia, .paper:
            return UIColor(red: 0.46, green: 0.33, blue: 0.17, alpha: 1.0)
        case .night, .black:
            return UIColor(red: 0.70, green: 0.70, blue: 0.74, alpha: 1.0)
        }
    }
}

extension UIColor {
    var cssHex: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)),
                      Int(round(g * 255)),
                      Int(round(b * 255)))
    }
}

enum FlipMode: Int {
    case vertical = 0
    case slide = 1
    case flip = 2

    var title: String {
        switch self {
        case .vertical: return "上下滚动"
        case .slide:    return "左右平移"
        case .flip:     return "仿真翻页"
        }
    }

    /// Left/right paging puts the reader in "zone tap" mode, like the
    /// original app's 左右区域模式 for paged animations.
    var isHorizontal: Bool {
        return self != .vertical
    }
}

extension Notification.Name {
    static let readerSettingsChanged = Notification.Name("lite.reader.settingsChanged")
}

final class ReaderSettings {

    static let shared = ReaderSettings()

    private let defaults = UserDefaults.standard

    /// Posts `readerSettingsChanged` so open readers can re-apply styles.
    private func changed() {
        NotificationCenter.default.post(name: .readerSettingsChanged, object: self)
    }

    var theme: ReaderTheme {
        get { return ReaderTheme(rawValue: defaults.integer(forKey: "rd.theme")) ?? .sepia }
        set { defaults.set(newValue.rawValue, forKey: "rd.theme") }
    }

    var fontName: String {
        get { return defaults.string(forKey: "rd.fontName") ?? "" }
        set { defaults.set(newValue, forKey: "rd.fontName") }
    }

    var fontSize: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.fontSize")
            return value >= 10 ? CGFloat(value) : 19
        }
        set { defaults.set(Double(newValue), forKey: "rd.fontSize") }
    }

    var lineSpacing: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.lineSpacing")
            return value > 0 ? CGFloat(value) : 8
        }
        set { defaults.set(Double(newValue), forKey: "rd.lineSpacing") }
    }

    var margin: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.margin")
            return value >= 8 ? CGFloat(value) : 18
        }
        set { defaults.set(Double(newValue), forKey: "rd.margin") }
    }

    var autoScrollSpeed: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.autoScroll")
            return value > 0 ? CGFloat(value) : 30
        }
        set { defaults.set(Double(newValue), forKey: "rd.autoScroll") }
    }

    var keepScreenAwake: Bool {
        get {
            if defaults.object(forKey: "rd.keepAwake") == nil { return true }
            return defaults.bool(forKey: "rd.keepAwake")
        }
        set { defaults.set(newValue, forKey: "rd.keepAwake") }
    }

    var autoOpenLastBook: Bool {
        get {
            if defaults.object(forKey: "rd.autoOpen") == nil { return false }
            return defaults.bool(forKey: "rd.autoOpen")
        }
        set { defaults.set(newValue, forKey: "rd.autoOpen") }
    }

    var speechRate: Float {
        get {
            let value = defaults.double(forKey: "rd.speechRate")
            return value > 0 ? Float(value) : 0.48
        }
        set { defaults.set(Double(newValue), forKey: "rd.speechRate") }
    }

    var brightness: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.brightness")
            return value > 0 ? CGFloat(value) : UIScreen.main.brightness
        }
        set { defaults.set(Double(newValue), forKey: "rd.brightness") }
    }

    var flipMode: FlipMode {
        get { return FlipMode(rawValue: defaults.integer(forKey: "rd.flipMode")) ?? .vertical }
        set { defaults.set(newValue.rawValue, forKey: "rd.flipMode"); changed() }
    }

    /// First-line indent, expressed in characters instead of a fixed point
    /// size (原版「首行缩进字数」)。
    var indentChars: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.indent")
            return value >= 0 ? CGFloat(value) : 2
        }
        set { defaults.set(Double(newValue), forKey: "rd.indent"); changed() }
    }

    var letterSpacing: CGFloat {
        get {
            let value = defaults.double(forKey: "rd.letterSpacing")
            return value != 0 ? CGFloat(value) : 0
        }
        set { defaults.set(Double(newValue), forKey: "rd.letterSpacing"); changed() }
    }

    /// Volume keys page the reader instead of changing the media volume.
    var volumeKeyNav: Bool {
        get { return defaults.bool(forKey: "rd.volumeNav") }
        set { defaults.set(newValue, forKey: "rd.volumeNav"); changed() }
    }

    /// Switch to the night theme inside a time window (原版「跟随系统深色模式」
    /// 与「执行条件: 上次阅读是在晚上」的思路)。
    var nightAutoEnabled: Bool {
        get { return defaults.bool(forKey: "rd.nightAuto") }
        set { defaults.set(newValue, forKey: "rd.nightAuto"); changed() }
    }

    var nightStartHour: Int {
        get {
            if defaults.object(forKey: "rd.nightStart") == nil { return 22 }
            return defaults.integer(forKey: "rd.nightStart")
        }
        set { defaults.set(newValue, forKey: "rd.nightStart"); changed() }
    }

    var nightEndHour: Int {
        get {
            if defaults.object(forKey: "rd.nightEnd") == nil { return 7 }
            return defaults.integer(forKey: "rd.nightEnd")
        }
        set { defaults.set(newValue, forKey: "rd.nightEnd"); changed() }
    }

    /// Minutes of continuous reading before a "take a break" alert appears
    /// (原版「连续阅读时间超过设置值时提醒」)。0 表示关闭。
    var restReminderMinutes: Int {
        get {
            let value = defaults.integer(forKey: "rd.restReminder")
            return value > 0 ? value : 30
        }
        set { defaults.set(newValue, forKey: "rd.restReminder"); changed() }
    }

    var restReminderOn: Bool {
        get { return defaults.bool(forKey: "rd.restOn") }
        set { defaults.set(newValue, forKey: "rd.restOn"); changed() }
    }

    var appLockEnabled: Bool {
        get { return defaults.data(forKey: "rd.appLock") != nil }
    }

    var font: UIFont {
        if !fontName.isEmpty, let custom = UIFont(name: fontName, size: fontSize) {
            return custom
        }
        return UIFont.systemFont(ofSize: fontSize)
    }

    var fontChoices: [(name: String, value: String)] {
        return [
            ("系统字体", ""),
            ("宋体", "Songti SC"),
            ("楷体", "Kaiti SC"),
            ("黑体", "PingFang SC"),
            ("衬线 (Georgia)", "Georgia")
        ]
    }
}

import UIKit

/// Presents an alert on whatever view controller is currently on top, which is
/// what the "take a break" and "night is deep" reminders need.
enum AlertPresenter {

    static func present(_ controller: UIViewController, title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default, handler: nil))
        controller.present(alert, animated: true, completion: nil)
    }
}

/// Automatically switches to the night theme inside a time window.
/// Mirrors the original app's 跟随系统深色模式 / 上次阅读是在晚上 conditions.
final class NightAutoScheduler {

    static let shared = NightAutoScheduler()

    private var timer: Timer?
    private let settings = ReaderSettings.shared

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        guard settings.nightAutoEnabled else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let start = settings.nightStartHour
        let end = settings.nightEndHour
        let isNight: Bool
        if start > end {
            isNight = hour >= start || hour < end
        } else if start == end {
            isNight = false
        } else {
            isNight = hour >= start && hour < end
        }
        let wanted: ReaderTheme = isNight ? .night : .day
        if settings.theme != wanted {
            settings.theme = wanted
            NotificationCenter.default.post(name: .readerSettingsChanged, object: self)
        }
    }

    /// True when the current hour falls inside the night window.
    var isNightWindow: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = settings.nightStartHour
        let end = settings.nightEndHour
        if start > end { return hour >= start || hour < end }
        if start == end { return false }
        return hour >= start && hour < end
    }
}

/// Warns after a long continuous reading session (原版「连续阅读时间超过设置值时提醒」)
/// and late at night (「夜已深，请注意休息」).
final class BreakReminder {

    static let shared = BreakReminder()

    private var timer: Timer?
    private var startedAt = Date()
    private let settings = ReaderSettings.shared

    func start() {
        guard timer == nil else { return }
        startedAt = Date()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let minutes = Int(Date().timeIntervalSince(startedAt) / 60)
        if settings.restReminderOn && minutes >= settings.restReminderMinutes {
            AlertPresenter.present(frontController,
                                   title: "请注意休息",
                                   message: "您已连续阅读 \(minutes) 分钟，起来活动一下、看看远处，保护视力。")
            startedAt = Date()
            return
        }
        if NightAutoScheduler.shared.isNightWindow, minutes > 0,
           Calendar.current.component(.hour, from: Date()) >= 23 {
            AlertPresenter.present(frontController,
                                   title: "夜已深",
                                   message: "夜已深，请注意休息。今晚的阅读量已经不少了。")
            startedAt = Date()
        }
    }

    private var frontController: UIViewController {
        let root = UIApplication.shared.keyWindow?.rootViewController ?? UIViewController()
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
import UIKit

final class SliderCell: UITableViewCell {

    let titleLabel = UILabel(frame: .zero)
    let slider = UISlider(frame: .zero)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 16)
        slider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        contentView.addSubview(slider)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 72),
            slider.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            slider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SettingsViewController: UITableViewController {

    var onChange: (() -> Void)?

    private let settings = ReaderSettings.shared

    private enum AppearanceRow: Int {
        case theme = 0
        case font = 1
        case fontSize = 2
        case lineSpacing = 3
        case margin = 4
        case indent = 5
        case letterSpacing = 6
    }

    private enum ReadingRow: Int {
        case brightness = 0
        case autoScroll = 1
        case speechRate = 2
        case keepAwake = 3
        case flipMode = 4
        case volumeKeys = 5
    }

    private enum GuardRow: Int {
        case nightAuto = 0
        case restReminder = 1
        case restInterval = 2
        case appLock = 3
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读设置"
        tableView.tableFooterView = UIView()
        tableView.rowHeight = 48
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成",
                                                           style: .done,
                                                           target: self,
                                                           action: #selector(closeSelf))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "恢复默认",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(resetDefaults))
    }

    @objc private func closeSelf() {
        dismiss(animated: true, completion: nil)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 7
        case 1: return 6
        case 2: return 1
        case 3: return 4
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "外观"
        case 1: return "阅读"
        case 2: return "启动"
        case 3: return "提醒与保护"
        default: return "关于"
        }
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 && indexPath.row == ReadingRow.brightness.rawValue {
            return brightnessCell(tableView, indexPath: indexPath)
        }

        let identifier = "ValueCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.detailTextLabel?.textColor = settings.theme.accent

        switch indexPath.section {
        case 0:
            if indexPath.row == AppearanceRow.theme.rawValue {
                cell.textLabel?.text = "主题"
                cell.detailTextLabel?.text = settings.theme.title
            } else if indexPath.row == AppearanceRow.font.rawValue {
                cell.textLabel?.text = "字体"
                var fontTitle = "系统字体"
                for choice in settings.fontChoices where choice.value == settings.fontName {
                    fontTitle = choice.name
                }
                cell.detailTextLabel?.text = fontTitle
            } else if indexPath.row == AppearanceRow.fontSize.rawValue {
                cell.textLabel?.text = "字号"
                cell.detailTextLabel?.text = "\(Int(settings.fontSize)) pt"
                cell.accessoryView = makeStepper(value: Double(settings.fontSize),
                                                 minimum: 12, maximum: 34, step: 1,
                                                 tag: 101)
            } else if indexPath.row == AppearanceRow.lineSpacing.rawValue {
                cell.textLabel?.text = "行距"
                cell.detailTextLabel?.text = "\(Int(settings.lineSpacing)) pt"
                cell.accessoryView = makeStepper(value: Double(settings.lineSpacing),
                                                 minimum: 0, maximum: 24, step: 2,
                                                 tag: 102)
            } else if indexPath.row == AppearanceRow.indent.rawValue {
                cell.textLabel?.text = "首行缩进"
                cell.detailTextLabel?.text = "\(Int(settings.indentChars)) 字"
                cell.accessoryView = makeStepper(value: Double(settings.indentChars),
                                                 minimum: 0, maximum: 6, step: 1,
                                                 tag: 104)
            } else if indexPath.row == AppearanceRow.letterSpacing.rawValue {
                cell.textLabel?.text = "字间距"
                cell.detailTextLabel?.text = String(format: "%+.1f pt", settings.letterSpacing)
                cell.accessoryView = makeStepper(value: Double(settings.letterSpacing),
                                                 minimum: -1, maximum: 6, step: 0.5,
                                                 tag: 105)
            } else {
                cell.textLabel?.text = "页边距"
                cell.detailTextLabel?.text = "\(Int(settings.margin)) pt"
                cell.accessoryView = makeStepper(value: Double(settings.margin),
                                                 minimum: 8, maximum: 40, step: 4,
                                                 tag: 103)
            }
        case 1:
            if indexPath.row == ReadingRow.brightness.rawValue {
                cell.textLabel?.text = "亮度"
            } else if indexPath.row == ReadingRow.autoScroll.rawValue {
                cell.textLabel?.text = "自动滚屏"
                cell.detailTextLabel?.text = "\(Int(settings.autoScrollSpeed)) pt/秒"
                cell.accessoryView = makeStepper(value: Double(settings.autoScrollSpeed),
                                                 minimum: 10, maximum: 120, step: 10,
                                                 tag: 201)
            
            } else if indexPath.row == ReadingRow.flipMode.rawValue {
                cell.textLabel?.text = "翻页方式"
                cell.detailTextLabel?.text = settings.flipMode.title
            } else if indexPath.row == ReadingRow.volumeKeys.rawValue {
                cell.textLabel?.text = "音量键翻页"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: settings.volumeKeyNav, tag: 204)
            } else if indexPath.row == ReadingRow.speechRate.rawValue {
                cell.textLabel?.text = "朗读语速"
                cell.detailTextLabel?.text = String(format: "%.2f", settings.speechRate)
                cell.accessoryView = makeStepper(value: Double(settings.speechRate),
                                                 minimum: 0.30, maximum: 0.70, step: 0.05,
                                                 tag: 202)
            } else {
                cell.textLabel?.text = "屏幕常亮"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: settings.keepScreenAwake, tag: 203)
            }
        case 2:
            cell.textLabel?.text = "自动打开上次的书"
            cell.selectionStyle = .none
            cell.accessoryView = makeSwitch(on: settings.autoOpenLastBook, tag: 301)
        case 3:
            if indexPath.row == GuardRow.nightAuto.rawValue {
                cell.textLabel?.text = "夜间自动切换主题"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: settings.nightAutoEnabled, tag: 205)
            } else if indexPath.row == GuardRow.restReminder.rawValue {
                cell.textLabel?.text = "连续阅读提醒"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: settings.restReminderOn, tag: 206)
            } else if indexPath.row == GuardRow.restInterval.rawValue {
                cell.textLabel?.text = "提醒间隔"
                cell.detailTextLabel?.text = "\(settings.restReminderMinutes) 分钟"
                cell.accessoryView = makeStepper(value: Double(settings.restReminderMinutes),
                                                 minimum: 5, maximum: 120, step: 5,
                                                 tag: 207)
            } else {
                cell.textLabel?.text = "启动密码"
                cell.detailTextLabel?.text = AppLock.shared.isEnabled ? "已开启" : "未设置"
            }
        default:
            cell.textLabel?.text = "轻阅读"
            cell.detailTextLabel?.text = "1.0 · iOS 12+"
            cell.selectionStyle = .default
        }
        return cell
    }

    private func brightnessCell(_ tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let identifier = "SliderCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) as? SliderCell
            ?? SliderCell(style: .default, reuseIdentifier: identifier)
        cell.titleLabel.text = "亮度"
        cell.slider.minimumValue = 0.05
        cell.slider.maximumValue = 1.0
        cell.slider.value = Float(UIScreen.main.brightness)
        cell.slider.tintColor = settings.theme.accent
        cell.slider.addTarget(self, action: #selector(brightnessChanged(_:)), for: .valueChanged)
        return cell
    }

    private func makeStepper(value: Double, minimum: Double, maximum: Double,
                             step: Double, tag: Int) -> UIStepper {
        let stepper = UIStepper()
        stepper.minimumValue = minimum
        stepper.maximumValue = maximum
        stepper.stepValue = step
        stepper.value = value
        stepper.tag = tag
        stepper.addTarget(self, action: #selector(stepperChanged(_:)), for: .valueChanged)
        return stepper
    }

    private func makeSwitch(on: Bool, tag: Int) -> UISwitch {
        let toggle = UISwitch()
        toggle.isOn = on
        toggle.tag = tag
        toggle.onTintColor = settings.theme.accent
        toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        return toggle
    }

    @objc private func brightnessChanged(_ sender: UISlider) {
        UIScreen.main.brightness = CGFloat(sender.value)
        settings.brightness = CGFloat(sender.value)
    }

    @objc private func stepperChanged(_ sender: UIStepper) {
        switch sender.tag {
        case 101:
            settings.fontSize = CGFloat(sender.value)
        case 102:
            settings.lineSpacing = CGFloat(sender.value)
        case 103:
            settings.margin = CGFloat(sender.value)
        case 104:
            settings.indentChars = CGFloat(sender.value)
        case 105:
            settings.letterSpacing = CGFloat(sender.value)
        case 207:
            settings.restReminderMinutes = Int(sender.value.rounded())
        case 201:
            settings.autoScrollSpeed = CGFloat(sender.value)
        case 202:
            settings.speechRate = Float(sender.value)
        default:
            break
        }
        tableView.reloadData()
        onChange?()
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        if sender.tag == 203 {
            settings.keepScreenAwake = sender.isOn
            UIApplication.shared.isIdleTimerDisabled = sender.isOn
        } else if sender.tag == 301 {
            settings.autoOpenLastBook = sender.isOn
        } else if sender.tag == 204 {
            settings.volumeKeyNav = sender.isOn
        } else if sender.tag == 205 {
            settings.nightAutoEnabled = sender.isOn
            NightAutoScheduler.shared.tick()
        } else if sender.tag == 206 {
            settings.restReminderOn = sender.isOn
        }
        onChange?()
    }

    @objc private func resetDefaults() {
        settings.theme = .sepia
        settings.fontName = ""
        settings.fontSize = 19
        settings.lineSpacing = 8
        settings.margin = 18
        settings.indentChars = 2
        settings.letterSpacing = 0
        settings.flipMode = .vertical
        settings.autoScrollSpeed = 30
        settings.speechRate = 0.48
        tableView.reloadData()
        onChange?()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == AppearanceRow.theme.rawValue {
            chooseTheme()
        } else if indexPath.section == 0 && indexPath.row == AppearanceRow.font.rawValue {
            chooseFont()
        } else if indexPath.section == 1 && indexPath.row == ReadingRow.flipMode.rawValue {
            chooseFlipMode()
        } else if indexPath.section == 3 && indexPath.row == GuardRow.appLock.rawValue {
            changeAppLock()
        } else if indexPath.section == 4 {
            let alert = UIAlertController(title: "轻阅读 1.0",
                                          message: "轻量本地阅读器\n支持 TXT / EPUB / PDF / DOCX / RTF / HTML\n\n功能参考「静读天下」整理：书架、目录、书签、全文搜索、朗读、自动滚屏、主题与字号。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }

    private func chooseTheme() {
        let alert = UIAlertController(title: "阅读主题", message: nil, preferredStyle: .actionSheet)
        for theme in ReaderTheme.allCases {
            alert.addAction(UIAlertAction(title: theme.title, style: .default, handler: { [weak self] _ in
                self?.settings.theme = theme
                self?.tableView.reloadData()
                self?.onChange?()
            }))
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(alert)
    }

    private func chooseFlipMode() {
        let sheet = UIAlertController(title: "翻页方式", message: nil, preferredStyle: .actionSheet)
        for mode in [FlipMode.vertical, FlipMode.slide, FlipMode.flip] {
            let suffix = mode == settings.flipMode ? "（当前）" : ""
            sheet.addAction(UIAlertAction(title: mode.title + suffix, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                self.settings.flipMode = mode
                self.tableView.reloadData()
                self.onChange?()
            }))
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(sheet)
    }

    private func changeAppLock() {
        let alert = UIAlertController(title: "设置阅读器保护密码", message: nil,
                                       preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "新密码" }
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "再次输入密码" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "关闭密码", style: .default, handler: { _ in
            AppLock.shared.setPassword("")
        }))
        alert.addAction(UIAlertAction(title: "设定", style: .default, handler: { [weak self] _ in
            let first = alert.textFields?.first?.text ?? ""
            let second = alert.textFields?.last?.text ?? ""
            if !first.isEmpty, first == second {
                AppLock.shared.setPassword(first)
                self?.tableView.reloadData()
            } else {
                let error = UIAlertController(title: "两次输入的密码不同",
                                             message: "请重新输入。",
                                             preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
                self?.present(error, animated: true, completion: nil)
            }
        }))
        present(alert, animated: true, completion: nil)
    }

    private func chooseFont() {
        let alert = UIAlertController(title: "字体", message: nil, preferredStyle: .actionSheet)
        for choice in settings.fontChoices {
            alert.addAction(UIAlertAction(title: choice.name, style: .default, handler: { [weak self] _ in
                self?.settings.fontName = choice.value
                self?.tableView.reloadData()
                self?.onChange?()
            }))
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(alert)
    }

    private func presentSheet(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true, completion: nil)
    }
}

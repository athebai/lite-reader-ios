import UIKit

/// Local launch password (原版「设置阅读器保护密码 / 登录密码 / 密码验证」)。
/// FNV-1a stretched over many rounds — a nudge for kids and borrowed phones,
/// not a vault.
final class AppLock {

    static let shared = AppLock()

    private let defaults = UserDefaults.standard
    private let key = "rd.appLockHex"
    private let salt = "LiteReader·1.0"

    var isEnabled: Bool {
        return defaults.string(forKey: key) != nil
    }

    /// Pass an empty string to switch the lock off.
    func setPassword(_ password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(digest(trimmed), forKey: key)
    }

    func verify(_ password: String) -> Bool {
        guard isEnabled else { return true }
        return digest(password) == (defaults.string(forKey: key) ?? "")
    }

    private func digest(_ password: String) -> String {
        var hash: UInt64 = 14695981039346656037
        let source = "\(salt)-\(password)".utf8
        for round in 0..<4000 {
            for byte in source {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            hash ^= UInt64(round)
        }
        return String(hash, radix: 16)
    }
}

/// Full screen gate shown at launch when a password is set.
final class AppLockGateViewController: UIViewController {

    var onUnlocked: (() -> Void)?

    private let field = UITextField(frame: .zero)
    private let hint = UILabel(frame: .zero)
    private let button = UIButton(type: .system)
    private let title = UILabel(frame: .zero)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "密码验证"

        title.text = "轻阅读"
        title.font = UIFont.systemFont(ofSize: 22, weight: .medium)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        field.isSecureTextEntry = true
        field.placeholder = "登录密码"
        field.font = UIFont.systemFont(ofSize: 19)
        field.clearButtonMode = .whileEditing
        field.borderStyle = .line
        field.autocorrectionType = .no
        field.translatesAutoresizingMaskIntoConstraints = false

        hint.text = "两次输入的密码不同, 请重新输入"
        hint.font = UIFont.systemFont(ofSize: 13)
        hint.textColor = UIColor(red: 0.78, green: 0.15, blue: 0.15, alpha: 1.0)
        hint.isHidden = true
        hint.translatesAutoresizingMaskIntoConstraints = false

        button.setTitle("确定", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(field)
        view.addSubview(hint)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 120),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            field.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 28),
            hint.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            hint.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
            button.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            button.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
            button.heightAnchor.constraint(equalToConstant: 48)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "修改密码",
                                                              style: .plain,
                                                              target: self,
                                                              action: #selector(changePassword))
    }

    @objc private func submit() {
        let password = field.text ?? ""
        guard AppLock.shared.verify(password) else {
            field.text = ""
            hint.isHidden = false
            field.becomeFirstResponder()
            return
        }
        hint.isHidden = true
        dismiss(animated: true, completion: { [weak self] in
            self?.onUnlocked?()
        })
    }

    @objc private func changePassword() {
        let alert = UIAlertController(title: "设置阅读器保护密码", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "新密码" }
        alert.addTextField { $0.isSecureTextEntry = true; $0.placeholder = "再次输入密码" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "关闭密码", style: .default, handler: { [weak self] _ in
            AppLock.shared.setPassword("")
            self?.onUnlocked?()
            self?.dismiss(animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "设定", style: .default, handler: { [weak self] _ in
            let first = alert.textFields?.first?.text ?? ""
            let second = alert.textFields?.last?.text ?? ""
            if !first.isEmpty, first == second {
                AppLock.shared.setPassword(first)
                self?.hint.text = "启动密码设定成功."
                self?.hint.textColor = UIColor(red: 0.13, green: 0.60, blue: 0.24, alpha: 1.0)
                self?.hint.isHidden = false
            } else {
                self?.hint.text = "两次输入的密码不同, 请重新输入"
                self?.hint.isHidden = false
            }
        }))
        present(alert, animated: true, completion: nil)
    }
}
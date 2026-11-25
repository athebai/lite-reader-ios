import UIKit

struct ChoiceItem {
    let title: String
    let subtitle: String?
    let checked: Bool

    init(title: String, subtitle: String? = nil, checked: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.checked = checked
    }
}

final class ChoiceListViewController: UITableViewController {

    private var items: [ChoiceItem]
    private let emptyText: String

    var onSelect: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?

    init(title: String, items: [ChoiceItem], emptyText: String = "没有内容") {
        self.items = items
        self.emptyText = emptyText
        super.init(style: .plain)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.tableFooterView = UIView()
        tableView.rowHeight = 54
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "关闭",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(closeSelf))
        updateEmptyState()
    }

    private func updateEmptyState() {
        if items.isEmpty {
            let label = UILabel(frame: tableView.bounds)
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            label.text = emptyText
            label.textAlignment = .center
            label.textColor = .gray
            label.numberOfLines = 0
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    @objc private func closeSelf() {
        dismiss(animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "ChoiceCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.textColor = .gray
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = item.checked ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let index = indexPath.row
        onSelect?(index)
        dismiss(animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let index = indexPath.row
        guard index < items.count else { return }
        items.remove(at: index)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        onDelete?(index)
        updateEmptyState()
    }
}

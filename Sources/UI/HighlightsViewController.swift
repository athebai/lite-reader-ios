import UIKit

/// Lists every highlight of one book, with jump / delete / clear / export.
final class HighlightsViewController: UITableViewController {

    private let bookName: String
    private let bookTitle: String

    private var highlights: [Highlight] = []

    /// Called with a book-wide ratio when the reader should jump there.
    var onJump: ((Double) -> Void)?

    init(bookName: String, bookTitle: String) {
        self.bookName = bookName
        self.bookTitle = bookTitle
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "高亮 \(highlights.count)"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 62
        tableView.tableFooterView = UIView()

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "导出",
                                                             style: .plain,
                                                             target: self,
                                                             action: #selector(exportAll))
        let clear = UIBarButtonItem(title: "清空", style: .plain,
                                    target: self, action: #selector(clearAll))
        navigationItem.leftBarButtonItem = clear
        reload()
    }

    private func reload() {
        highlights = HighlightsStore.shared.highlights(for: bookName)
        title = highlights.isEmpty ? "高亮" : "高亮 \(highlights.count)"
        tableView.reloadData()
    }

    @objc private func exportAll() {
        guard !highlights.isEmpty else { return }
        let text = HighlightsStore.shared.exportText(for: bookName, title: bookTitle)
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activity, animated: true, completion: nil)
    }

    @objc private func clearAll() {
        guard !highlights.isEmpty else { return }
        let alert = UIAlertController(title: "删除本书所有高亮？",
                                      message: "已选中的文字标记会一并清除，无法恢复。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive, handler: { [weak self] _ in
            HighlightsStore.shared.removeAll(for: self?.bookName ?? "")
            self?.reload()
        }))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return highlights.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "HighlightCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? HighlightCell(style: .default,
                                                                                       reuseIdentifier: identifier)
        cell.selectionStyle = .none
        let item = highlights[indexPath.row]
        cell.bar.backgroundColor = HighlightColor.color(item.color)
        cell.textLabel?.text = item.text
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = nil
        cell.detailTextLabel?.textColor = .gray

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        cell.subtitle = " \(Int(item.ratio * 100))%  ·  \(formatter.string(from: item.date))\(item.note.isEmpty ? "" : "  ·  " + item.note)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < highlights.count else { return }
        onJump?(highlights[indexPath.row].ratio)
        dismiss(animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView,
                            commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.row < highlights.count else { return }
        HighlightsStore.shared.remove(at: indexPath.row, for: bookName)
        reload()
    }
}

private final class HighlightCell: UITableViewCell {

    let bar = UIView(frame: .zero)

    var subtitle: String? {
        didSet {
            detailTextLabel?.text = subtitle
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        bar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bar.topAnchor.constraint(equalTo: contentView.topAnchor),
            bar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4)
        ])
        textLabel?.numberOfLines = 0
        detailTextLabel?.numberOfLines = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
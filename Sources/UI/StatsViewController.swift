import UIKit

final class StatsViewController: UITableViewController {

    private var overview: [(String, String)] = []
    private var books: [(name: String, seconds: Double)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "阅读统计"
        tableView.tableFooterView = UIView()
        tableView.rowHeight = 48
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "清空",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(clearStats))
        reloadData()
    }

    private func reloadData() {
        let stats = ReadingStats.shared
        let week = stats.dailyHistory.prefix(7).reduce(0.0) { $0 + $1.seconds }
        overview = [
            ("今日阅读", formatDuration(stats.todaySeconds)),
            ("最近 7 天", formatDuration(week)),
            ("累计阅读", formatDuration(stats.totalSeconds)),
            ("连续阅读", "\(stats.streakDays) 天")
        ]
        let shelf = BookStore.shared.books
        let finished = shelf.filter {
            ProgressStore.shared.ratio(for: $0.fileName) >= 0.999
        }.count
        overview += [
            ("书架总数", "\(shelf.count) 本"),
            ("已读完", "\(finished) 本"),
            ("阅读速度", String(format: "%.0f 字/分钟", stats.readingSpeed))
        ]
        books = stats.topBooks(8)
        tableView.reloadData()
    }

    @objc private func clearStats() {
        let alert = UIAlertController(title: "清空阅读统计？",
                                      message: "只清除阅读时长记录，不会删除书籍。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive, handler: { [weak self] _ in
            ReadingStats.shared.reset()
            self?.reloadData()
        }))
        present(alert, animated: true, completion: nil)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? overview.count : max(1, books.count)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return "总览" }
        return books.isEmpty ? nil : "最常阅读"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && books.isEmpty {
            return "阅读超过 3 秒会自动记录时长。"
        }
        return nil
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "StatsCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .value1, reuseIdentifier: identifier)
        cell.selectionStyle = .none

        if indexPath.section == 0 {
            let item = overview[indexPath.row]
            cell.textLabel?.text = item.0
            cell.detailTextLabel?.text = item.1
            cell.detailTextLabel?.textColor = .gray
        } else if books.isEmpty {
            cell.textLabel?.text = "还没有阅读记录"
            cell.textLabel?.textColor = .gray
            cell.detailTextLabel?.text = nil
        } else {
            let item = books[indexPath.row]
            var title = item.name
            if let dot = title.range(of: ".", options: .backwards) {
                title = String(title[title.startIndex..<dot.lowerBound])
            }
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = formatDuration(item.seconds)
            cell.detailTextLabel?.textColor = .gray
        }
        return cell
    }
}

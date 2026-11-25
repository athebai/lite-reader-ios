import UIKit

extension Notification.Name {
    static let libraryChanged = Notification.Name("lite.library.changed")
}

final class BookCell: UICollectionViewCell {

    static let reuseIdentifier = "BookCell"

    private let coverView = UIImageView(frame: .zero)
    private let titleLabel = UILabel(frame: .zero)
    private let subtitleLabel = UILabel(frame: .zero)
    private let starLabel = UILabel(frame: .zero)
    private let progressBar = UIProgressView(progressViewStyle: .bar)

    private var isGridMode = true
    private var bookKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = false
        clipsToBounds = false

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 5
        coverView.backgroundColor = UIColor(white: 0.90, alpha: 1.0)
        coverView.layer.borderWidth = 0.5
        coverView.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor

        titleLabel.numberOfLines = 2
        titleLabel.textColor = UIColor(white: 0.15, alpha: 1.0)

        subtitleLabel.textColor = UIColor(white: 0.50, alpha: 1.0)

        starLabel.text = "★"
        starLabel.textColor = UIColor(red: 0.86, green: 0.62, blue: 0.16, alpha: 1.0)
        starLabel.textAlignment = .center

        progressBar.trackTintColor = UIColor(white: 0, alpha: 0.06)
        progressBar.progressTintColor = UIColor(red: 0.31, green: 0.38, blue: 0.50, alpha: 1.0)
        progressBar.isHidden = true

        contentView.addSubview(coverView)
        contentView.addSubview(progressBar)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(starLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(book: Book, progress: Double, isGrid: Bool) {
        isGridMode = isGrid
        bookKey = book.key

        titleLabel.text = book.title
        titleLabel.font = UIFont.systemFont(ofSize: isGrid ? 13 : 16, weight: .regular)
        titleLabel.numberOfLines = isGrid ? 2 : 1
        subtitleLabel.font = UIFont.systemFont(ofSize: isGrid ? 11 : 12, weight: .regular)

        var parts: [String] = [book.type.displayName]
        if progress > 0.001 {
            parts.append("\(Int(progress * 100))%")
        } else {
            parts.append(book.sizeText)
        }
        subtitleLabel.text = parts.joined(separator: " · ")
        starLabel.isHidden = !BookStore.shared.isFavorite(book)
        progressBar.progress = Float(max(0, min(1, progress)))
        progressBar.isHidden = progress <= 0.002

        if let image = CoverCache.shared.cachedCover(for: book) {
            coverView.image = image
        } else {
            coverView.image = nil
            let key = book.key
            CoverCache.shared.cover(for: book, size: CGSize(width: 240, height: 340)) { [weak self] image in
                guard let self = self, self.bookKey == key else { return }
                self.coverView.image = image
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        if isGridMode {
            let coverHeight = max(60, bounds.height - 62)
            coverView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: coverHeight)
            progressBar.frame = CGRect(x: 0, y: coverView.frame.maxY - 4,
                                        width: bounds.width, height: 4)
            titleLabel.frame = CGRect(x: 0, y: coverHeight + 6, width: bounds.width, height: 34)
            subtitleLabel.frame = CGRect(x: 0, y: coverHeight + 42, width: bounds.width, height: 16)
            starLabel.frame = CGRect(x: bounds.width - 20, y: 6, width: 16, height: 16)
        } else {
            coverView.frame = CGRect(x: 0, y: 6, width: 48, height: 64)
            progressBar.frame = CGRect(x: 0, y: coverView.frame.maxY - 4,
                                        width: coverView.frame.width, height: 4)
            titleLabel.frame = CGRect(x: 60, y: 14, width: bounds.width - 80, height: 22)
            subtitleLabel.frame = CGRect(x: 60, y: 38, width: bounds.width - 80, height: 18)
            starLabel.frame = CGRect(x: bounds.width - 26, y: 24, width: 16, height: 16)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.image = nil
        progressBar.isHidden = true
        bookKey = ""
    }
}

final class LibraryViewController: UIViewController {

    /// 原版书架可按未读/在读/已读筛选（「未读」「已读书籍总数」）。
    private enum ReadingFilter: Int {
        case all = 0
        case unread = 1
        case reading = 2
        case finished = 3

        var text: String {
            switch self {
            case .all:      return "全部"
            case .unread:    return "未读"
            case .reading:   return "在读"
            case .finished:  return "已读"
            }
        }

        func matches(ratio: Double) -> Bool {
            switch self {
            case .all:      return true
            case .unread:    return ratio <= 0.002
            case .reading:   return ratio > 0.002 && ratio < 0.999
            case .finished: return ratio >= 0.999
            }
        }
    }

    private enum SortMode: Int {
        case recent = 0
        case title = 1
        case size = 2
        case favorite = 3

        var text: String {
            switch self {
            case .recent:   return "最近阅读"
            case .title:    return "书名"
            case .size:     return "文件大小"
            case .favorite: return "收藏优先"
            }
        }
    }

    private let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let emptyLabel = UILabel(frame: .zero)
    private let searchController = UISearchController(searchResultsController: nil)

    private var books: [Book] = []
    private var query = ""
    private var sortMode: SortMode = .recent
    private var readingFilter: ReadingFilter = .all
    private var isGridMode = true
    private var lastWidth: CGFloat = 0
    private var didAutoOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "书库"
        view.backgroundColor = .white

        let hasSavedLayout = UserDefaults.standard.object(forKey: "library.grid") != nil
        isGridMode = hasSavedLayout ? UserDefaults.standard.bool(forKey: "library.grid") : true

        setupCollectionView()
        setupNavigation()
        setupSearch()
        setupEmptyLabel()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadBooks),
                                               name: .libraryChanged,
                                               object: nil)

        reloadBooks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.resetReaderTheme()
        reloadBooks()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if didAutoOpen { return }
        didAutoOpen = true
        guard ReaderSettings.shared.autoOpenLastBook,
              let name = ProgressStore.shared.lastBook,
              let book = BookStore.shared.books.first(where: { $0.fileName == name }) else {
            return
        }
        openBook(book)
    }

    private func setupCollectionView() {
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(BookCell.self, forCellWithReuseIdentifier: BookCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPress)
    }

    private func setupNavigation() {
        let sortItem = UIBarButtonItem(title: "排序", style: .plain,
                                       target: self, action: #selector(showSortMenu))
        let statsItem = UIBarButtonItem(title: "统计", style: .plain,
                                        target: self, action: #selector(showStats))
        navigationItem.leftBarButtonItems = [sortItem, statsItem]

        let addItem = UIBarButtonItem(barButtonSystemItem: .add,
                                      target: self, action: #selector(importBook))
        let layoutItem = UIBarButtonItem(title: isGridMode ? "列表" : "网格",
                                         style: .plain,
                                         target: self, action: #selector(toggleLayout))
        navigationItem.rightBarButtonItems = [addItem, layoutItem]
    }

    private func setupSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索书名"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "书库是空的\n点右上角 + 从「文件」导入\nTXT / EPUB / PDF / DOCX / RTF / HTML"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor(white: 0.55, alpha: 1.0)
        emptyLabel.font = UIFont.systemFont(ofSize: 15)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    @objc private func reloadBooks() {
        BookStore.shared.reload()
        var list = BookStore.shared.books

        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }

        switch sortMode {
        case .recent:
            list.sort { first, second in
                let firstDate = ProgressStore.shared.position(for: first.fileName)?.updated ?? first.added
                let secondDate = ProgressStore.shared.position(for: second.fileName)?.updated ?? second.added
                return firstDate > secondDate
            }
        case .title:
            list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size:
            list.sort { $0.fileSize > $1.fileSize }
        case .favorite:
            list.sort { first, second in
                let firstFavorite = BookStore.shared.isFavorite(first)
                let secondFavorite = BookStore.shared.isFavorite(second)
                if firstFavorite != secondFavorite { return firstFavorite }
                return first.added > second.added
            }
        }

        if readingFilter != .all {
            list = list.filter {
                readingFilter.matches(ratio: ProgressStore.shared.ratio(for: $0.fileName))
            }
        }

        books = list
        emptyLabel.isHidden = !books.isEmpty
        collectionView.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if collectionView.bounds.width != lastWidth {
            lastWidth = collectionView.bounds.width
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Actions

    @objc private func toggleLayout() {
        isGridMode = !isGridMode
        UserDefaults.standard.set(isGridMode, forKey: "library.grid")
        if let item = navigationItem.rightBarButtonItems?.last {
            item.title = isGridMode ? "列表" : "网格"
        }
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    @objc private func showSortMenu() {
        let alert = UIAlertController(title: "排序与筛选", message: nil, preferredStyle: .actionSheet)
        for mode in [SortMode.recent, .title, .size, .favorite] {
            alert.addAction(UIAlertAction(title: mode.text, style: .default, handler: { [weak self] _ in
                self?.sortMode = mode
                self?.reloadBooks()
            }))
        }
        for filter in [ReadingFilter.all, .unread, .reading, .finished] {
            let suffix = filter == readingFilter ? "（当前）" : ""
            alert.addAction(UIAlertAction(title: "筛选：" + filter.text + suffix, style: .default,
                                          handler: { [weak self] _ in
                self?.readingFilter = filter
                self?.reloadBooks()
            }))
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        presentSheet(alert)
    }

    @objc private func showStats() {
        let controller = StatsViewController(style: .grouped)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func importBook() {
        let types = ["public.plain-text",
                     "org.idpf.epub-container",
                     "com.adobe.pdf",
                     "public.html",
                     "org.openxmlformats.wordprocessingml.document",
                     "public.rtf"]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true, completion: nil)
    }

    private func openBook(_ book: Book) {
        ProgressStore.shared.lastBook = book.fileName
        let controller: UIViewController
        switch book.type {
        case .pdf:
            controller = PDFReaderViewController(book: book)
        case .epub:
            controller = EPUBReaderViewController(book: book)
        case .html:
            controller = WebReaderViewController(book: book)
        default:
            controller = TextReaderViewController(book: book)
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              indexPath.item < books.count else { return }
        let book = books[indexPath.item]

        let alert = UIAlertController(title: book.title, message: nil, preferredStyle: .actionSheet)
        let favorite = BookStore.shared.isFavorite(book)
        alert.addAction(UIAlertAction(title: favorite ? "取消收藏" : "收藏",
                                      style: .default,
                                      handler: { [weak self] _ in
            BookStore.shared.toggleFavorite(book)
            self?.reloadBooks()
        }))
        alert.addAction(UIAlertAction(title: "查看信息", style: .default, handler: { [weak self] _ in
            self?.showInfo(book)
        }))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive, handler: { [weak self] _ in
            self?.confirmDelete(book)
        }))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = collectionView
            popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }
        present(alert, animated: true, completion: nil)
    }

    private func showInfo(_ book: Book) {
        let position = ProgressStore.shared.ratio(for: book.fileName)
        let message = "格式：\(book.type.displayName)\n大小：\(book.sizeText)\n进度：\(Int(position * 100))%\n加入时间：\(dateText(book.added))"
        let alert = UIAlertController(title: book.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func confirmDelete(_ book: Book) {
        let alert = UIAlertController(title: "删除《\(book.title)》？",
                                      message: "只删除书库中的文件，阅读记录会保留。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive, handler: { [weak self] _ in
            BookStore.shared.delete(book)
            CoverCache.shared.removeCover(for: book)
            self?.reloadBooks()
        }))
        present(alert, animated: true, completion: nil)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func presentSheet(_ alert: UIAlertController) {
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true, completion: nil)
    }
}

// MARK: - Collection view

extension LibraryViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return books.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: BookCell.reuseIdentifier,
                                                      for: indexPath) as? BookCell ?? BookCell(frame: .zero)
        let book = books[indexPath.item]
        let progress = ProgressStore.shared.ratio(for: book.fileName)
        cell.configure(book: book, progress: progress, isGrid: isGridMode)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        if isGridMode {
            let itemWidth = (width - layout.minimumInteritemSpacing) / 2
            return CGSize(width: floor(itemWidth), height: floor(itemWidth * 1.5) + 62)
        }
        return CGSize(width: width, height: 76)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.item < books.count else { return }
        openBook(books[indexPath.item])
    }
}

// MARK: - Search

extension LibraryViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reloadBooks()
    }
}

// MARK: - Document picker

extension LibraryViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        var imported = 0
        for url in urls {
            if BookStore.shared.importFile(from: url) != nil {
                imported += 1
            }
        }
        reloadBooks()
        if imported > 0 {
            NotificationCenter.default.post(name: .libraryChanged, object: nil)
        }
    }
}

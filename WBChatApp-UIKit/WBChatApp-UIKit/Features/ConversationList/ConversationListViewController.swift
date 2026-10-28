import UIKit

/// 抽屉内容页：顶部"新对话 / 设置"，下方会话列表（左滑删除、重命名）。
/// 页面跳转通过回调交给外层（AppContainer）处理。
final class ConversationListViewController: UIViewController {

    /// 选中或新建会话后触发，参数为会话 id
    var onSelect: ((String) -> Void)?
    var onOpenSettings: (() -> Void)?
    /// 某个会话被删除后触发（DB 已经删完）。外层用来判断被删的是不是聊天页正显示的那个会话，
    /// 是的话就把聊天页切走，避免聊天页停留在一个已经不存在的 conversationId 上。
    var onDelete: ((String) -> Void)?

    private let viewModel: ConversationListViewModel
    private let tableView = UITableView(frame: .zero, style: .plain)
    /// 单 section，item 为会话 id
    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    init(viewModel: ConversationListViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.secondaryBackground
        setUpViews()
        setUpDataSource()

        viewModel.onItemsChanged = { [weak self] _ in self?.applySnapshot() }
        viewModel.start()
        applySnapshot()
    }

    private func setUpViews() {
        let header = UIStackView()
        header.axis = .horizontal
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false

        let newButton = UIButton(type: .system)
        newButton.setTitle("＋ 新对话", for: .normal)
        newButton.contentHorizontalAlignment = .leading
        newButton.accessibilityIdentifier = "drawer.newConversation"
        newButton.addTarget(self, action: #selector(handleNew), for: .touchUpInside)

        let settingsButton = UIButton(type: .system)
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.accessibilityIdentifier = "drawer.settings"
        settingsButton.addTarget(self, action: #selector(handleSettings), for: .touchUpInside)

        header.addArrangedSubview(newButton)
        header.addArrangedSubview(settingsButton)

        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "conversation")
        tableView.delegate = self
        tableView.accessibilityIdentifier = "drawer.tableView"

        view.addSubview(header)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setUpDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) {
            [weak self] tableView, indexPath, id in
            let cell = tableView.dequeueReusableCell(withIdentifier: "conversation", for: indexPath)
            let item = self?.viewModel.items.first { $0.id == id }
            var configuration = cell.defaultContentConfiguration()
            configuration.text = item?.title
            configuration.secondaryText = item?.subtitle
            cell.contentConfiguration = configuration
            cell.backgroundColor = .clear
            return cell
        }
    }

    /// 用 ViewModel 当前的 items 刷新列表
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        let ids = viewModel.items.map(\.id)
        snapshot.appendItems(ids)
        // NSDiffableDataSourceSnapshot 只按 id（这里就是 String 本身）做 diff：
        // 重命名不改 id，已经在屏幕上的那一行不会自动重新走 cellProvider,
        // 标题会停留在旧值直到该行因为别的原因（如滚出屏幕再滚回来）被复用重建。
        // 对本次快照里的全部 id 显式 reconfigureItems，保证标题/副标题总能刷新。
        snapshot.reconfigureItems(ids)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    @objc private func handleNew() {
        // `createConversation()` 建库失败时会返回 ""（内部 `try?` 吞掉了错误）。
        // 不判空的话，"" 会被当成一个会话 id 传给 `onSelect`，下游拿它建出的
        // `ChatViewController` 绑定在一个数据库里根本不存在的 conversationId 上——
        // 发消息时 `insertMessage` 一样是 `try?`，外键约束不满足会静默失败，
        // 用户点发送后消息直接消失，且没有任何报错。
        let id = viewModel.createConversation()
        guard !id.isEmpty else { return }
        onSelect?(id)
    }

    @objc private func handleSettings() {
        onOpenSettings?()
    }
}

extension ConversationListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        onSelect?(id)
    }

    /// 左滑：删除（异步，失败弹窗）/ 重命名
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "删除") {
            [weak self] _, _, completion in
            Task { @MainActor [weak self] in
                guard let self else { completion(false); return }
                do {
                    try await self.viewModel.delete(id: id)
                    self.onDelete?(id)
                    completion(true)
                } catch {
                    completion(false)
                    let alert = UIAlertController(title: "删除失败", message: "聊天记录未能删除，请重试", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "好", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
        let rename = UIContextualAction(style: .normal, title: "重命名") {
            [weak self] _, _, completion in
            self?.presentRenameAlert(for: id)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    private func presentRenameAlert(for id: String) {
        let alert = UIAlertController(title: "重命名会话", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = self.viewModel.items.first { $0.id == id }?.title }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.viewModel.rename(id: id, to: alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }
}

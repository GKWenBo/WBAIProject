//
//  CaseListViewController.swift
//  TextKitExample
//

import UIKit

/// 首页：案例目录。
final class CaseListViewController: UITableViewController {

    private let entries = CaseCatalog.all

    init() {
        super.init(style: .insetGrouped)
        title = "TextKit 应用案例"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现，本工程不使用 storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "case")
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "case", for: indexPath)
        let entry = entries[indexPath.row]

        var content = UIListContentConfiguration.subtitleCell()
        content.text = String(format: "%02d  %@", entry.number, entry.title)
        content.secondaryText = entry.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content

        let badge = UILabel()
        badge.text = entry.badge
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .systemBlue
        badge.sizeToFit()
        cell.accessoryView = badge
        cell.accessoryType = .none

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(entries[indexPath.row].make(), animated: true)
    }
}

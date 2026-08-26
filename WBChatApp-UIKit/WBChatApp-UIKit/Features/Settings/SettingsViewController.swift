import UIKit

final class SettingsViewController: UITableViewController {

    private enum Row: Int, CaseIterable {
        case provider, model, baseURL, apiKey, systemPrompt, testConnection
    }

    private let viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "完成", style: .done, target: self, action: #selector(handleDone))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "setting")
        tableView.accessibilityIdentifier = "settings.tableView"
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator

        switch Row(rawValue: indexPath.row)! {
        case .provider:
            configuration.text = "服务商"
            configuration.secondaryText = viewModel.provider.displayName
        case .model:
            configuration.text = "模型"
            configuration.secondaryText = viewModel.model
        case .baseURL:
            configuration.text = "接口地址"
            configuration.secondaryText = viewModel.baseURLText
        case .apiKey:
            configuration.text = "API Key"
            configuration.secondaryText = viewModel.maskedAPIKey
        case .systemPrompt:
            configuration.text = "系统提示词"
            configuration.secondaryText = viewModel.systemPrompt
        case .testConnection:
            configuration.text = "测试连接"
            cell.accessoryType = .none
        }
        cell.contentConfiguration = configuration
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Row(rawValue: indexPath.row)! {
        case .provider:      presentProviderPicker()
        case .model:         presentModelPicker()
        case .baseURL:       presentTextInput(title: "接口地址", value: viewModel.baseURLText) {
                                 self.viewModel.baseURLText = $0 }
        case .apiKey:        presentTextInput(title: "API Key", value: "", isSecure: true) {
                                 self.viewModel.apiKey = $0 }
        case .systemPrompt:  presentTextInput(title: "系统提示词", value: viewModel.systemPrompt) {
                                 self.viewModel.systemPrompt = $0 }
        case .testConnection: runConnectionTest()
        }
    }

    // MARK: - 交互

    private func presentProviderPicker() {
        let sheet = UIAlertController(title: "选择服务商", message: nil, preferredStyle: .actionSheet)
        for kind in ProviderKind.allCases {
            sheet.addAction(UIAlertAction(title: kind.displayName, style: .default) { _ in
                self.viewModel.provider = kind
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentModelPicker() {
        let sheet = UIAlertController(title: "选择模型", message: nil, preferredStyle: .actionSheet)
        for model in viewModel.availableModels {
            sheet.addAction(UIAlertAction(title: model, style: .default) { _ in
                self.viewModel.model = model
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func presentTextInput(title: String, value: String,
                                  isSecure: Bool = false,
                                  onDone: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.text = value
            $0.isSecureTextEntry = isSecure
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            onDone(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func runConnectionTest() {
        viewModel.save()
        let progress = UIAlertController(title: "正在测试…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)

        Task {
            let result = await viewModel.testConnection()
            progress.dismiss(animated: true) {
                let message: String
                switch result {
                case .success:            message = "连接成功"
                case .failure(let error): message = error.userMessage
                }
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    @objc private func handleDone() {
        viewModel.save()
        dismiss(animated: true)
    }
}

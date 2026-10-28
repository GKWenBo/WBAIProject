import UIKit

/// 设置页：每行点开弹窗/选单修改一项，"完成"时统一保存。
final class SettingsViewController: UITableViewController {

    /// 行顺序即 rawValue
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
        case .apiKey:        presentAPIKeyInput()
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

    /// 通用单行文本输入弹窗
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

    /// API Key 出于安全考虑不明文回显，输入框初值必须留空。
    /// 但这也意味着「什么都不输入直接确定」不能等同于「清空」，
    /// 否则用户误触一下就会把已保存的真实 Key 静默删掉。
    /// 空输入按「不修改」处理；清空走单独的「清除 Key」按钮，做成有意为之的操作。
    private func presentAPIKeyInput() {
        let alert = UIAlertController(title: "API Key",
                                      message: "留空点击确定表示不修改现有 Key",
                                      preferredStyle: .alert)
        alert.addTextField {
            $0.text = ""
            $0.isSecureTextEntry = true
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除 Key", style: .destructive) { _ in
            self.viewModel.clearAPIKey()
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            self.viewModel.updateAPIKeyIfProvided(alert.textFields?.first?.text ?? "")
        })
        present(alert, animated: true)
    }

    private func runConnectionTest() {
        // 有意先 save() 再测：这是「边填边存」的取舍——测试即视为用户认可当前填写内容，
        // 顺带把 provider/model/baseURL/apiKey 落盘，不必等用户再点一次「完成」。
        viewModel.save()
        let progress = UIAlertController(title: "正在测试…", message: nil, preferredStyle: .alert)
        // present 的转场动画完成前不能起 Task：如果 testConnection() 走的是几乎不挂起的
        // 快速失败路径（Key 为空 / URL 非法），dismiss 可能抢在 present 动画跑完前调用，
        // 触发 UIKit 「正在 present/dismiss 时又 present/dismiss」的警告，
        // 某些系统版本上这次过早的 dismiss 会被直接丢弃，导致「正在测试…」弹窗卡死不消失。
        // 把 Task 挪到 present 的 completion 里，保证严格串行。
        present(progress, animated: true) {
            Task {
                let result = await self.viewModel.testConnection()
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
    }

    /// 保存并关闭；地址非法时留在本页提示
    @objc private func handleDone() {
        guard viewModel.save() else {
            presentInvalidBaseURLAlert()
            return
        }
        dismiss(animated: true)
    }

    private func presentInvalidBaseURLAlert() {
        let alert = UIAlertController(title: nil,
                                      message: "接口地址格式不正确，请检查后重试",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

import AppKit

private final class FlippedModelStack: NSStackView {
    override var isFlipped: Bool { true }
}

final class ProviderFormController: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 330))
    let nameField = NSTextField()
    let baseURLField = NSTextField()
    let apiKeyField = NSSecureTextField()
    let manualModelsField = NSTextField()

    private let agentID: String
    private let fetchButton = NSButton(title: "获取模型", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "填写 Base URL 和 SK 后获取当前可用模型")
    private let modelStack = FlippedModelStack()
    private let scrollView = NSScrollView()
    private var modelButtons: [NSButton] = []

    init(agentID: String, profile: ProviderProfile? = nil, apiKey: String? = nil) {
        self.agentID = agentID
        super.init()
        buildUI()
        if let profile {
            nameField.stringValue = profile.name
            baseURLField.stringValue = profile.baseURL
            apiKeyField.stringValue = apiKey ?? ""
            show(models: profile.models)
            statusLabel.stringValue = "当前已选择 \(profile.models.count) 个模型，可重新获取"
        }
    }

    var selectedModels: [String] {
        let selected = modelButtons.compactMap { button -> String? in
            guard button.state == .on else { return nil }
            return button.title
        }
        let manual = manualModelsField.stringValue
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (selected + manual).filter { seen.insert($0).inserted }
    }

    private func buildUI() {
        nameField.placeholderString = "Provider 名称"
        baseURLField.placeholderString = "https://api.example.com/v1"
        apiKeyField.placeholderString = "sk-…"
        manualModelsField.placeholderString = "接口不可用时手动输入，多个用逗号分隔"

        let fields = [nameField, baseURLField, apiKeyField, manualModelsField]
        fields.forEach { $0.heightAnchor.constraint(equalToConstant: 25).isActive = true }
        let labels = ["名称", "Base URL", "SK", "手动模型"]
        let grid = NSGridView(views: zip(labels, fields).map {
            [NSTextField(labelWithString: $0.0), $0.1]
        })
        grid.rowSpacing = 7
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)

        fetchButton.target = self
        fetchButton.action = #selector(fetchModels)
        fetchButton.bezelStyle = .rounded
        fetchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fetchButton)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        modelStack.orientation = .vertical
        modelStack.alignment = .leading
        modelStack.spacing = 2
        modelStack.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        modelStack.frame = NSRect(x: 0, y: 0, width: 410, height: 34)

        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.documentView = modelStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            fetchButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            fetchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: fetchButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: fetchButton.leadingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: fetchButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func fetchModels() {
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: baseURL), url.scheme != nil else {
            statusLabel.stringValue = "请输入有效的 Base URL"
            statusLabel.textColor = .systemRed
            return
        }
        fetchButton.isEnabled = false
        fetchButton.title = "获取中…"
        statusLabel.stringValue = "正在请求 \(modelsEndpointDescription(baseURL))"
        statusLabel.textColor = .secondaryLabelColor

        ProviderStore.shared.fetchModels(baseURL: baseURL, apiKey: apiKeyField.stringValue, agentID: agentID) {
            [weak self] result in
            guard let self else { return }
            self.fetchButton.isEnabled = true
            self.fetchButton.title = "重新获取"
            switch result {
            case .success(let models):
                self.show(models: models)
                self.statusLabel.stringValue = "已获取 \(models.count) 个模型，取消勾选可排除"
                self.statusLabel.textColor = .secondaryLabelColor
            case .failure(let error):
                self.show(models: [])
                self.statusLabel.stringValue = "获取失败：\(error.localizedDescription)"
                self.statusLabel.textColor = .systemRed
            }
        }
    }

    private func show(models: [String]) {
        modelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        modelButtons.removeAll()
        if models.isEmpty {
            let empty = NSTextField(labelWithString: "没有获取到模型，可使用上方手动输入")
            empty.font = .systemFont(ofSize: 11)
            empty.textColor = .secondaryLabelColor
            modelStack.addArrangedSubview(empty)
        } else {
            for model in models {
                let button = NSButton(checkboxWithTitle: model, target: nil, action: nil)
                button.state = .on
                button.font = .systemFont(ofSize: 12)
                modelButtons.append(button)
                modelStack.addArrangedSubview(button)
            }
        }
        let height = max(CGFloat(34), CGFloat(modelStack.arrangedSubviews.count * 24 + 10))
        modelStack.frame = NSRect(x: 0, y: 0, width: max(410, scrollView.contentSize.width), height: height)
        modelStack.needsLayout = true
    }

    private func modelsEndpointDescription(_ baseURL: String) -> String {
        baseURL.hasSuffix("/models") ? baseURL : baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
    }
}

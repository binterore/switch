import AppKit

extension Notification.Name {
    static let bbDidSwitchModel = Notification.Name("bbDidSwitchModel")
}

enum ToggleID: String {
    case autoBackup = "BBSwitchAutoBackup"
    case showOnLaunch = "BBSwitchShowOnLaunch"

    var title: String {
        switch self {
        case .autoBackup: return "自动备份配置"
        case .showOnLaunch: return "启动时显示面板"
        }
    }
}

private final class FlippedMenuStack: NSStackView {
    override var isFlipped: Bool { true }
}

private final class ModelMenuRow: NSControl {
    private let checkView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private let handler: () -> Void

    init(model: String, selected: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: NSRect(x: 0, y: 0, width: 292, height: 27))
        wantsLayer = true
        layer?.cornerRadius = 5

        checkView.image = selected ? NSImage(systemSymbolName: "checkmark", accessibilityDescription: "当前模型") : nil
        checkView.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        checkView.contentTintColor = .labelColor

        titleField.stringValue = model
        titleField.font = .menuFont(ofSize: 0)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.toolTip = model

        [checkView, titleField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            checkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 14),
            checkView.heightAnchor.constraint(equalToConstant: 14),
            titleField.leadingAnchor.constraint(equalTo: checkView.trailingAnchor, constant: 7),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(model)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }
    override func mouseDown(with event: NSEvent) { setHighlighted(true) }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        handler()
    }

    private func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = highlighted ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let color: NSColor = highlighted ? .white : .labelColor
        checkView.contentTintColor = color
        titleField.textColor = color
    }
}

private final class ScrollableModelMenuView: NSView {
    private let scrollView = NSScrollView()
    private let stack = FlippedMenuStack()

    init(models: [String], selectedModel: String?, onSelect: @escaping (String) -> Void) {
        let visibleRows = min(models.count, 12)
        super.init(frame: NSRect(x: 0, y: 0, width: 308, height: CGFloat(visibleRows * 27 + 8)))

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.frame = NSRect(x: 0, y: 0, width: 308, height: CGFloat(models.count * 27 + 8))

        var selectedRow: ModelMenuRow?
        for model in models {
            let row = ModelMenuRow(model: model, selected: model == selectedModel) { onSelect(model) }
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 296).isActive = true
            row.heightAnchor.constraint(equalToConstant: 27).isActive = true
            stack.addArrangedSubview(row)
            if model == selectedModel { selectedRow = row }
        }

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = stack
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        if let selectedRow {
            DispatchQueue.main.async { [weak self, weak selectedRow] in
                guard let self, let selectedRow else { return }
                self.stack.layoutSubtreeIfNeeded()
                self.scrollView.contentView.scrollToVisible(selectedRow.frame)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class AgentDisclosureMenuView: NSControl {
    static let menuContentWidth: CGFloat = 360
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let disclosureView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    var onToggle: (() -> Void)?

    init(title: String, symbol: String, expanded: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.menuContentWidth, height: 24))
        wantsLayer = true
        layer?.cornerRadius = 5
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        iconView.contentTintColor = .labelColor
        titleField.stringValue = title
        titleField.font = .menuFont(ofSize: 0)
        titleField.textColor = .labelColor
        setExpanded(expanded)
        [iconView, titleField, disclosureView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: disclosureView.leadingAnchor, constant: -10),
            disclosureView.trailingAnchor.constraint(equalTo: trailingAnchor),
            disclosureView.centerYAnchor.constraint(equalTo: centerYAnchor),
            disclosureView.widthAnchor.constraint(equalToConstant: 10),
            disclosureView.heightAnchor.constraint(equalToConstant: 12),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setExpanded(_ expanded: Bool) {
        disclosureView.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                       accessibilityDescription: expanded ? "已展开" : "已收起")
        disclosureView.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        disclosureView.contentTintColor = .secondaryLabelColor
        setAccessibilityValue(expanded ? "已展开" : "已收起")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) { setHighlighted(true) }
    override func mouseExited(with event: NSEvent) { setHighlighted(false) }
    override func mouseDown(with event: NSEvent) { setHighlighted(true) }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        setHighlighted(false)
        DispatchQueue.main.async { [weak self] in self?.onToggle?() }
    }

    private func setHighlighted(_ highlighted: Bool) {
        layer?.backgroundColor = highlighted ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        let color: NSColor = highlighted ? .white : .labelColor
        iconView.contentTintColor = color
        titleField.textColor = color
        disclosureView.contentTintColor = highlighted ? .white : .secondaryLabelColor
    }
}

final class NativeMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let store = ConfigStore.shared
    private let defaults = UserDefaults.standard
    private var expandedAgentIDs: Set<String> = []
    private var didChooseInitialAgent = false
    private var agentViews: [String: AgentDisclosureMenuView] = [:]
    private var agentItems: [String: NSMenuItem] = [:]
    private var agentChildren: [String: [NSMenuItem]] = [:]

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    private func rebuild() {
        store.refresh()
        menu.removeAllItems()
        agentViews.removeAll()
        agentItems.removeAll()
        agentChildren.removeAll()

        let header = NSMenuItem(title: "BB Switch", action: nil, keyEquivalent: "")
        header.image = symbol("arrow.left.arrow.right")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !didChooseInitialAgent {
            if let first = store.agents.first?.id { expandedAgentIDs.insert(first) }
            didChooseInitialAgent = true
        }
        for (index, agent) in store.agents.enumerated() {
            let expanded = expandedAgentIDs.contains(agent.id)
            let item = NSMenuItem()
            let row = AgentDisclosureMenuView(title: agent.name, symbol: agent.symbol, expanded: expanded)
            row.onToggle = { [weak self] in self?.toggleAgent(agent.id) }
            item.view = row
            agentViews[agent.id] = row
            agentItems[agent.id] = item
            menu.addItem(item)
            let children = makeProviderItems(for: agent, index: index)
            if expanded { children.forEach(menu.addItem) }
            agentChildren[agent.id] = children
        }

        menu.addItem(.separator())
        addToggle(.autoBackup)
        addToggle(.showOnLaunch)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新配置", action: #selector(refreshPressed), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command]
        refresh.image = symbol("arrow.clockwise")
        refresh.target = self
        menu.addItem(refresh)

        let open = NSMenuItem(title: "打开配置", action: nil, keyEquivalent: "")
        open.image = symbol("folder")
        open.submenu = makeConfigMenu()
        menu.addItem(open)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 BB Switch", action: #selector(quitPressed), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    private func makeProviderItems(for agent: Agent, index: Int) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let profiles = ProviderStore.shared.profiles(for: agent.id)
        let currentProvider = defaults.string(forKey: "BBSwitchActiveProvider.\(agent.id)") ?? profiles.first?.id ?? "default"

        for profile in profiles {
            let providerItem = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
            providerItem.image = symbol("server.rack")
            providerItem.indentationLevel = 2
            providerItem.state = profile.id == currentProvider ? .on : .off
            providerItem.submenu = makeModelMenu(agentIndex: index, agent: agent, provider: profile.id,
                                                  models: profile.models, profile: profile)
            items.append(providerItem)
        }

        if profiles.isEmpty {
            let empty = NSMenuItem(title: "尚未添加 Provider", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.indentationLevel = 2
            items.append(empty)
        }

        let add = NSMenuItem(title: "添加 Provider…", action: #selector(addProviderPressed(_:)), keyEquivalent: "")
        add.image = symbol("plus")
        add.indentationLevel = 2
        add.target = self
        add.representedObject = agent.id
        items.append(add)
        return items
    }

    private func makeModelMenu(agentIndex: Int, agent: Agent, provider: String,
                               models: [String], profile: ProviderProfile?) -> NSMenu {
        let submenu = NSMenu(title: provider)
        submenu.autoenablesItems = false
        if models.count > 12 {
            let selected = models.first { model in
                let full = profile == nil ? model : provider + "/" + model
                return agent.current == full || (agent.id != "opencode" && profile != nil && agent.current == model)
            }
            let listItem = NSMenuItem()
            listItem.view = ScrollableModelMenuView(models: models.map { displayModel($0, provider: provider) },
                                                    selectedModel: selected.map { displayModel($0, provider: provider) }) {
                [weak self, weak submenu] display in
                guard let self else { return }
                let model = models.first { self.displayModel($0, provider: provider) == display } ?? display
                submenu?.cancelTracking()
                self.switchModel(agentIndex: agentIndex, model: model, profile: profile)
            }
            submenu.addItem(listItem)
        } else {
            for model in models {
                let display = displayModel(model, provider: provider)
                let item = NSMenuItem(title: display, action: #selector(modelPressed(_:)), keyEquivalent: "")
                item.target = self
                let full = profile == nil ? model : provider + "/" + model
                item.state = agent.current == full || (agent.id != "opencode" && profile != nil && agent.current == model) ? .on : .off
                item.representedObject = ["agent": agentIndex, "model": model, "profile": profile as Any]
                submenu.addItem(item)
            }
        }
        if let profile {
            submenu.addItem(.separator())
            let edit = NSMenuItem(title: "编辑 Provider…", action: #selector(editProviderPressed(_:)), keyEquivalent: "")
            edit.image = symbol("pencil")
            edit.target = self
            edit.representedObject = profile
            submenu.addItem(edit)

            let remove = NSMenuItem(title: "删除 Provider…", action: #selector(deleteProviderPressed(_:)), keyEquivalent: "")
            remove.image = symbol("trash")
            remove.target = self
            remove.representedObject = profile
            submenu.addItem(remove)
        }
        return submenu
    }

    private func addToggle(_ id: ToggleID) {
        let item = NSMenuItem(title: id.title, action: #selector(togglePressed(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = id.rawValue
        item.state = toggleState(id) ? .on : .off
        menu.addItem(item)
    }

    private func makeConfigMenu() -> NSMenu {
        let submenu = NSMenu()
        for agent in store.agents {
            guard let path = agent.configPath else { continue }
            let item = NSMenuItem(title: agent.name, action: #selector(openConfigPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func modelPressed(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: Any],
              let index = data["agent"] as? Int,
              let model = data["model"] as? String else { return }
        switchModel(agentIndex: index, model: model, profile: data["profile"] as? ProviderProfile)
    }

    private func switchModel(agentIndex index: Int, model: String, profile: ProviderProfile?) {
        do {
            let result: SwitchResult
            if let profile {
                result = try store.switchProviderModel(profile, model: model)
            } else {
                result = try store.switchModel(agentID: store.agents[index].id, to: model)
            }
            NotificationCenter.default.post(name: .bbDidSwitchModel, object: nil,
                                            userInfo: ["model": result.model, "agentID": result.agentID])
        } catch { showError("切换失败", error: error) }
    }

    private func toggleAgent(_ agentID: String) {
        guard let agentItem = agentItems[agentID], let children = agentChildren[agentID] else { return }
        if expandedAgentIDs.contains(agentID) {
            collapseAgent(agentID)
        } else {
            for otherID in Array(expandedAgentIDs) where otherID != agentID {
                collapseAgent(otherID)
            }
            expandedAgentIDs.insert(agentID)
            var insertionIndex = menu.index(of: agentItem) + 1
            for child in children {
                menu.insertItem(child, at: insertionIndex)
                insertionIndex += 1
            }
            agentViews[agentID]?.setExpanded(true)
        }
        menu.update()
    }

    private func collapseAgent(_ agentID: String) {
        expandedAgentIDs.remove(agentID)
        agentChildren[agentID]?.forEach { child in
            if menu.items.contains(where: { $0 === child }) { menu.removeItem(child) }
        }
        agentViews[agentID]?.setExpanded(false)
    }

    @objc private func addProviderPressed(_ sender: NSMenuItem) {
        guard let agentID = sender.representedObject as? String,
              let agent = store.agent(id: agentID) else { return }
        let alert = NSAlert()
        alert.messageText = "为 \(agent.name) 添加 Provider"
        alert.informativeText = "通过 /models 获取当前可用模型；SK 保存在 macOS 钥匙串。"
        let form = ProviderFormController(agentID: agentID)
        alert.accessoryView = form.view
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = form.nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = form.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = form.baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = form.selectedModels
        guard !name.isEmpty, URL(string: baseURL)?.scheme != nil, !list.isEmpty else {
            let error = NSAlert(); error.messageText = "信息不完整"; error.informativeText = "请填写名称、有效 Base URL，并获取或手动输入至少一个模型。"; error.runModal(); return
        }
        ProviderStore.shared.add(agentID: agentID, name: name, baseURL: baseURL,
                                 apiKey: form.apiKeyField.stringValue, models: list)
    }

    @objc private func editProviderPressed(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? ProviderProfile,
              let agent = store.agent(id: profile.agentID) else { return }
        let alert = NSAlert()
        alert.messageText = "编辑 \(agent.name) Provider"
        alert.informativeText = "可修改连接信息，并通过 /models 更新可选择模型。"
        let form = ProviderFormController(agentID: profile.agentID, profile: profile,
                                          apiKey: ProviderStore.shared.apiKey(for: profile))
        alert.accessoryView = form.view
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = form.nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = form.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = form.baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = form.selectedModels
        guard !name.isEmpty, URL(string: baseURL)?.scheme != nil, !models.isEmpty else {
            let error = NSAlert()
            error.messageText = "信息不完整"
            error.informativeText = "请填写名称、有效 Base URL，并保留至少一个模型。"
            error.runModal()
            return
        }
        ProviderStore.shared.update(profile, name: name, baseURL: baseURL,
                                    apiKey: form.apiKeyField.stringValue, models: models)
    }

    @objc private func deleteProviderPressed(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? ProviderProfile else { return }
        let alert = NSAlert()
        alert.messageText = "删除 Provider“\(profile.name)”？"
        alert.informativeText = "Provider 配置与钥匙串中的 SK 都会删除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { ProviderStore.shared.remove(profile) }
    }

    @objc private func togglePressed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = ToggleID(rawValue: raw) else { return }
        defaults.set(!toggleState(id), forKey: id.rawValue)
    }

    @objc private func refreshPressed() { store.refresh() }
    @objc private func quitPressed() { NSApp.terminate(nil) }
    @objc private func openConfigPressed(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func toggleState(_ id: ToggleID) -> Bool {
        switch id {
        case .autoBackup: return defaults.object(forKey: id.rawValue) as? Bool ?? true
        case .showOnLaunch: return defaults.bool(forKey: id.rawValue)
        }
    }

    private func displayModel(_ model: String, provider: String) -> String {
        let prefix = provider + "/"
        return model.hasPrefix(prefix) ? String(model.dropFirst(prefix.count)) : model
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func showError(_ title: String, error: Error) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = error.localizedDescription; alert.alertStyle = .warning; alert.runModal()
    }
}

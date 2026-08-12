import AppKit

// MARK: - CLI self-check (make probe)

func probe() {
    let store = ConfigStore.shared
    var out: [[String: Any]] = []
    for a in store.agents {
        out.append([
            "id": a.id,
            "name": a.name,
            "current": a.current,
            "models": a.models,
            "config": a.configPath ?? "",
            "error": a.error ?? "",
        ])
    }
    if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menuController = NativeMenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ProviderStore.shared
        configureStatusItem()
        statusItem.menu = menuController.menu
        NotificationCenter.default.addObserver(self, selector: #selector(modelSwitched(_:)),
                                               name: .bbDidSwitchModel, object: nil)
        updateTitle(model: ConfigStore.shared.agent(id: "claude")?.current ?? "", agentID: "claude")
        let shouldShowOnLaunch = UserDefaults.standard.bool(forKey: "BBSwitchShowOnLaunch")
        if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--show-provider") || shouldShowOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.statusItem.button?.performClick(nil)
                if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--show-provider") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
                }
            }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let img = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "BB Switch")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    }

    @objc private func modelSwitched(_ note: Notification) {
        let agentID = note.userInfo?["agentID"] as? String ?? "claude"
        let model = note.userInfo?["model"] as? String ?? ""
        updateTitle(model: model, agentID: agentID)
    }

    private func updateTitle(model: String, agentID: String) {
        guard let button = statusItem.button else { return }
        let short = model.components(separatedBy: "/").last ?? model
        if short.isEmpty {
            button.title = ""
        } else {
            button.title = " " + short
        }
        let agentName = ConfigStore.shared.agent(id: agentID)?.name ?? agentID
        button.toolTip = "\(agentName) · \(model)"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Entry

if CommandLine.arguments.contains("--probe") {
    probe()
    exit(0)
}

setbuf(stdout, nil)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import Foundation

// MARK: - Data model

struct Agent {
    let id: String
    let name: String
    let symbol: String
    let configPath: String?
    var current: String
    var models: [String]
    var error: String?
}

struct SwitchResult {
    let agentID: String
    let model: String
    let backupPath: String?
}

enum ConfigError: LocalizedError {
    case missingFile(String)
    case invalidJSON(String)
    case invalidTOML(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let p): return "配置文件不存在：\(p)"
        case .invalidJSON(let p): return "配置文件不是有效 JSON：\(p)"
        case .invalidTOML(let p): return "配置文件无法解析：\(p)"
        case .writeFailed(let p): return "写入失败：\(p)"
        }
    }
}

// MARK: - Store

final class ConfigStore {

    static let shared = ConfigStore()

    private let fm = FileManager.default
    private let home: URL

    private var _agents: [Agent] = []
    var agents: [Agent] { _agents }

    init(baseURL: URL? = nil) {
        home = baseURL ?? fm.homeDirectoryForCurrentUser
        refresh()
    }

    // MARK: Paths

    private func claudeSettingsURL() -> URL { home.appendingPathComponent(".claude/settings.json") }
    private func codexConfigURL() -> URL { home.appendingPathComponent(".codex/config.toml") }
    private func opencodeConfigURL() -> URL { home.appendingPathComponent(".config/opencode/opencode.json") }

    // MARK: Refresh

    func refresh() {
        var list: [Agent] = []
        list.append(readClaude())
        list.append(readCodex())
        list.append(readOpenCode())
        _agents = list
    }

    func agent(id: String) -> Agent? { _agents.first { $0.id == id } }

    private func readClaude() -> Agent {
        let url = claudeSettingsURL()
        var current = ""
        var models: [String] = []
        var errMsg: String? = nil
        if fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConfigError.invalidJSON(url.path)
                }
                if let env = obj["env"] as? [String: Any] {
                    current = env["ANTHROPIC_MODEL"] as? String ?? ""
                }
                if let list = obj["availableModels"] as? [String] {
                    models = list
                }
            } catch {
                errMsg = error.localizedDescription
            }
        } else {
            errMsg = "未找到 \(url.path)"
        }
        if current.isEmpty {
            current = models.first ?? ""
        }
        return Agent(id: "claude", name: "Claude Code", symbol: "hammer.fill",
                     configPath: url.path, current: current, models: models,
                     error: errMsg)
    }

    private func readCodex() -> Agent {
        let url = codexConfigURL()
        var current = ""
        var errMsg: String? = nil
        if fm.fileExists(atPath: url.path) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                guard let match = topLevelModel(in: text) else {
                    throw ConfigError.invalidTOML(url.path)
                }
                current = match
            } catch {
                errMsg = error.localizedDescription
            }
        } else {
            errMsg = "未找到 \(url.path)"
        }
        let defaults = [
            "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.2",
            "deepseek-v4-flash", "deepseek-v4-pro", "o3", "o4-mini",
        ]
        var models = defaults
        if !current.isEmpty && !models.contains(current) { models.insert(current, at: 0) }
        return Agent(id: "codex", name: "Codex", symbol: "chevron.left.forwardslash.chevron.right",
                     configPath: url.path, current: current, models: models,
                     error: errMsg)
    }

    private func readOpenCode() -> Agent {
        let url = opencodeConfigURL()
        var current = ""
        var models: [String] = []
        var errMsg: String? = nil
        if fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw ConfigError.invalidJSON(url.path)
                }
                current = obj["model"] as? String ?? ""
                if let providers = obj["provider"] as? [String: Any] {
                    for (providerID, pv) in providers {
                        if let p = pv as? [String: Any], let ms = p["models"] as? [String: Any] {
                            models.append(contentsOf: ms.keys.map { modelID in
                                modelID.hasPrefix(providerID + "/") ? modelID : providerID + "/" + modelID
                            })
                        }
                    }
                }
                models.sort()
                if !current.isEmpty && !models.contains(current) { models.insert(current, at: 0) }
            } catch {
                errMsg = error.localizedDescription
            }
        } else {
            errMsg = "未找到 \(url.path)"
        }
        return Agent(id: "opencode", name: "OpenCode", symbol: "terminal.fill",
                     configPath: url.path, current: current, models: models,
                     error: errMsg)
    }

    /// Finds the top-level `model = "..."` in a TOML file (line must start at column 0).
    private func topLevelModel(in text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("[") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "model" else { continue }
            var v = parts[1]
            if v.hasPrefix("\"") || v.hasPrefix("'") {
                let q = v.removeFirst()
                if let end = v.firstIndex(of: q) { return String(v[..<end]) }
            }
            return v
        }
        return nil
    }

    // MARK: Switch

    @discardableResult
    func switchModel(agentID: String, to model: String) throws -> SwitchResult {
        let backup: String?
        switch agentID {
        case "claude": backup = try writeClaude(model: model)
        case "codex": backup = try writeCodex(model: model)
        case "opencode": backup = try writeOpenCode(model: model)
        default: throw ConfigError.missingFile("未知 agent")
        }
        refresh()
        return SwitchResult(agentID: agentID, model: model, backupPath: backup)
    }

    @discardableResult
    func switchProviderModel(_ profile: ProviderProfile, model: String) throws -> SwitchResult {
        let backup: String?
        let resultModel: String
        switch profile.agentID {
        case "claude":
            backup = try writeClaudeProvider(profile, model: model)
            resultModel = model
        case "codex":
            backup = try writeCodexProvider(profile, model: model)
            resultModel = model
        case "opencode":
            backup = try writeOpenCodeProvider(profile, model: model)
            resultModel = profile.id + "/" + model
        default:
            throw ConfigError.missingFile("未知 agent")
        }
        UserDefaults.standard.set(profile.id, forKey: "BBSwitchActiveProvider.\(profile.agentID)")
        refresh()
        return SwitchResult(agentID: profile.agentID, model: resultModel, backupPath: backup)
    }

    private func backupIfExists(_ url: URL) throws -> String? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let autoBackup = UserDefaults.standard.object(forKey: "BBSwitchAutoBackup") as? Bool ?? true
        guard autoBackup else { return nil }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let bak = url.deletingPathExtension().path + "." + url.pathExtension + ".bak." + ts
        try fm.copyItem(at: url, to: URL(fileURLWithPath: bak))
        return bak
    }

    private func writeClaude(model: String) throws -> String? {
        let url = claudeSettingsURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        var obj: [String: Any]
        do {
            let data = try Data(contentsOf: url)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError.invalidJSON(url.path)
            }
            obj = o
        } catch let e as ConfigError { throw e }
        var env = obj["env"] as? [String: Any] ?? [:]
        for key in ["ANTHROPIC_MODEL",
                    "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
                    "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] {
            env[key] = model
        }
        obj["env"] = env
        var avail = obj["availableModels"] as? [String] ?? []
        if !avail.contains(model) { avail.insert(model, at: 0) }
        obj["availableModels"] = avail

        let backup = try backupIfExists(url)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return backup
    }

    private func writeCodex(model: String) throws -> String? {
        let url = codexConfigURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        var text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch { throw ConfigError.invalidTOML(url.path) }
        guard topLevelModel(in: text) != nil else { throw ConfigError.invalidTOML(url.path) }

        var lines = text.components(separatedBy: "\n")
        var replaced = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("[") else { continue }
            let parts = lines[i].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "model" else { continue }
            let indent = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
            lines[i] = indent + "model = \"" + model + "\""
            replaced = true
            break
        }
        guard replaced else { throw ConfigError.invalidTOML(url.path) }

        let backup = try backupIfExists(url)
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch { throw ConfigError.writeFailed(url.path) }
        return backup
    }

    private func writeOpenCode(model: String) throws -> String? {
        let url = opencodeConfigURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        var obj: [String: Any]
        do {
            let data = try Data(contentsOf: url)
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError.invalidJSON(url.path)
            }
            obj = o
        } catch let e as ConfigError { throw e }
        obj["model"] = model
        let backup = try backupIfExists(url)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return backup
    }

    private func writeClaudeProvider(_ profile: ProviderProfile, model: String) throws -> String? {
        let url = claudeSettingsURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        let data = try Data(contentsOf: url)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidJSON(url.path)
        }
        var env = obj["env"] as? [String: Any] ?? [:]
        env["ANTHROPIC_BASE_URL"] = profile.baseURL
        if let key = ProviderStore.shared.apiKey(for: profile), !key.isEmpty {
            env["ANTHROPIC_API_KEY"] = key
        }
        for key in ["ANTHROPIC_MODEL",
                    "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
                    "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME"] {
            env[key] = model
        }
        obj["env"] = env
        var available = obj["availableModels"] as? [String] ?? []
        if !available.contains(model) { available.insert(model, at: 0) }
        obj["availableModels"] = available
        let backup = try backupIfExists(url)
        let output = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url, options: .atomic)
        return backup
    }

    private func writeOpenCodeProvider(_ profile: ProviderProfile, model: String) throws -> String? {
        let url = opencodeConfigURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        let data = try Data(contentsOf: url)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidJSON(url.path)
        }
        var providers = obj["provider"] as? [String: Any] ?? [:]
        var models: [String: Any] = [:]
        for modelID in profile.models { models[modelID] = [String: Any]() }
        var options: [String: Any] = ["baseURL": profile.baseURL]
        if let key = ProviderStore.shared.apiKey(for: profile), !key.isEmpty { options["apiKey"] = key }
        providers[profile.id] = [
            "name": profile.name,
            "npm": "@ai-sdk/openai-compatible",
            "api": "openai-chat-completions",
            "options": options,
            "models": models,
        ]
        obj["provider"] = providers
        obj["model"] = profile.id + "/" + model
        let backup = try backupIfExists(url)
        let output = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: url, options: .atomic)
        return backup
    }

    private func writeCodexProvider(_ profile: ProviderProfile, model: String) throws -> String? {
        let url = codexConfigURL()
        guard fm.fileExists(atPath: url.path) else { throw ConfigError.missingFile(url.path) }
        var text = try String(contentsOf: url, encoding: .utf8)
        text = replacingOrInsertingTopLevel(key: "model", value: "\"\(tomlEscape(model))\"", in: text)
        text = replacingOrInsertingTopLevel(key: "model_provider", value: "\"\(tomlEscape(profile.id))\"", in: text)
        text = removingTOMLSections(prefix: "model_providers.\(profile.id)", from: text)

        if profile.id == "openai" {
            let backup = try backupIfExists(url)
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { throw ConfigError.writeFailed(url.path) }
            return backup
        }

        let section = """

[model_providers.\(profile.id)]
name = "\(tomlEscape(profile.name))"
base_url = "\(tomlEscape(profile.baseURL))"
wire_api = "responses"

[model_providers.\(profile.id).auth]
command = "/usr/bin/security"
args = ["find-generic-password", "-s", "\(ProviderStore.keychainService)", "-a", "\(tomlEscape(ProviderStore.keychainAccount(for: profile)))", "-w"]
"""
        text = text.trimmingCharacters(in: .whitespacesAndNewlines) + section + "\n"
        let backup = try backupIfExists(url)
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ConfigError.writeFailed(url.path) }
        return backup
    }

    private func replacingOrInsertingTopLevel(key: String, value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        for i in lines.indices {
            if lines[i].hasPrefix("[") { break }
            let parts = lines[i].split(separator: "=", maxSplits: 1)
            if parts.first?.trimmingCharacters(in: .whitespaces) == key {
                lines[i] = "\(key) = \(value)"
                return lines.joined(separator: "\n")
            }
        }
        let firstSection = lines.firstIndex { $0.hasPrefix("[") } ?? lines.endIndex
        lines.insert("\(key) = \(value)", at: firstSection)
        return lines.joined(separator: "\n")
    }

    private func removingTOMLSections(prefix: String, from text: String) -> String {
        var result: [String] = []
        var skipping = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("[") {
                let section = line.dropFirst().split(separator: "]", maxSplits: 1).first.map(String.init) ?? ""
                skipping = section == prefix || section.hasPrefix(prefix + ".")
            }
            if !skipping { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    private func tomlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

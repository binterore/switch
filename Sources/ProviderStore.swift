import Foundation
import Security

struct ProviderProfile: Codable, Hashable {
    let id: String
    let agentID: String
    var name: String
    var baseURL: String
    var models: [String]
}

enum ModelDiscoveryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noModels

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Base URL 无效"
        case .invalidResponse: return "接口返回格式无法识别"
        case .httpStatus(let status): return "接口返回 HTTP \(status)"
        case .noModels: return "响应中没有模型"
        }
    }
}

final class ProviderStore {
    static let shared = ProviderStore()
    static let keychainService = "com.binterore.bbswitch.provider"
    static func keychainAccount(for profile: ProviderProfile) -> String { "\(profile.agentID):\(profile.id)" }

    private let fm = FileManager.default
    private let home: URL
    private let url: URL
    private(set) var profiles: [ProviderProfile] = []

    init(baseURL: URL? = nil) {
        home = baseURL ?? fm.homeDirectoryForCurrentUser
        url = home.appendingPathComponent("Library/Application Support/BBSwitch/providers.json")
        load()
        bootstrapDefaults()
    }

    func profiles(for agentID: String) -> [ProviderProfile] {
        profiles.filter { $0.agentID == agentID }
    }

    @discardableResult
    func add(agentID: String, name: String, baseURL: String, apiKey: String, models: [String]) -> ProviderProfile {
        let seed = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(seed).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var id = slug.isEmpty ? UUID().uuidString.lowercased() : slug
        var suffix = 2
        while profiles.contains(where: { $0.agentID == agentID && $0.id == id }) {
            id = "\(slug)-\(suffix)"; suffix += 1
        }
        let profile = ProviderProfile(id: id, agentID: agentID, name: name, baseURL: baseURL, models: models)
        profiles.append(profile)
        save()
        setAPIKey(apiKey, account: Self.keychainAccount(for: profile))
        return profile
    }

    @discardableResult
    func update(_ profile: ProviderProfile, name: String, baseURL: String,
                apiKey: String, models: [String]) -> ProviderProfile {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id && $0.agentID == profile.agentID }) else {
            return profile
        }
        let updated = ProviderProfile(id: profile.id, agentID: profile.agentID,
                                      name: name, baseURL: baseURL, models: models)
        profiles[index] = updated
        save()
        setAPIKey(apiKey, account: Self.keychainAccount(for: updated))
        return updated
    }

    func remove(_ profile: ProviderProfile) {
        profiles.removeAll { $0.id == profile.id && $0.agentID == profile.agentID }
        save()
        SecItemDelete(keychainQuery(account: Self.keychainAccount(for: profile)) as CFDictionary)
    }

    func apiKey(for profile: ProviderProfile) -> String? {
        var query = keychainQuery(account: Self.keychainAccount(for: profile))
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func fetchModels(baseURL: String, apiKey: String, agentID: String,
                     completion: @escaping (Result<[String], Error>) -> Void) {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = trimmed.hasSuffix("/models") ? trimmed : trimmed + "/models"
        guard let url = URL(string: endpoint) else {
            completion(.failure(ModelDiscoveryError.invalidURL))
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if agentID == "claude" {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<[String], Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                result = .failure(ModelDiscoveryError.httpStatus(http.statusCode))
            } else if let data, let models = Self.parseModels(data), !models.isEmpty {
                result = .success(models)
            } else {
                result = .failure(ModelDiscoveryError.noModels)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static func parseModels(_ data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var values: [String] = []
        if let dictionary = object as? [String: Any] {
            for key in ["data", "models"] {
                if let rows = dictionary[key] as? [[String: Any]] {
                    values.append(contentsOf: rows.compactMap {
                        $0["id"] as? String ?? $0["name"] as? String ?? $0["model"] as? String
                    })
                } else if let strings = dictionary[key] as? [String] {
                    values.append(contentsOf: strings)
                }
            }
        } else if let rows = object as? [[String: Any]] {
            values.append(contentsOf: rows.compactMap { $0["id"] as? String ?? $0["name"] as? String })
        } else if let strings = object as? [String] {
            values.append(contentsOf: strings)
        }
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func setAPIKey(_ value: String, account: String) {
        let query = keychainQuery(account: account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ProviderProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func save() {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func bootstrapDefaults() {
        if profiles(for: "claude").isEmpty { importClaudeDefault() }
        if profiles(for: "codex").isEmpty {
            importProfile(ProviderProfile(id: "openai", agentID: "codex", name: "OpenAI",
                                          baseURL: "https://api.openai.com/v1",
                                          models: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.2"]), apiKey: "")
        }
        if profiles(for: "opencode").isEmpty { importOpenCodeProviders() }
        save()
    }

    private func importClaudeDefault() {
        let path = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let env = obj["env"] as? [String: Any] ?? [:]
        let baseURL = env["ANTHROPIC_BASE_URL"] as? String ?? "https://api.anthropic.com"
        let apiKey = env["ANTHROPIC_API_KEY"] as? String ?? env["ANTHROPIC_AUTH_TOKEN"] as? String ?? ""
        let models = obj["availableModels"] as? [String] ?? []
        let name = URL(string: baseURL)?.host ?? "默认 Provider"
        importProfile(ProviderProfile(id: "default", agentID: "claude", name: name,
                                      baseURL: baseURL, models: models), apiKey: apiKey)
    }

    private func importOpenCodeProviders() {
        let path = home.appendingPathComponent(".config/opencode/opencode.json")
        guard let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = obj["provider"] as? [String: Any] else { return }
        for (id, value) in providers {
            guard let provider = value as? [String: Any] else { continue }
            let options = provider["options"] as? [String: Any] ?? [:]
            let models = (provider["models"] as? [String: Any])?.keys.sorted() ?? []
            let profile = ProviderProfile(id: id, agentID: "opencode",
                                          name: provider["name"] as? String ?? id,
                                          baseURL: options["baseURL"] as? String ?? "",
                                          models: models)
            importProfile(profile, apiKey: options["apiKey"] as? String ?? "")
        }
    }

    private func importProfile(_ profile: ProviderProfile, apiKey: String) {
        guard !profiles.contains(where: { $0.agentID == profile.agentID && $0.id == profile.id }) else { return }
        profiles.append(profile)
        setAPIKey(apiKey, account: Self.keychainAccount(for: profile))
        let key = "BBSwitchActiveProvider.\(profile.agentID)"
        if UserDefaults.standard.string(forKey: key) == nil { UserDefaults.standard.set(profile.id, forKey: key) }
    }
}

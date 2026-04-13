import Foundation
import Security

/// Persisted SMB server connection configuration.
public struct SMBServerConfig: Codable, Identifiable, Sendable, Hashable {
    public var id: String { "\(host)/\(share)" }
    public var host: String       // e.g. "192.168.1.100" or "nas.local"
    public var port: Int           // default 445
    public var share: String       // e.g. "Photos"
    public var username: String
    public var displayName: String // user-chosen label for sidebar

    public init(host: String, port: Int = 445, share: String, username: String, displayName: String = "") {
        self.host = host
        self.port = port
        self.share = share
        self.username = username
        self.displayName = displayName.isEmpty ? "\(host)/\(share)" : displayName
    }

    /// The smb:// URL for connecting.
    public var serverURL: URL? {
        URL(string: "smb://\(host):\(port)")
    }
}

// MARK: - Persistence

public enum SMBConfigStore {

    private static let defaultsKey = "com.justmaple.coral-maple.smb-servers"

    public static func loadAll() -> [SMBServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let configs = try? JSONDecoder().decode([SMBServerConfig].self, from: data) else {
            return []
        }
        return configs
    }

    public static func save(_ configs: [SMBServerConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    public static func add(_ config: SMBServerConfig) {
        var all = loadAll()
        all.removeAll { $0.id == config.id }
        all.append(config)
        save(all)
    }

    public static func remove(id: String) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        save(all)
        deletePassword(for: id)
    }
}

// MARK: - Keychain for passwords

extension SMBConfigStore {

    private static let service = "com.justmaple.coral-maple.smb"

    public static func savePassword(_ password: String, for configID: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configID,
        ]
        // Delete existing
        SecItemDelete(query as CFDictionary)
        // Add new
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func loadPassword(for configID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deletePassword(for configID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configID,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

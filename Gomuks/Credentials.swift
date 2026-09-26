import Foundation
import Security

struct Credentials {
    var server: URL
    var username: String
    private var enteredPassword: String?

    var password: String {
        enteredPassword ?? Self.loadPassword() ?? ""
    }

    init(server: URL, username: String, password: String? = nil) {
        self.server = server
        self.username = username
        enteredPassword = password
    }

    private static let serverKey = "server_url"
    private static let usernameKey = "username"
    private static let keychainService = "com.balgeriada.gomuks"

    static func load() -> Credentials? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: serverKey),
              let server = parseServer(raw),
              let username = defaults.string(forKey: usernameKey)
        else { return nil }
        return Credentials(server: server, username: username)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(server.absoluteString, forKey: Self.serverKey)
        defaults.set(username, forKey: Self.usernameKey)
        Self.savePassword(password)
    }

    static func parseServer(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    private static var passwordQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "password",
        ]
    }

    private static func loadPassword() -> String? {
        var query = passwordQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func savePassword(_ password: String) {
        SecItemDelete(passwordQuery as CFDictionary)
        var query = passwordQuery
        query[kSecValueData as String] = Data(password.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }
}

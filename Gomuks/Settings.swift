import Foundation
import Security
import SwiftUI

struct SetupView: View {
    @ObservedObject var browser: Browser
    @State private var server: String
    @State private var username: String
    @State private var password: String
    @State private var connecting = false
    @State private var player = VideoPlayer.server?.absoluteString ?? ""

    init(browser: Browser) {
        self.browser = browser
        let credentials = browser.credentials
        server = credentials?.server.absoluteString ?? ""
        username = credentials?.username ?? ""
        password = credentials?.password ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://gomuks.example.com", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                Section {
                    TextField("https://player.example.com", text: $player)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: player) { _, value in
                            VideoPlayer.server = URL(serverAddress: value)
                        }
                } header: {
                    Text("Video Player")
                } footer: {
                    Text("yt-dlp web player for video links. Leave empty to open links in the browser.")
                }
                if let error = browser.setupError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        connecting = true
                        Task {
                            await browser.connect(server: server, username: username, password: password)
                            connecting = false
                        }
                    } label: {
                        if connecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(connecting || server.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("gomuks")
            .toolbar {
                if browser.credentials != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        if #available(iOS 26, *) {
                            Button(role: .close) {
                                browser.dismissSetup()
                            }
                            .accessibilityIdentifier("gomuks-setup-close")
                        } else {
                            Button("Cancel") {
                                browser.dismissSetup()
                            }
                            .accessibilityIdentifier("gomuks-setup-close")
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

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
              let server = URL(serverAddress: raw),
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

extension URL {
    init?(serverAddress raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        self = url
    }
}

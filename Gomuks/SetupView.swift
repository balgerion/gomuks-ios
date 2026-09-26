import SwiftUI

struct SetupView: View {
    @ObservedObject var browser: Browser
    @State private var server: String
    @State private var username: String
    @State private var password: String
    @State private var connecting = false

    init(browser: Browser) {
        self.browser = browser
        let credentials = browser.credentials
        _server = State(initialValue: credentials?.server.absoluteString ?? Browser.defaultServer)
        _username = State(initialValue: credentials?.username ?? "")
        _password = State(initialValue: credentials?.password ?? "")
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
                        Button("Cancel") {
                            browser.dismissSetup()
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

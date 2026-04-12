import SwiftUI
import CoralCore

/// Sheet for connecting to an SMB server.
struct SMBConnectView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    let onConnect: (SMBServerConfig, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Address (e.g. 192.168.1.100)", text: $host)
                        .textContentType(.URL)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        #endif
                    TextField("Share name (e.g. Photos)", text: $share)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section("Display") {
                    TextField("Name (optional)", text: $displayName)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(JM.Font.caption())
                    }
                }
            }
            .navigationTitle("Connect to Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        connect()
                    }
                    .disabled(host.isEmpty || share.isEmpty || username.isEmpty || isConnecting)
                }
            }
            .overlay {
                if isConnecting {
                    ProgressView("Connecting...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        let config = SMBServerConfig(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            share: share.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username,
            displayName: displayName
        )

        Task {
            do {
                // Test the connection
                let source = SMBSource(config: config, password: password)
                _ = try await source.rootContainers()
                await source.disconnect()

                // Connection works — save and return
                SMBConfigStore.add(config)
                SMBConfigStore.savePassword(password, for: config.id)

                await MainActor.run {
                    isConnecting = false
                    onConnect(config, password)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var client:   KnowledgedClient

    @State private var draftURL        = ""
    @State private var pingState: PingState = .idle

    private enum PingState {
        case idle, checking, ok, failed(String)
    }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("URL") {
                    HStack(spacing: 8) {
                        TextField("http://localhost:9090", text: $draftURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 240)
                            .onSubmit(applyURL)

                        Button("Apply", action: applyURL)
                            .buttonStyle(.bordered)
                    }
                }

                LabeledContent("Connection") {
                    HStack(spacing: 8) {
                        pingIndicator
                        Button("Test") { ping() }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Backend", value: "knowledged HTTP API")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.vertical, 8)
        .onAppear { draftURL = settings.serverURL }
    }

    // MARK: - Ping indicator

    @ViewBuilder
    private var pingIndicator: some View {
        switch pingState {
        case .idle:
            Text("Not checked")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Actions

    private func applyURL() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        settings.serverURL = trimmed
        pingState = .idle
    }

    private func ping() {
        pingState = .checking
        Task {
            do {
                // Use GET /content?path=INDEX.md as the health check.
                _ = try await client.getFile(path: "INDEX.md")
                pingState = .ok
            } catch {
                pingState = .failed(error.localizedDescription)
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let ver  = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(ver) (\(build))"
    }
}

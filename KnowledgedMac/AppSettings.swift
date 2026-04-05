import Foundation

/// Persisted application settings, shared across all views via @EnvironmentObject.
class AppSettings: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Keys.serverURL) }
    }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: Keys.serverURL)
            ?? "http://localhost:9090"
    }

    var baseURL: URL? { URL(string: serverURL) }

    private enum Keys {
        static let serverURL = "serverURL"
    }
}

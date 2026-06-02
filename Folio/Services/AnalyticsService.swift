import Foundation

/// Sends a single fire-and-forget launch event to the Folio-Listener edge function.
/// No personal data is collected — only an anonymous UUID generated once per device,
/// the app version, and the platform string "macos".
enum AnalyticsService {

    private static let endpoint = URL(string: "https://bghidhkhscdhzvdgqyeh.supabase.co/functions/v1/Folio-Listener")!
    private static let userIDKey = "analytics.anonymousUserID"

    /// Call once at app launch. Returns immediately; the network request runs in the background.
    static func recordLaunch() {
        Task.detached(priority: .background) {
            await send(eventType: "launch", userID: anonymousUserID)
        }
    }

    // MARK: - Private

    /// Persistent anonymous UUID — created on first launch, never changes.
    private static var anonymousUserID: String {
        if let existing = UserDefaults.standard.string(forKey: userIDKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: userIDKey)
        return new
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private static func send(eventType: String, userID: String?) async {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        var payload: [String: String] = [
            "event_type": eventType,
            "app_version": appVersion,
            "platform": "macos",
        ]
        if let userID { payload["user_id"] = userID }

        guard let body = try? JSONEncoder().encode(payload) else { return }
        request.httpBody = body

        _ = try? await URLSession.shared.data(for: request)
    }
}

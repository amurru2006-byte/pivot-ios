import Foundation
import Combine
import Security
import UserNotifications

/// Credentials and cooldown never enter AppData, exported backups or diagnostics.
private enum OnlineCoachKeychain {
    private static let service = "app.pivot.personal.online-coach.v1"
    static func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:account,
            kSecAttrSynchronizable as String:false, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = item as? Data else { throw KeychainFailure.unavailable }
        return try JSONDecoder().decode(type, from: bytes)
    }
    static func write<T: Encodable>(_ value: T, account: String) throws {
        let bytes = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:account, kSecAttrSynchronizable as String:false]
        let attributes: [String: Any] = [kSecValueData as String:bytes,
            kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw KeychainFailure.unavailable }
        } else if update != errSecSuccess { throw KeychainFailure.unavailable }
    }
    static func remove(account: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:account, kSecAttrSynchronizable as String:false]
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KeychainFailure.unavailable }
    }
    enum KeychainFailure: Error { case unavailable }
}

private final class OnlineCoachSessionDelegate: NSObject, URLSessionTaskDelegate {
    // Redirecting a request could disclose its authorization or body to another host.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class OnlineCoachService: ObservableObject {
    static let settingsChanged = Notification.Name("pivot-online-coach-settings-changed")
    @Published private(set) var isConfigured = false
    @Published private(set) var isRequesting = false
    @Published private(set) var failure: CoachOnlineFailure?
    @Published private(set) var configurationMessage: String?
    private var configuration: CoachOnlineConfiguration?
    private var generation = 0
    private var session: URLSession?
    private let delegate = OnlineCoachSessionDelegate()
    private let quotaNotificationID = "pivot-online-coach-retry"
    #if DEBUG && targetEnvironment(simulator)
    private var quotaFixture: Bool { ProcessInfo.processInfo.arguments.contains("--online-coach-quota-test") }
    private var preflightFixture: Bool { ProcessInfo.processInfo.arguments.contains("--online-coach-preflight-test") }
    #endif

    init() { reload() }
    func reload() {
        #if DEBUG && targetEnvironment(simulator)
        if preflightFixture { isConfigured = true; return }
        if quotaFixture {
            isConfigured = true
            if failure == nil { failure = .init(kind: .quota, receivedAt: Date(), retryAt: Date().addingTimeInterval(5 * 3600)) }
            return
        }
        #endif
        do {
            configuration = try OnlineCoachKeychain.read(CoachOnlineConfiguration.self, account: "configuration")
            isConfigured = configuration?.valid == true
            failure = try OnlineCoachKeychain.read(CoachOnlineFailure.self, account: "cooldown")
            configurationMessage = nil
        } catch {
            configuration = nil; isConfigured = false
            configurationMessage = "Non riesco a leggere il collegamento protetto. Sblocca l'iPhone e riprova."
        }
    }
    func configure(endpoint: String, token: String, consent: Bool) -> Bool {
        let config = CoachOnlineConfiguration(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines), consent: consent)
        guard config.valid else { configurationMessage = "Controlla l'indirizzo HTTPS del collegamento, il token e il consenso."; return false }
        do {
            cancel()
            try OnlineCoachKeychain.write(config, account: "configuration")
            try OnlineCoachKeychain.remove(account: "cooldown")
            configuration = config; isConfigured = true; failure = nil
            configurationMessage = "Collegamento salvato nel portachiavi di questo iPhone."
            NotificationCenter.default.post(name: Self.settingsChanged, object: nil)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [quotaNotificationID])
            return true
        } catch { configurationMessage = "Il collegamento non è stato salvato. Riprova dopo aver sbloccato l'iPhone."; return false }
    }
    func disconnect() -> Bool {
        cancel()
        configuration = nil; isConfigured = false; failure = nil
        do {
            try OnlineCoachKeychain.remove(account: "configuration")
            try OnlineCoachKeychain.remove(account: "cooldown")
            configuration = nil; isConfigured = false; failure = nil
            configurationMessage = "AI online scollegata. La base locale resta disponibile."
            NotificationCenter.default.post(name: Self.settingsChanged, object: nil)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [quotaNotificationID])
            return true
        } catch { configurationMessage = "Non riesco a rimuovere il collegamento protetto. Riprova dopo aver sbloccato l'iPhone."; return false }
    }
    func cancel() {
        generation += 1; session?.invalidateAndCancel(); session = nil; isRequesting = false
    }
    func ask(_ snapshot: CoachV8Snapshot) async throws -> CoachV8Response {
        try Task.checkCancellation()
        if let failure, let seconds = failure.remaining(at: Date()), seconds > 0 { throw failure }
        #if DEBUG && targetEnvironment(simulator)
        if preflightFixture {
            // A cancelled preflight must never reach this synthetic provider failure.
            let value = CoachOnlineFailure(kind: .invalidResponse, receivedAt: Date())
            failure = value; throw value
        }
        if quotaFixture {
            let value = CoachOnlineFailure(kind: .quota, receivedAt: Date(), retryAt: Date().addingTimeInterval(5 * 3600))
            failure = value; throw value
        }
        #endif
        guard !isRequesting, let config = configuration, config.valid, let url = config.url else {
            throw CoachOnlineFailure(kind: .notConfigured, receivedAt: Date())
        }
        let bytes = try snapshot.request.encoded()
        guard bytes.count <= 24_000 else { throw CoachV8Error.contextTooLarge }
        let currentGeneration = generation
        isRequesting = true
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil; settings.httpCookieStorage = nil; settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.timeoutIntervalForRequest = 30; settings.timeoutIntervalForResource = 35
        settings.waitsForConnectivity = false
        let active = URLSession(configuration: settings, delegate: delegate, delegateQueue: nil)
        session = active
        defer {
            active.invalidateAndCancel()
            if generation == currentGeneration { isRequesting = false; session = nil }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = bytes
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + config.token, forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (stream, response) = try await active.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url == url,
                  http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else {
                throw CoachOnlineFailure(kind: .invalidResponse, receivedAt: Date())
            }
            var body = Data()
            for try await byte in stream {
                if Task.isCancelled || generation != currentGeneration { throw CancellationError() }
                guard body.count < 8192 else { throw CoachOnlineFailure(kind: .invalidResponse, receivedAt: Date()) }
                body.append(byte)
            }
            guard generation == currentGeneration, !Task.isCancelled else { throw CancellationError() }
            if http.statusCode != 200 { throw CoachOnlineFailure.parse(status: http.statusCode, bytes: body, receivedAt: Date()) }
            let value = try CoachV8Response.decode(body, for: snapshot.request)
            failure = nil; try? OnlineCoachKeychain.remove(account: "cooldown")
            return value
        } catch {
            let value: CoachOnlineFailure
            if generation != currentGeneration || error is CancellationError { value = .init(kind: .cancelled, receivedAt: Date()) }
            else if let reported = error as? CoachOnlineFailure { value = reported }
            else if let network = error as? URLError, network.code == .timedOut { value = .init(kind: .timeout, receivedAt: Date()) }
            else if error is CoachV8Error { value = .init(kind: .invalidResponse, receivedAt: Date()) }
            else { value = .init(kind: .unavailable, receivedAt: Date()) }
            if generation == currentGeneration {
                failure = value
                if value.kind == .quota || value.kind == .rateLimit { try? OnlineCoachKeychain.write(value, account: "cooldown") }
            }
            throw value
        }
    }
    func notifyWhenRetryIsPossible() async {
        guard let retry = failure?.retryAt, retry > Date() else { configurationMessage = "Non c'è un orario comunicato dal servizio da usare per il promemoria."; return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            configurationMessage = "Abilita le notifiche di Pivot nelle impostazioni dell'iPhone per ricevere il promemoria."; return
        }
        let content = UNMutableNotificationContent()
        content.title = "Pivot"; content.body = "Puoi riprovare l'AI online. Apri Pivot per verificare la disponibilità."
        content.sound = .default; content.userInfo = ["destination":"coach"]
        let interval = max(1, retry.timeIntervalSinceNow)
        do {
            try await center.add(.init(identifier: quotaNotificationID, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            configurationMessage = "Promemoria impostato. Il messaggio resta dentro Pivot."
        } catch { configurationMessage = "Non riesco a impostare il promemoria. Il timer resta visibile in Pivot." }
    }
}

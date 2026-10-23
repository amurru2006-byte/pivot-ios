import Foundation
import Combine
import Security
import UserNotifications

/// Credentials and cooldown never enter AppData, exported backups or diagnostics.
private enum OnlineCoachKeychain {
    // Opening an external URL can relaunch the simulator app without XCTest's
    // launch environment. Persist only the non-secret QA UUID before that hop;
    // do not accidentally write fixtures into the normal Keychain namespace.
    static func prepareInteractionNamespace() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_KEYCHAIN_ID"], let id = UUID(uuidString: value) {
            UserDefaults.standard.set(id.uuidString, forKey: "pivot-online-coach-qa-namespace")
        }
        #endif
    }
    static var interactionNamespace: String? {
        #if DEBUG && targetEnvironment(simulator)
        prepareInteractionNamespace()
        return UserDefaults.standard.string(forKey: "pivot-online-coach-qa-namespace").flatMap { UUID(uuidString: $0)?.uuidString }
        #else
        return nil
        #endif
    }
    private static var service: String {
        let base = "app.pivot.personal.online-coach.v1"
        #if DEBUG && targetEnvironment(simulator)
        if let id = interactionNamespace {
            return base + ".qa." + id
        }
        #endif
        return base
    }
    static func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:account,
            kSecAttrSynchronizable as String:false, kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(operation: .read, status: status) }
        guard let bytes = item as? Data else { throw KeychainFailure(operation: .read, status: errSecDecode) }
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
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainFailure(operation: .add, status: result) }
        } else if update != errSecSuccess { throw KeychainFailure(operation: .update, status: update) }
    }
    static func remove(account: String) throws {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:account, kSecAttrSynchronizable as String:false]
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KeychainFailure(operation: .remove, status: result) }
    }
    struct KeychainFailure: Error {
        enum Operation: String { case read, update, add, remove }
        var operation: Operation
        var status: OSStatus
    }
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
    #if DEBUG && targetEnvironment(simulator)
    static func prepareInteractionTestNamespace() { OnlineCoachKeychain.prepareInteractionNamespace() }
    static var interactionTestNamespace: String? { OnlineCoachKeychain.interactionNamespace }
    // Only a closed operation and numeric OSStatus, never a query, value or raw error.
    @Published private(set) var keychainTestDiagnostic: String?
    @Published private(set) var interactionRequestCount = 0
    #endif
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
    private var reviewFixture: Bool { ProcessInfo.processInfo.arguments.contains("--online-coach-review-test") }
    private var actionFixture: Bool { ProcessInfo.processInfo.arguments.contains("--online-coach-action-test") }
    #endif

    init() { reload() }
    func reload() {
        clearKeychainFailure()
        #if DEBUG && targetEnvironment(simulator)
        if preflightFixture || reviewFixture || actionFixture { isConfigured = true; return }
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
            recordKeychainFailure(error)
            configurationMessage = "Non riesco a leggere il collegamento protetto. Il portachiavi non è disponibile; l'AI online resta disattivata."
        }
    }
    func configure(endpoint: String, token: String, consent: Bool) -> Bool {
        clearKeychainFailure()
        let config = CoachOnlineConfiguration(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines), consent: consent)
        guard config.valid else { configurationMessage = "Controlla l'indirizzo HTTPS del collegamento, il token e il consenso."; return false }
        do {
            cancel()
            // Cleanup must succeed before replacing the saved configuration:
            // a failed save must not silently enable a new token on next launch.
            try OnlineCoachKeychain.remove(account: "cooldown")
            try OnlineCoachKeychain.write(config, account: "configuration")
            configuration = config; isConfigured = true; failure = nil
            configurationMessage = "Collegamento salvato nel portachiavi di questo iPhone."
            NotificationCenter.default.post(name: Self.settingsChanged, object: nil)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [quotaNotificationID])
            return true
        } catch {
            recordKeychainFailure(error)
            configurationMessage = "Il collegamento non è stato salvato. Il portachiavi non è disponibile: nessun nuovo collegamento è stato attivato."
            return false
        }
    }
    func disconnect() -> Bool {
        clearKeychainFailure()
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
        } catch {
            recordKeychainFailure(error)
            configurationMessage = "Non riesco a rimuovere il collegamento protetto dal portachiavi. Lo scollegamento non è confermato: riprova."
            return false
        }
    }
    private func clearKeychainFailure() {
        #if DEBUG && targetEnvironment(simulator)
        keychainTestDiagnostic = nil
        #endif
    }
    private func recordKeychainFailure(_ error: Error) {
        #if DEBUG && targetEnvironment(simulator)
        if let failure = error as? OnlineCoachKeychain.KeychainFailure {
            keychainTestDiagnostic = failure.operation.rawValue + ":" + String(failure.status)
        } else { keychainTestDiagnostic = "decode" }
        #endif
    }
    func cancel() {
        generation += 1; session?.invalidateAndCancel(); session = nil; isRequesting = false
    }
    func ask(_ snapshot: CoachV8Snapshot) async throws -> CoachV8Response {
        try Task.checkCancellation()
        if let failure, let seconds = failure.remaining(at: Date()), seconds > 0 { throw failure }
        #if DEBUG && targetEnvironment(simulator)
        if actionFixture {
            interactionRequestCount += 1
            if ProcessInfo.processInfo.arguments.contains("--planning-conversation-test"), snapshot.request.version == 4,
               let alias = snapshot.request.planningContext?.first?.intent.eventIDs.first ?? snapshot.request.references?.first ?? snapshot.request.events.first?.id {
                let followup = snapshot.request.planningContext?.isEmpty == false
                let intent = CoachPlanningIntent(eventIDs: [alias], allowedDayOffsets: followup ? [3] : [1, 3, 4],
                    excludedDayOffsets: followup ? [1, 2] : [2], band: .afternoon,
                    earliestMinute: nil, latestMinute: nil, afterEventID: nil)
                return .init(version: 4, requestID: snapshot.request.requestID, mode: .recover, eventIDs: [], reply: "Vincoli QA da controllare.", actions: [], planning: intent)
            }
            if ProcessInfo.processInfo.arguments.contains("--calendar-mutations-test"), snapshot.request.version >= 3,
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_COACH_ACTION_ID"] ?? "") != nil {
                let updating = snapshot.request.message.localizedCaseInsensitiveContains("modifica")
                let ids = updating ? Array(snapshot.request.events.prefix(1)).map(\.id) : snapshot.request.events.map(\.id)
                let actions = ids.map { CoachCalendarEdit(kind: updating ? .update : .delete, eventID: $0,
                    title: updating ? "Impegno QA modificato" : nil, start: nil, end: nil, notes: nil) }
                return .init(version: snapshot.request.version, requestID: snapshot.request.requestID, mode: .actions, eventIDs: [], reply: "Anteprima QA, nessuna scrittura.", actions: actions)
            }
            if ProcessInfo.processInfo.arguments.contains("--conversation-continuity-test"), snapshot.request.version >= 3,
               UUID(uuidString: ProcessInfo.processInfo.environment["PIVOT_QA_COACH_ACTION_ID"] ?? "") != nil {
                if var draft = snapshot.request.draftContext?.last {
                    draft.end = draft.start?.addingTimeInterval(3600)
                    return .init(version: snapshot.request.version, requestID: snapshot.request.requestID, mode: .create, eventIDs: [], reply: "Bozza completata con i dati precedenti.", draft: draft, actions: [])
                }
                let draft = CoachCalendarDraft(title: "Attività passata QA", start: Date().addingTimeInterval(-7200), end: nil,
                    calendarHint: "Personale test", notes: "Nota dettata QA", endEstimated: false)
                return .init(version: snapshot.request.version, requestID: snapshot.request.requestID, mode: .clarify, eventIDs: [], reply: "A che ora è finita?", draft: draft, actions: [])
            }
            if snapshot.request.purpose == "rewrite" {
                return .init(version: snapshot.request.version, requestID: snapshot.request.requestID, mode: .rewrite, eventIDs: [], reply: "Testo riordinato",
                             draft: nil, rewrittenMessage: snapshot.request.message.replacingOccurrences(of: "latte uova farina", with: "\n- latte\n- uova\n- farina"))
            }
            let start = PivotDate.calendar.startOfDay(for: Date()).addingTimeInterval(22 * 3600)
            let draft = CoachCalendarDraft(title: "Impegno di prova", start: start > Date() ? start : Date().addingTimeInterval(3600),
                                          end: start > Date() ? start.addingTimeInterval(7200) : Date().addingTimeInterval(7200),
                                          calendarHint: "Personale test", notes: "Nota sintetica", endEstimated: false)
            return .init(version: snapshot.request.version, requestID: snapshot.request.requestID, mode: .create, eventIDs: [], reply: "Bozza pronta, nessun evento creato.", draft: draft,
                actions: snapshot.request.version >= 3 ? [] : nil)
        }
        if preflightFixture || reviewFixture {
            interactionRequestCount += 1
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
        let bytes = snapshot.encodedRequest
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
                guard body.count < (snapshot.request.version >= 2 ? 32_000 : 8192) else { throw CoachOnlineFailure(kind: .invalidResponse, receivedAt: Date()) }
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

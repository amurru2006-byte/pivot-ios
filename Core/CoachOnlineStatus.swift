import Foundation

struct CoachOnlineConfiguration: Codable {
    var endpoint: String
    var token: String
    var consent: Bool
    var url: URL? {
        guard let value = URLComponents(string: endpoint), value.scheme == "https",
              let host = value.host, host.hasSuffix(".workers.dev"), host.count > ".workers.dev".count,
              value.port == nil || value.port == 443, value.user == nil, value.password == nil,
              value.query == nil, value.fragment == nil, value.path == "/v1/coach",
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }) else { return nil }
        return value.url
    }
    var valid: Bool {
        consent && url != nil && (43...128).contains(token.count)
            && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// Sanitized transport state. It never retains raw provider error bodies or prompts.
struct CoachOnlineFailure: Error, Codable, Equatable, LocalizedError {
    enum Kind: String, Codable {
        case quota, rateLimit, notConfigured, authentication, unavailable, timeout, invalidResponse, cancelled
    }
    var kind: Kind
    var receivedAt: Date
    var retryAt: Date?
    var remainingSeconds: Int? { remaining(at: Date()) }
    func remaining(at now: Date) -> Int? {
        retryAt.map { max(0, Int(ceil($0.timeIntervalSince(now)))) }
    }
    var errorDescription: String? {
        switch kind {
        case .quota: return "Il limite dell'AI online è stato raggiunto. Puoi continuare con la base locale."
        case .rateLimit: return "Sono arrivate troppe richieste ravvicinate. Puoi continuare con la base locale."
        case .notConfigured: return "Il collegamento AI online non è ancora configurato."
        case .authentication: return "Il collegamento AI online va riconfigurato nelle impostazioni."
        case .unavailable: return "L'AI online non è raggiungibile. Il messaggio resta qui; puoi usare la base locale."
        case .timeout: return "L'AI online non ha risposto in tempo. Il messaggio resta qui; puoi usare la base locale."
        case .invalidResponse: return "La risposta online non supera i controlli. Nessuna modifica è stata applicata."
        case .cancelled: return "Richiesta interrotta. Nessuna modifica è stata applicata."
        }
    }
    func timingLabel(at now: Date) -> String? {
        guard kind == .quota || kind == .rateLimit else { return nil }
        guard let seconds = remaining(at: now) else { return "Il servizio non comunica l'orario di ripristino. Puoi riprovare manualmente." }
        if seconds == 0 { return "Puoi riprovare ora. La disponibilità sarà verificata con la prossima richiesta." }
        return "Riprova tra " + String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
    static func parse(status: Int, bytes: Data, receivedAt: Date) -> Self {
        guard bytes.count <= 8192,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let code = object["error"] as? String,
              Set(object.keys).isSubset(of: ["error", "retryAfterSeconds", "retryAt"]) else {
            return .init(kind: status == 401 || status == 403 ? .authentication : .unavailable, receivedAt: receivedAt)
        }
        var kind: Kind = .unavailable
        if status == 429 && code == "quota_unavailable" { kind = .quota }
        else if status == 429 && code == "rate_limited" { kind = .rateLimit }
        else if status == 401 || status == 403 { kind = .authentication }
        else if code == "not_configured" { kind = .notConfigured }
        else if code == "provider_timeout" { kind = .timeout }
        else if code == "invalid_response" { kind = .invalidResponse }
        var retry: Date?
        if kind == .quota || kind == .rateLimit,
           let seconds = object["retryAfterSeconds"] as? NSNumber,
           String(cString: seconds.objCType) != "c", seconds.doubleValue.isFinite,
           seconds.doubleValue.rounded() == seconds.doubleValue, (1...604800).contains(seconds.doubleValue) {
            // A relative wait remains correct even when the server/device clocks differ.
            retry = receivedAt.addingTimeInterval(seconds.doubleValue)
        }
        return .init(kind: kind, receivedAt: receivedAt, retryAt: retry)
    }
}

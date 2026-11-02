import Foundation
import SwiftUI
import WebKit
import CryptoKit

/// First native bridge increment: site login + read-only DOM observation.
/// No setter, Finish action, cookie API, credential capture or automatic sender.
@MainActor
final class FitProsBrowserSession: NSObject, ObservableObject, WKNavigationDelegate {
    enum BridgeError: LocalizedError {
        case wrongPage, navigating, changedPage, invalidObservation, accountNotVisible
        var errorDescription: String? {
            switch self {
            case .wrongPage: return "Apri la pagina FitPros prevista per questa verifica."
            case .navigating: return "Attendi che FitPros abbia terminato il caricamento."
            case .changedPage: return "La pagina è cambiata durante la verifica. Rileggila prima di continuare."
            case .invalidObservation: return "La struttura della pagina FitPros non è riconosciuta. Nessun risultato è stato inviato."
            case .accountNotVisible: return "Apri la pagina Account di FitPros e verifica l'accesso."
            }
        }
    }
    enum Phase: Equatable { case unopened, browsing, reading, failed(String) }
    struct AccountProof: Equatable {
        let accountKey: String
        let observedAt: Date
        // Visible account address, hashed locally. Not an auth token or API UID.
        func isFresh(at date: Date) -> Bool {
            let age = date.timeIntervalSince(observedAt)
            return age >= 0 && age <= 120
        }
    }
    struct Surface: Decodable {
        struct Cell: Decodable { let ordinal: Int; let current: Double?; let placeholder: String }
        struct Metric: Decodable { let id: String; let kind: String; let unit: String; let cells: [Cell] }
        struct Exercise: Decodable {
            let anchor: String; let title: String; let metrics: [Metric]; let notes: String
            let statusControl: Bool; let failureControl: Bool
        }
        let schema: Int
        let adapter: String
        let programId: String; let workoutId: String; let weekId: String
        let title: String; let exercises: [Exercise]
        let loggedSets: Int; let totalSets: Int; let emptyDraft: Bool
        let prescriptionCanonical: String; let stateCanonical: String
        let canWrite: Bool; let serverPersistenceVerified: Bool; let accountIdentityVerified: Bool
        var prescriptionFingerprint: String { Self.hash(prescriptionCanonical) }
        var stateFingerprint: String { Self.hash(stateCanonical) }
        private static func hash(_ value: String) -> String {
            SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    @Published private(set) var phase: Phase = .unopened
    let webView: WKWebView
    private var navigationGeneration = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        // Let WebKit and the authentic site manage login. Never extract cookies.
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }
    func openAccount() {
        phase = .browsing
        webView.load(URLRequest(url: URL(string: "https://app.fitpros.io/account")!))
    }
    func readVisibleAccount(now: Date = Date()) async throws -> AccountProof {
        let page = try checkedPage(path: "/account")
        let generation = navigationGeneration
        phase = .reading
        defer { if phase == .reading { phase = .browsing } }
        let script = #"""
        const headings = Array.from(document.querySelectorAll('h1')).filter(e => e.textContent.trim() === 'Account');
        if (headings.length !== 1) throw new Error('account_not_visible');
        const visible = document.body.innerText;
        const addresses = Array.from(new Set((visible.match(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi) || []).map(x => x.toLowerCase())));
        if (addresses.length !== 1) throw new Error('ambiguous_visible_account');
        return addresses[0];
        """#
        guard let address = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil,
                                                                   contentWorld: .defaultClient) as? String,
              address.utf8.count <= 320, address.contains("@")
        else { throw BridgeError.accountNotVisible }
        guard generation == navigationGeneration, webView.url == page, !webView.isLoading
        else { throw BridgeError.changedPage }
        let key = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return AccountProof(accountKey: key, observedAt: now)
    }
    func readEditor() async throws -> Surface {
        let page = try checkedPage(path: "/workout-log")
        let generation = navigationGeneration
        phase = .reading
        defer { if phase == .reading { phase = .browsing } }
        let script = FitProsDOMScript.observer + "\nreturn JSON.stringify(readFitProsEditor(document, href));"
        guard let json = try await webView.callAsyncJavaScript(script, arguments: ["href":page.absoluteString],
                                                               in: nil, contentWorld: .defaultClient) as? String,
              json.utf8.count <= 1_048_576
        else { throw BridgeError.invalidObservation }
        guard generation == navigationGeneration, webView.url == page, !webView.isLoading
        else { throw BridgeError.changedPage }
        let result = try JSONDecoder().decode(Surface.self, from: Data(json.utf8))
        guard result.schema == 1, result.adapter == "fitpros-visible-logger-v1",
              !result.canWrite, !result.serverPersistenceVerified, !result.accountIdentityVerified,
              (1...40).contains(result.exercises.count), (1...400).contains(result.totalSets),
              (0...result.totalSets).contains(result.loggedSets)
        else { throw BridgeError.invalidObservation }
        return result
    }
    private func checkedPage(path: String) throws -> URL {
        guard !webView.isLoading else { throw BridgeError.navigating }
        guard let page = webView.url, page.scheme == "https", page.host?.lowercased() == "app.fitpros.io",
              page.path == path else { throw BridgeError.wrongPage }
        return page
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard let url = action.request.url, url.scheme == "https", url.host?.lowercased() == "app.fitpros.io"
        else {
            phase = .failed("Questa pagina non appartiene all'app FitPros. Aprila separatamente nel browser se ti serve.")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationGeneration += 1
        phase = .browsing
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        phase = .failed("FitPros non ha completato il caricamento. Nessun risultato è stato inviato.")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        phase = .failed("FitPros non è raggiungibile. Nessun risultato è stato inviato.")
    }
}

/// Setup/inspection surface only. Not added as a production menu or result sender.
struct FitProsBrowserView: UIViewRepresentable {
    @ObservedObject var session: FitProsBrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

import Foundation

/// Original motivational names supplied by the user, in rank order.
/// Presentation only: these do not change the published strength thresholds.
enum StrengthRankPresentation {
    static let names = ["Schiavo della gravità", "Patto col ferro", "Sfidante della fisica",
                        "Distruttore di ego", "Mutante", "Forza primordiale", "Onnipotente del carico"]
    static var count: Int { names.count }
    static func name(_ level: Int) -> String {
        names.indices.contains(level) ? names[level] : "Rank non disponibile"
    }
    static func emblem(_ level: Int) -> String? {
        names.indices.contains(level) ? "Rank\(level + 1)Emblem" : nil
    }
    static func titleArtwork(_ level: Int) -> String? {
        names.indices.contains(level) ? "Rank\(level + 1)Title" : nil
    }
    static func kg(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "it_IT"), value) + " kg"
    }
}

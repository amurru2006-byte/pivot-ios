import Foundation

/// A minimizer, not a semantic anonymizer. The exact outgoing request must still
/// be reviewed on-device; unknown names and sensitive prose can survive rules.
enum CoachPrivacy {
    static func knownLocations(events: [CalendarItem], data: AppData) -> [String] {
        var locations = Set<String>()
        var explicitCatalogValues = Set<String>()
        for event in events { locations.insert(event.location) }
        for client in data.clients {
            guard let defaults = client.defaults else { continue }
            locations.insert(defaults.address)
            for origin in defaults.origins { locations.insert(origin.address) }
        }
        if let library = data.placeLibrary {
            for place in library.favorites + library.recent.map({ SavedPlace($0.place) }) {
                locations.insert(place.name); locations.insert(place.address)
                explicitCatalogValues.insert(place.name); explicitCatalogValues.insert(place.address)
                if let latitude = place.latitude, let longitude = place.longitude {
                    // Only coordinate pairs, never individual numbers: otherwise
                    // a latitude like 45 could erase a duration or an amount.
                    for separator in [",", ", ", " "] {
                        locations.insert("\(latitude)\(separator)\(longitude)")
                        locations.insert("\(latitude)\(separator)\(longitude)".replacingOccurrences(of: ".", with: ","))
                    }
                }
            }
        }
        return Array(locations).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ($0.count >= 3 || explicitCatalogValues.contains($0)) }
    }
    static func text(_ text: String, events: [CalendarItem], data: AppData) -> String {
        var value = text
        var replacements: [(String, String)] = []
        for (index, client) in data.clients.enumerated() {
            for name in [client.name] + (client.calendarAliases ?? []) where name.count >= 3 {
                replacements.append((name, "[contatto \(index + 1)]"))
            }
        }
        for location in knownLocations(events: events, data: data) {
            replacements.append((location, "[luogo]"))
        }
        // Longest first avoids exposing the tail of a name/address after a match.
        for (source, alias) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: source) + "(?![\\p{L}\\p{N}])"
            value = replace(pattern, in: value, with: alias)
        }
        for (pattern, alias) in [
            (#"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, "[email]"),
            (#"\b(?:https?://|www\.)[^\s]+"#, "[link]"),
            (#"\b[A-Z]{2}[0-9]{2}(?:\s?[A-Z0-9]){11,30}\b"#, "[conto]"),
            // Phone-like sequences: require >=9 digits, so hours and short
            // amounts remain unchanged. ISO dates are explicitly excluded.
            (#"(?<![\w\d])\+?(?!\d{4}-\d{2}-\d{2}\b)(?:\d[ .()\-]*){8,14}\d(?![\w\d])"#, "[telefono]")
        ] { value = replace(pattern, in: value, with: alias) }
        return value
    }

    private static func replace(_ pattern: String, in value: String, with alias: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return value }
        return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: alias))
    }

    /// Never honor a report/export opt-in at the cloud boundary. Keep Health
    /// reconciliation and the user's full record exclusively in the local data.
    static func calendarData(_ data: AppData) -> AppData {
        HealthImport.exportData(data, allowHealth: false)
    }
}

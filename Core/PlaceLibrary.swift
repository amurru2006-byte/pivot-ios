import Foundation

/// A personal, local shortcut, not evidence of the user's current position.
/// An address entered manually deliberately has no invented coordinates.
struct SavedPlace: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double? = nil
    var longitude: Double? = nil

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 500
            && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && address.count <= 1000
            && coordinatesAreValid
    }
    private var coordinatesAreValid: Bool {
        switch (latitude, longitude) {
        case (nil, nil): return true
        case let (.some(lat), .some(lon)):
            return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
        default: return false
        }
    }
    var resolvedPlace: TravelPlace? {
        guard isValid, let latitude, let longitude else { return nil }
        return .init(id: id, name: name, address: address, latitude: latitude, longitude: longitude)
    }
    init(id: UUID = UUID(), name: String, address: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id; self.name = name; self.address = address
        self.latitude = latitude; self.longitude = longitude
    }
    init(_ place: TravelPlace, id: UUID? = nil, name: String? = nil) {
        self.init(id: id ?? place.id, name: name ?? place.name, address: place.address,
                  latitude: place.latitude, longitude: place.longitude)
    }
}

/// Only explicitly used resolved places enter history. Queries, GPS fixes,
/// route duration and Maps consent never belong in this model.
struct PlaceUse: Codable, Equatable, Identifiable {
    var place: TravelPlace
    var lastUsedAt: Date
    var useCount: Int
    var id: UUID { place.id }
    var isValid: Bool {
        place.isValid && !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && PlaceLibrary.validDate(lastUsedAt) && (1...PlaceLibrary.maximumUseCount).contains(useCount)
    }
}

struct PlaceLibrary: Codable, Equatable {
    static let maximumFavorites = 50
    static let maximumHistory = 30
    static let maximumUseCount = 1_000_000
    var favorites: [SavedPlace] = []
    var recent: [PlaceUse] = []

    enum Failure: LocalizedError {
        case invalid, limit, missing
        var errorDescription: String? {
            switch self {
            case .invalid: return "Controlla nome, indirizzo e coordinate del luogo. Nessun luogo è stato modificato."
            case .limit: return "Hai già 50 luoghi salvati. Rimuovine uno prima di aggiungerne un altro."
            case .missing: return "Questo luogo salvato non è più disponibile. Riapri l’elenco aggiornato."
            }
        }
    }

    var isValid: Bool {
        favorites.count <= Self.maximumFavorites && recent.count <= Self.maximumHistory
            && favorites.allSatisfy(\.isValid) && recent.allSatisfy(\.isValid)
            && Set(favorites.map(\.id) + recent.map(\.id)).count == favorites.count + recent.count
            && !favorites.indices.contains { i in favorites.indices.contains { j in j > i && Self.sameLocation(favorites[i], favorites[j]) } }
            && !recent.indices.contains { i in recent.indices.contains { j in j > i && Self.sameLocation(SavedPlace(recent[i].place), SavedPlace(recent[j].place)) } }
    }
    var sortedFavorites: [SavedPlace] { favorites.sorted(by: Self.favoriteOrder) }
    var recentPlaces: [TravelPlace] { orderedRecent.map(\.place) }
    var frequentPlaces: [TravelPlace] {
        recent.sorted {
            if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
            return Self.recentOrder($0, $1)
        }.map(\.place)
    }
    /// Favorites first, then latest used places; exact location duplicates appear
    /// once. A manual address is not conflated with a resolved result.
    func suggestions(matching query: String = "") -> [SavedPlace] {
        let term = Self.normalized(query)
        var result: [SavedPlace] = []
        for value in sortedFavorites + orderedRecent.map({ SavedPlace($0.place) }) {
            guard term.isEmpty || Self.normalized(value.name).contains(term) || Self.normalized(value.address).contains(term) else { continue }
            if !result.contains(where: { Self.sameLocation($0, value) }) { result.append(value) }
        }
        return result
    }

    /// Called only by an explicit Save action, never while typing/searching.
    @discardableResult mutating func save(name: String, address: String, latitude: Double? = nil,
                                         longitude: Double? = nil, editingID: UUID? = nil) throws -> SavedPlace {
        guard isValid else { throw Failure.invalid }
        let input = SavedPlace(name: name, address: address, latitude: latitude, longitude: longitude)
        guard input.isValid else { throw Failure.invalid }
        if let editingID {
            guard let index = favorites.firstIndex(where: { $0.id == editingID }) else { throw Failure.missing }
            guard !favorites.contains(where: { $0.id != editingID && Self.sameLocation($0, input) }) else { throw Failure.invalid }
            var value = input; value.id = editingID; favorites[index] = value
            return value
        }
        if let index = favorites.firstIndex(where: { Self.sameLocation($0, input) }) {
            var value = input; value.id = favorites[index].id; favorites[index] = value
            return value
        }
        guard favorites.count < Self.maximumFavorites else { throw Failure.limit }
        var value = input
        while recent.contains(where: { $0.id == value.id }) || favorites.contains(where: { $0.id == value.id }) { value.id = UUID() }
        favorites.append(value)
        return value
    }
    @discardableResult mutating func save(_ place: TravelPlace, name: String? = nil, editingID: UUID? = nil) throws -> SavedPlace {
        guard place.isValid else { throw Failure.invalid }
        return try save(name: name ?? place.name, address: place.address, latitude: place.latitude,
                        longitude: place.longitude, editingID: editingID)
    }

    /// The caller invokes this after "Use this estimate", not after search or
    /// selection alone. This does not confirm any route or write a calendar.
    mutating func recordUse(_ place: TravelPlace, now: Date = Date()) throws {
        guard isValid, place.isValid, !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.validDate(now) else { throw Failure.invalid }
        if let index = recent.firstIndex(where: { Self.sameLocation(SavedPlace($0.place), SavedPlace(place)) }) {
            var used = place; used.id = recent[index].id
            recent[index].place = used
            recent[index].lastUsedAt = max(recent[index].lastUsedAt, now)
            recent[index].useCount = min(Self.maximumUseCount, recent[index].useCount + 1)
        } else {
            var used = place
            while favorites.contains(where: { $0.id == used.id }) || recent.contains(where: { $0.id == used.id }) { used.id = UUID() }
            recent.append(.init(place: used, lastUsedAt: now, useCount: 1))
        }
        recent = Array(orderedRecent.prefix(Self.maximumHistory))
    }
    mutating func removeFavorite(id: UUID) throws {
        guard isValid else { throw Failure.invalid }
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { throw Failure.missing }
        favorites.remove(at: index)
    }
    mutating func clearHistory() throws {
        guard isValid else { throw Failure.invalid }
        recent = []
    }

    private var orderedRecent: [PlaceUse] { recent.sorted(by: Self.recentOrder) }
    private static func recentOrder(_ lhs: PlaceUse, _ rhs: PlaceUse) -> Bool {
        if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
        return favoriteOrder(SavedPlace(lhs.place), SavedPlace(rhs.place))
    }
    private static func favoriteOrder(_ lhs: SavedPlace, _ rhs: SavedPlace) -> Bool {
        let a = normalized(lhs.name), b = normalized(rhs.name)
        if a != b { return a < b }
        let leftAddress = normalized(lhs.address), rightAddress = normalized(rhs.address)
        if leftAddress != rightAddress { return leftAddress < rightAddress }
        return lhs.id.uuidString < rhs.id.uuidString
    }
    private static func normalized(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func sameLocation(_ lhs: SavedPlace, _ rhs: SavedPlace) -> Bool {
        normalized(lhs.address) == normalized(rhs.address) && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
    static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(value.timeIntervalSince1970)
    }
}

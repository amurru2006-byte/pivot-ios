import XCTest
@testable import PivotCore

final class PlaceLibraryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func place(_ index: Int = 0, name: String? = nil, address: String? = nil) -> TravelPlace {
        .init(name: name ?? "Luogo sintetico \(index)", address: address ?? "Via sintetica \(index)",
              latitude: 40 + Double(index) / 1000, longitude: 8 + Double(index) / 1000)
    }

    func testOldBackupWithoutCatalogStillDecodesAndNewCatalogRoundTrips() throws {
        var data = AppData()
        let oldBytes = try BackupCodec.encode(data)
        XCTAssertNil(try BackupCodec.decode(oldBytes).placeLibrary)
        var library = PlaceLibrary()
        try library.save(name: "Casa QA", address: "  Indirizzo Sintetico 12/B  ")
        try library.recordUse(place(), now: now)
        data.placeLibrary = library
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.placeLibrary, library)
        XCTAssertEqual(restored.placeLibrary?.favorites.first?.address, "  Indirizzo Sintetico 12/B  ")
    }

    func testManualFavoriteDoesNotInventCoordinatesHistoryOrConfirmation() throws {
        var library = PlaceLibrary()
        let saved = try library.save(name: "Partenza QA", address: "Via sintetica 12")
        XCTAssertNil(saved.resolvedPlace)
        XCTAssertTrue(library.recent.isEmpty)
        let encoded = String(decoding: try JSONEncoder().encode(library), as: UTF8.self)
        for field in ["consent", "duration", "travelConfirmed", "GPS", "travelSeconds"] {
            XCTAssertFalse(encoded.contains(field))
        }
    }

    func testSaveUsesLocationNotNameForConservativeDeduplicationAndKeepsID() throws {
        var library = PlaceLibrary()
        let first = try library.save(name: "Casa QA", address: "  Via Sintetica 12/B ")
        let repeated = try library.save(name: "Altro nome QA", address: "via sintetica  12/b")
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(library.favorites.count, 1)
        XCTAssertEqual(library.favorites[0].address, "via sintetica  12/b", "Keep the exact explicitly saved text")
        try library.save(name: "Altro nome QA", address: "Via sintetica 12/C")
        try library.save(place(address: "Via sintetica 12/B"))
        try library.save(place(1, address: "Via sintetica 12/B"))
        XCTAssertEqual(library.favorites.count, 4, "Different apartments/coordinates and unresolved addresses remain distinct")
    }

    func testEditingKeepsFavoriteIDAndDoesNotChangeHistoricalSnapshot() throws {
        var library = PlaceLibrary()
        let resolved = place()
        let favorite = try library.save(resolved, name: "Etichetta QA")
        try library.recordUse(resolved, now: now)
        let historical = library.recent
        let updated = try library.save(name: "Nuovo nome QA", address: "Nuova via QA", editingID: favorite.id)
        XCTAssertEqual(updated.id, favorite.id)
        XCTAssertNil(updated.resolvedPlace)
        XCTAssertEqual(library.recent, historical)
        XCTAssertEqual(library.recent.first?.place.name, resolved.name)
    }

    func testEditingIntoDuplicateOrMissingFavoriteDoesNotPartiallyMutate() throws {
        var library = PlaceLibrary()
        let a = try library.save(name: "A QA", address: "Via A QA")
        try library.save(name: "B QA", address: "Via B QA")
        let before = library
        XCTAssertThrowsError(try library.save(name: "Nuovo QA", address: "Via B QA", editingID: a.id))
        XCTAssertThrowsError(try library.save(name: "Nuovo QA", address: "Via C QA", editingID: UUID()))
        XCTAssertEqual(library, before)
    }

    func testFavoriteLimitAllowsExistingLocationRenameButRejectsNewOne() throws {
        var library = PlaceLibrary()
        for index in 0..<50 { try library.save(name: "QA \(index)", address: "Via QA \(index)") }
        let id = library.favorites[0].id
        try library.save(name: "Rinominato QA", address: "Via QA 0")
        XCTAssertEqual(library.favorites[0].id, id)
        let before = library
        XCTAssertThrowsError(try library.save(name: "QA extra", address: "Via extra QA"))
        XCTAssertEqual(library, before)
    }

    func testRecentUseDeduplicatesByLocationKeepsIDAndDoesNotRegressTime() throws {
        var library = PlaceLibrary()
        let initial = place()
        try library.recordUse(initial, now: now)
        let id = library.recent[0].id
        let repeated = place(name: "Ultima descrizione QA", address: " via SINTETICA 0 ")
        try library.recordUse(repeated, now: now.addingTimeInterval(-60))
        XCTAssertEqual(library.recent.count, 1)
        XCTAssertEqual(library.recent[0].id, id)
        XCTAssertEqual(library.recent[0].useCount, 2)
        XCTAssertEqual(library.recent[0].lastUsedAt, now)
        XCTAssertEqual(library.recent[0].place.name, repeated.name)
    }

    func testHistoryIsBoundedAndEvictsOldestWithoutDeletingFavorites() throws {
        var library = PlaceLibrary()
        try library.save(place())
        for index in 0..<31 { try library.recordUse(place(index), now: now.addingTimeInterval(Double(index))) }
        XCTAssertEqual(library.recent.count, 30)
        XCTAssertFalse(library.recentPlaces.contains(where: { $0.address == "Via sintetica 0" }))
        XCTAssertEqual(library.recentPlaces.first?.address, "Via sintetica 30")
        XCTAssertEqual(library.favorites.count, 1)
        XCTAssertTrue(library.isValid)
    }

    func testRecentAndFrequentOrdersAreDeterministicWithStableTies() throws {
        var library = PlaceLibrary()
        let a = place(name: "A QA"), b = place(1, name: "B QA"), c = place(2, name: "C QA")
        try library.recordUse(c, now: now)
        try library.recordUse(b, now: now)
        try library.recordUse(a, now: now)
        try library.recordUse(b, now: now.addingTimeInterval(-1))
        XCTAssertEqual(library.recentPlaces.map(\.name), ["A QA", "B QA", "C QA"])
        XCTAssertEqual(library.frequentPlaces.map(\.name), ["B QA", "A QA", "C QA"])
        let restored = try JSONDecoder().decode(PlaceLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.recentPlaces.map(\.id), library.recentPlaces.map(\.id))
        XCTAssertEqual(restored.frequentPlaces.map(\.id), library.frequentPlaces.map(\.id))
    }

    func testSuggestionsMatchNameOrAddressAndDedupOnlyExactResolvedLocation() throws {
        var library = PlaceLibrary()
        let p = place()
        let favorite = try library.save(p, name: "Università QA")
        try library.recordUse(p, now: now)
        try library.recordUse(place(1), now: now.addingTimeInterval(60))
        let list = library.suggestions()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.id, favorite.id)
        XCTAssertEqual(library.suggestions(matching: "UNIVERSITÀ").map(\.id), [favorite.id])
        XCTAssertEqual(library.suggestions(matching: "sintetica 1").count, 1)
        XCTAssertTrue(library.suggestions(matching: "Sconosciuto QA").isEmpty)
    }

    func testClearHistoryAndRemoveFavoriteAreIndependentAndDoNotWriteCalendar() throws {
        var library = PlaceLibrary()
        let favorite = try library.save(place())
        try library.recordUse(place(), now: now)
        try library.removeFavorite(id: favorite.id)
        XCTAssertTrue(library.favorites.isEmpty)
        XCTAssertEqual(library.recent.count, 1)
        try library.save(place(1))
        try library.clearHistory()
        XCTAssertTrue(library.recent.isEmpty)
        XCTAssertEqual(library.favorites.count, 1)
        var data = AppData(); data.placeLibrary = library
        XCTAssertTrue(data.records.isEmpty); XCTAssertTrue(data.rules.isEmpty); XCTAssertTrue(data.moves.isEmpty)
        XCTAssertNil(data.calendarActivityLinks)
    }

    func testUseCounterSaturatesWithoutOverflow() throws {
        var library = PlaceLibrary()
        try library.recordUse(place(), now: now)
        library.recent[0].useCount = PlaceLibrary.maximumUseCount
        try library.recordUse(place(), now: now)
        XCTAssertEqual(library.recent[0].useCount, PlaceLibrary.maximumUseCount)
        XCTAssertTrue(library.isValid)
    }

    func testInvalidInputsNeverMutateValidCatalog() throws {
        var library = PlaceLibrary()
        try library.save(name: "QA", address: "Via QA")
        let before = library
        for value in [SavedPlace(name: " ", address: "QA"), SavedPlace(name: "QA", address: " "),
                      SavedPlace(name: "QA", address: String(repeating: "x", count: 1001)),
                      SavedPlace(name: "QA", address: "QA", latitude: 45),
                      SavedPlace(name: "QA", address: "QA", latitude: 91, longitude: 9)] {
            XCTAssertThrowsError(try library.save(name: value.name, address: value.address,
                                                 latitude: value.latitude, longitude: value.longitude))
            XCTAssertEqual(library, before)
        }
        XCTAssertThrowsError(try library.recordUse(place(), now: Date(timeIntervalSince1970: -1)))
        var invalid = place(); invalid.latitude = .infinity
        XCTAssertThrowsError(try library.recordUse(invalid, now: now))
        XCTAssertEqual(library, before)
    }

    func testBackupRejectsDuplicateIDsIdentitiesInvalidCountersDatesAndCoordinates() throws {
        var base = PlaceLibrary()
        try base.save(name: "Casa QA", address: "Via QA")
        try base.recordUse(place(), now: now)
        var invalids: [PlaceLibrary] = []
        var value = base; value.favorites.append(value.favorites[0]); invalids.append(value)
        value = base; value.recent[0].place.id = value.favorites[0].id; invalids.append(value)
        value = base; value.recent[0].useCount = 0; invalids.append(value)
        value = base; value.recent[0].useCount = PlaceLibrary.maximumUseCount + 1; invalids.append(value)
        value = base; value.recent[0].lastUsedAt = Date(timeIntervalSince1970: -1); invalids.append(value)
        value = base; value.recent[0].lastUsedAt = Date(timeIntervalSince1970: 253_402_300_800); invalids.append(value)
        value = base; value.recent[0].place.longitude = 181; invalids.append(value)
        value = base; value.favorites[0].longitude = 9; invalids.append(value)
        value = base; var duplicate = value.recent[0]; duplicate.place.id = UUID(); value.recent.append(duplicate); invalids.append(value)
        value = base; var duplicateFavorite = value.favorites[0]; duplicateFavorite.id = UUID(); value.favorites.append(duplicateFavorite); invalids.append(value)
        value = .init(favorites: (0..<51).map { SavedPlace(name: "QA \($0)", address: "Via QA \($0)") }); invalids.append(value)
        value = .init(recent: (0..<31).map { PlaceUse(place: place($0), lastUsedAt: now, useCount: 1) }); invalids.append(value)
        for library in invalids {
            XCTAssertFalse(library.isValid)
            var data = AppData(); data.placeLibrary = library
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
            var mutable = library; let original = mutable
            XCTAssertThrowsError(try mutable.clearHistory())
            XCTAssertEqual(mutable, original)
        }
    }

    func testExistingStateIsUntouchedByCatalogEditsAndBackupRoundTrip() throws {
        var data = AppData()
        data.clients = [.init(name: "Contatto QA", rateCents: 1500)]
        let originalClients = data.clients
        var library = PlaceLibrary()
        try library.save(name: "Luogo QA", address: "Via QA")
        data.placeLibrary = library
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.clients, originalClients)
        XCTAssertTrue(restored.records.isEmpty); XCTAssertTrue(restored.payments.isEmpty)
        XCTAssertNil(restored.lessonDefaults)
    }
}

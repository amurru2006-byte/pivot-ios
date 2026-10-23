import Foundation

/// Future online planning boundary. NOT used by the v3 gateway or the 0.8.8
/// release: an intent describes constraints, never slots, ETA or Calendar writes.
struct CoachPlanningIntent: Codable, Equatable {
    var eventIDs: [String]
    var allowedDayOffsets: [Int]
    var excludedDayOffsets: [Int]
    var band: TrainingDurationTimeBand?
    var earliestMinute: Int?
    var latestMinute: Int?
    var afterEventID: String?

    private enum CodingKeys: String, CodingKey {
        case eventIDs, allowedDayOffsets, excludedDayOffsets, band, earliestMinute, latestMinute, afterEventID
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(eventIDs, forKey: .eventIDs)
        try values.encode(allowedDayOffsets, forKey: .allowedDayOffsets)
        try values.encode(excludedDayOffsets, forKey: .excludedDayOffsets)
        try values.encode(band, forKey: .band)
        try values.encode(earliestMinute, forKey: .earliestMinute)
        try values.encode(latestMinute, forKey: .latestMinute)
        try values.encode(afterEventID, forKey: .afterEventID)
    }

    enum Failure: Error, Equatable {
        case invalidIntent, invalidContext, missingReference, ambiguousLocalTime
    }
    private static let keys: Set<String> = ["eventIDs", "allowedDayOffsets", "excludedDayOffsets", "band",
                                           "earliestMinute", "latestMinute", "afterEventID"]
    private static func validAlias(_ value: String) -> Bool {
        value.range(of: #"^e(?:[0-9]|[1-3][0-9]|4[0-7])$"#, options: .regularExpression) != nil
    }
    func isValid(knownAliases: Set<String>) -> Bool {
        guard (1...48).contains(knownAliases.count), knownAliases.allSatisfy(Self.validAlias),
              (1...3).contains(eventIDs.count), Set(eventIDs).count == eventIDs.count,
              eventIDs.allSatisfy({ knownAliases.contains($0) }),
              (1...7).contains(allowedDayOffsets.count), Set(allowedDayOffsets).count == allowedDayOffsets.count,
              allowedDayOffsets.allSatisfy({ (0...6).contains($0) }),
              excludedDayOffsets.count <= 7, Set(excludedDayOffsets).count == excludedDayOffsets.count,
              excludedDayOffsets.allSatisfy({ (0...6).contains($0) }),
              Set(allowedDayOffsets).isDisjoint(with: excludedDayOffsets),
              earliestMinute.map({ (0...1439).contains($0) }) ?? true,
              latestMinute.map({ (1...1440).contains($0) }) ?? true,
              afterEventID.map({ knownAliases.contains($0) && !eventIDs.contains($0) }) ?? true else { return false }
        return minuteBounds.lower < minuteBounds.upper
    }

    /// Required nullable keys stay required: omitted constraints must not be
    /// confused with constraints the model considered and explicitly left empty.
    static func decode(_ bytes: Data, knownAliases: Set<String>) throws -> Self {
        guard (1...2048).contains(bytes.count), uniqueTopLevelKeys(bytes) == keys else { throw Failure.invalidIntent }
        do {
            let value = try JSONDecoder().decode(Self.self, from: bytes)
            guard value.isValid(knownAliases: knownAliases) else { throw Failure.invalidIntent }
            return value
        } catch { throw Failure.invalidIntent }
    }

    /// Returns allowed intervals, NOT planned activities. The scheduler must
    /// still fit full durations/travel, validate snapshots and require review.
    /// Reopening never rebases the original day anchor to today's date.
    func intervals(knownAliases: Set<String>, anchor: Date, now: Date,
                   referenceEnds: [String: Date] = [:]) throws -> [DateInterval] {
        guard isValid(knownAliases: knownAliases) else { throw Failure.invalidIntent }
        guard Self.validDate(anchor), Self.validDate(now), now >= anchor else { throw Failure.invalidContext }
        let expected = Set(afterEventID.map { [$0] } ?? [])
        guard Set(referenceEnds.keys) == expected else { throw Failure.missingReference }
        if referenceEnds.values.contains(where: { !Self.validDate($0) }) { throw Failure.invalidContext }
        let earliest = max(now, afterEventID.flatMap { referenceEnds[$0] } ?? now)
        let calendar = PivotDate.calendar, firstDay = calendar.startOfDay(for: anchor)
        let bounds = minuteBounds
        var result: [DateInterval] = []
        for offset in allowedDayOffsets.sorted() {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay), Self.validDate(day) else { throw Failure.invalidContext }
            let lower = try Self.boundary(bounds.lower, on: day)
            let upper = try Self.boundary(bounds.upper, on: day)
            let start = max(lower, earliest)
            if start < upper { result.append(.init(start: start, end: upper)) }
        }
        return result
    }

    private var minuteBounds: (lower: Int, upper: Int) {
        let bandBounds: (Int, Int)
        switch band {
        case .morning: bandBounds = (0, 720)
        case .afternoon: bandBounds = (720, 1080)
        case .evening: bandBounds = (1080, 1440)
        case nil: bandBounds = (0, 1440)
        }
        return (max(bandBounds.0, earliestMinute ?? 0), min(bandBounds.1, latestMinute ?? 1440))
    }
    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(date.timeIntervalSince1970)
    }
    private static func boundary(_ minute: Int, on day: Date) throws -> Date {
        let calendar = PivotDate.calendar
        if minute == 1440 {
            guard let date = calendar.date(byAdding: .day, value: 1, to: day), validDate(date) else { throw Failure.invalidContext }
            return date
        }
        let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
        // Strict matching rejects nonexistent spring times. Compare both autumn
        // occurrences rather than arbitrarily choosing one of two 02:30 values.
        let before = day.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
              let last = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last),
              calendar.isDate(first, inSameDayAs: day), calendar.isDate(last, inSameDayAs: day), first == last else {
            throw Failure.ambiguousLocalTime
        }
        return first
    }

    /// JSON parsers normally collapse duplicate object keys. Detect them before
    /// decoding, including Unicode-escaped aliases of the same field name.
    /// This bounded scanner only identifies top-level keys; JSONDecoder remains
    /// responsible for JSON grammar, scalar types and nested-array validation.
    private static func uniqueTopLevelKeys(_ data: Data) -> Set<String>? {
        let bytes = [UInt8](data)
        var index = 0, depth = 0
        var found: Set<String> = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 {
                let start = index
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { break }
                    index += 1
                }
                guard index < bytes.count else { return nil }
                let end = index + 1
                var next = end
                while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if depth == 1, next < bytes.count, bytes[next] == 58 {
                    guard let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<end])), found.insert(key).inserted else { return nil }
                }
            } else if byte == 123 || byte == 91 { depth += 1 }
            else if byte == 125 || byte == 93 { depth -= 1 }
            index += 1
        }
        return found
    }
}

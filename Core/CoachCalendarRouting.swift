import Foundation

// The cloud proposes a draft, never a private account/calendar ID. Routing is
// resolved on-device and learns only associations explicitly confirmed there.
enum CoachCalendarRouting {
    struct Choice: Equatable {
        var id: String
        var title: String
        var sourceID: String
    }
    enum Reason: Equatable {
        case namedCalendar, rememberedTopic, preferredCalendar, onlyCalendar
        case ambiguous, unknownHint, missingDestination, missingAccount
    }
    struct Suggestion: Equatable {
        var calendarID: String?
        var reason: Reason
    }
    enum Failure: Error { case invalid }

    static func suggest(title: String, hint: String?, choices: [Choice], settings: Settings) -> Suggestion {
        let candidates: [Choice]
        if let source = settings.preferredNewEventSourceID, !source.isEmpty {
            candidates = choices.filter { $0.sourceID == source }
            guard !candidates.isEmpty else { return .init(reason: .missingAccount) }
        } else { candidates = choices }
        let ids = Set(candidates.map(\.id))
        let hintKey = CoachCalendarDraft.normalizedCalendarHint(hint ?? "")
        if !hintKey.isEmpty {
            if let saved = settings.calendarCreationAliases?[hintKey] {
                return ids.contains(saved) ? .init(calendarID: saved, reason: .namedCalendar) : .init(reason: .missingDestination)
            }
            let matches = candidates.filter { CoachCalendarDraft.normalizedCalendarHint($0.title) == hintKey }
            if matches.count == 1 { return .init(calendarID: matches[0].id, reason: .namedCalendar) }
            if matches.count > 1 { return .init(reason: .ambiguous) }
        }
        let titleWords = " " + EventCoalescer.normalized(title) + " "
        var matches = Set<String>()
        for (topic, id) in settings.calendarTopicRoutes ?? [:] {
            let words = EventCoalescer.normalized(topic)
            guard !words.isEmpty else { continue }
            if titleWords.contains(" " + words + " ") || EventCoalescer.normalized(hint ?? "") == words {
                matches.insert(id)
            }
        }
        if !matches.isEmpty {
            guard matches.count == 1 else { return .init(reason: .ambiguous) }
            let id = matches.first!
            return ids.contains(id) ? .init(calendarID: id, reason: .rememberedTopic) : .init(reason: .missingDestination)
        }
        // An unknown explicit hint is not permission to use an unrelated default.
        guard hintKey.isEmpty else { return .init(reason: .unknownHint) }
        if settings.preferredNewEventSourceID == nil, (settings.calendarTopicRoutes ?? [:]).isEmpty,
           let preferred = settings.preferredNewEventCalendarID, ids.contains(preferred) {
            return .init(calendarID: preferred, reason: .preferredCalendar)
        }
        if candidates.count == 1 { return .init(calendarID: candidates[0].id, reason: .onlyCalendar) }
        return .init(reason: .ambiguous)
    }

    static func remember(topic: String?, calendarID: String, rememberAccount: Bool,
                         choices: [Choice], settings: inout Settings) throws {
        guard let choice = choices.first(where: { $0.id == calendarID }) else { throw Failure.invalid }
        var next = settings
        if rememberAccount {
            guard !choice.sourceID.isEmpty, choice.sourceID.count <= 1024 else { throw Failure.invalid }
            next.preferredNewEventSourceID = choice.sourceID
        }
        if let topic {
            let key = EventCoalescer.normalized(topic)
            guard !key.isEmpty, key.count <= 80 else { throw Failure.invalid }
            var routes = next.calendarTopicRoutes ?? [:]
            routes[key] = calendarID
            guard routes.count <= 100 else { throw Failure.invalid }
            next.calendarTopicRoutes = routes
        }
        guard valid(next) else { throw Failure.invalid }
        settings = next
    }

    static func valid(_ settings: Settings) -> Bool {
        guard settings.preferredNewEventSourceID.map({ !$0.isEmpty && $0.count <= 1024 }) ?? true else { return false }
        let routes = settings.calendarTopicRoutes ?? [:]
        return routes.count <= 100 && routes.allSatisfy {
            !$0.key.isEmpty && $0.key.count <= 80 && EventCoalescer.normalized($0.key) == $0.key
                && !$0.value.isEmpty && $0.value.count <= 1024
        }
    }

    static func suggestedTopic(title: String, hint: String?) -> String {
        let ignored: Set<String> = ["appuntamento", "uscita", "incontro", "lezione", "ripetizioni", "chiamata", "con", "di", "per", "a", "al", "alle", "il", "la", "un", "una", "domani", "oggi", "prova", "pivot", "impegno"]
        let words = title.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let meaningful = words.filter { !ignored.contains($0.lowercased()) && $0.count >= 3 }
        let proper = meaningful.filter { $0.first?.isUppercase == true }
        let topic = (proper.isEmpty ? meaningful : proper).prefix(3).joined(separator: " ")
        return String((topic.isEmpty ? hint ?? "" : topic).prefix(80))
    }
}

import Foundation
enum WorkoutRoute: Hashable {
    case session(WorkoutDeepLink)
    case day(planID: UUID, dayID: String)
}
struct WorkoutDeepLink: Identifiable, Hashable {
    var id: UUID
    var setID: UUID?
    static func parse(_ url: URL) -> WorkoutDeepLink? {
        guard url.scheme == "pivot", url.host == "workout", url.pathComponents.count == 2,
              let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "set" }?.value
        return .init(id: id, setID: value.flatMap(UUID.init(uuidString:)))
    }
}

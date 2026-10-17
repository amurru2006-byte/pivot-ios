import Foundation

enum ClientPaymentMethod: String, Codable, CaseIterable {
    case unspecified, cash, bankTransfer, card, digital, other
    var label: String {
        switch self {
        case .unspecified: return "Da scegliere"
        case .cash: return "Contanti"
        case .bankTransfer: return "Bonifico"
        case .card: return "Carta"
        case .digital: return "Pagamento digitale"
        case .other: return "Altro"
        }
    }
}

enum ClientTravelMode: String, Codable, CaseIterable {
    case unspecified, walking, transit, car, bicycle, other
    var label: String {
        switch self {
        case .unspecified: return "Da scegliere"
        case .walking: return "A piedi"
        case .transit: return "Mezzi pubblici"
        case .car: return "Auto"
        case .bicycle: return "Bicicletta"
        case .other: return "Altro"
        }
    }
}

// A route is a user estimate, not GPS, a calculated itinerary or permission
// to move an event. Separate outbound/after times avoid assuming symmetry.
struct ClientTravelOrigin: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = ""
    var address: String = ""
    var mode: ClientTravelMode = .unspecified
    var beforeMinutes: Int = 0
    var afterMinutes: Int = 0
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && name.count <= 120 && address.count <= 500
            && (0...240).contains(beforeMinutes) && (0...240).contains(afterMinutes)
    }
}

struct ClientDefaults: Codable, Equatable {
    var paymentMethod: ClientPaymentMethod = .unspecified
    var place: LessonPlace = .undecided
    var address: String = ""
    var origins: [ClientTravelOrigin] = []
    var isValid: Bool {
        address.count <= 500 && origins.count <= 12
            && Set(origins.map(\.id)).count == origins.count
            && Set(origins.map { EventCoalescer.normalized($0.name) }).count == origins.count
            && origins.allSatisfy(\.isValid)
    }
    func proposal(studentName: String, calendarLocation: String) -> LessonLogistics {
        // A current calendar location wins over the profile's usual destination.
        // No origin is chosen automatically, even when there is just one.
        var value = LessonLogistics(studentName: studentName, place: place,
                                    address: calendarLocation.isEmpty ? address : calendarLocation)
        value.paymentMethod = paymentMethod
        return value
    }
    static func applying(_ origin: ClientTravelOrigin, to current: LessonLogistics) -> LessonLogistics {
        var value = current
        value.departure = origin
        value.travelBeforeMinutes = origin.beforeMinutes
        value.travelAfterMinutes = origin.afterMinutes
        value.travelConfirmed = false
        value.confirmedAt = nil
        return value
    }
    func calibrated(using logistics: LessonLogistics) throws -> ClientDefaults {
        guard logistics.travelConfirmed, logistics.confirmedAt != nil,
              let used = logistics.departure, let index = origins.firstIndex(where: { $0.id == used.id }),
              origins[index].name == used.name, origins[index].address == used.address,
              origins[index].mode == used.mode, logistics.address == address,
              logistics.place == place,
              (0...240).contains(logistics.travelBeforeMinutes), (0...240).contains(logistics.travelAfterMinutes) else {
            throw ClientRegistry.Failure.invalid
        }
        var result = self
        result.origins[index].beforeMinutes = logistics.travelBeforeMinutes
        result.origins[index].afterMinutes = logistics.travelAfterMinutes
        return result
    }
}

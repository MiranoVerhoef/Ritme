import Foundation
import SwiftData
import CoreLocation

enum TripKind: String, Codable, CaseIterable, Identifiable {
    case unclassified, work, personal
    var id: String { rawValue }
    var title: String { switch self { case .unclassified: "Review"; case .work: "Work"; case .personal: "Private" } }
    var icon: String { switch self { case .unclassified: "circle.dashed"; case .work: "briefcase.fill"; case .personal: "house.fill" } }
}

struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var speed: Double
    var accuracy: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
}

@Model final class Trip {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var origin: String = "Finding start…"
    var destination: String = "Recording…"
    var vehicleID: UUID?
    var kindRaw: String = TripKind.unclassified.rawValue
    var classificationReason: String = "Choose Work or Private"
    var manuallyClassified: Bool = false
    var classificationUpdatedAt: Date = Date.distantPast
    var distanceMeters: Double = 0
    var routeData: Data = Data()
    var notes: String = ""
    var source: String = "Recorded"
    var isDemo: Bool = false
    init(startedAt: Date = .now, vehicleID: UUID? = nil) { self.startedAt = startedAt; self.vehicleID = vehicleID }
    var kind: TripKind { get { TripKind(rawValue: kindRaw) ?? .unclassified } set { kindRaw = newValue.rawValue } }
    var points: [RoutePoint] {
        get { (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? [] }
        set { routeData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
    var isActive: Bool { endedAt == nil }
    var duration: TimeInterval { max(0, (endedAt ?? .now).timeIntervalSince(startedAt)) }
}

@Model final class Vehicle {
    var id: UUID = UUID()
    var name: String = "My car"
    var plate: String = ""
    var odometer: Double = 0
    init(name: String, plate: String = "") { self.name = name; self.plate = plate }
}

@Model final class SavedPlace {
    var id: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radiusMeters: Double = 150
    var icon: String = "mappin"
    init(name: String, address: String, latitude: Double, longitude: Double, icon: String = "mappin") {
        self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude; self.icon = icon
    }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    func contains(_ point: RoutePoint) -> Bool {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: point.location) <= radiusMeters
    }
}

@Model final class WorkRule {
    var id: UUID = UUID()
    var name: String = "Work schedule"
    var enabled: Bool = true
    var weekdaysData: Data = Data([2, 3, 4, 5, 6])
    var startMinute: Int = 420
    var endMinute: Int = 1140
    var destinationPlaceID: UUID?
    init() {}
    var weekdays: Set<Int> {
        get { Set(weekdaysData.map(Int.init)) }
        set { weekdaysData = Data(newValue.sorted().map(UInt8.init)) }
    }
    var snapshot: RuleSnapshot { .init(enabled: enabled, weekdays: weekdays, startMinute: startMinute, endMinute: endMinute, destinationID: destinationPlaceID) }
}

@Model final class Preferences {
    var key: String = "settings"
    var selectedVehicleID: UUID?
    var holidayUntil: Date?
    var holidayFrom: Date?
    var setupFinished: Bool = false
    init() {}
    var holidayActive: Bool { (holidayUntil ?? .distantPast) > .now }
}

struct RuleSnapshot {
    var enabled: Bool
    var weekdays: Set<Int>
    var startMinute: Int
    var endMinute: Int
    var destinationID: UUID?
}

struct Classification: Equatable {
    var kind: TripKind
    var reason: String
}

enum RuleEngine {
    // Schedule follows departure time; overnight hours belong to the day the shift starts.
    static func classify(start: Date, destinationID: UUID?, holidayUntil: Date?, rules: [RuleSnapshot], calendar: Calendar = .current, holidayFrom: Date? = nil) -> Classification {
        if let holidayUntil, start < holidayUntil, start >= (holidayFrom ?? .distantPast) { return .init(kind: .personal, reason: "Holiday mode · work rules paused") }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: start)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let day = components.weekday ?? 1
        for rule in rules where rule.enabled {
            if let required = rule.destinationID, required != destinationID { continue }
            let overnight = rule.startMinute > rule.endMinute
            let effectiveDay = overnight && minute < rule.endMinute ? (day == 1 ? 7 : day - 1) : day
            let inHours = overnight ? minute >= rule.startMinute || minute < rule.endMinute : minute >= rule.startMinute && minute < rule.endMinute
            if rule.weekdays.contains(effectiveDay), inHours {
                return .init(kind: .work, reason: rule.destinationID == nil ? "Work schedule · departure within working hours" : "Work schedule · arriving at saved workplace")
            }
        }
        return .init(kind: .unclassified, reason: "No matching rule · choose Work or Private")
    }
}

enum RouteFilter {
    static func accepts(_ point: RoutePoint, after previous: RoutePoint?, now: Date = .now) -> Bool {
        guard point.latitude.isFinite, point.longitude.isFinite, abs(point.latitude) <= 90, abs(point.longitude) <= 180,
              point.accuracy >= 0, point.accuracy <= 65, abs(point.timestamp.timeIntervalSince(now)) <= 30 else { return false }
        guard let previous else { return true }
        let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }
        return point.location.distance(from: previous.location) / elapsed <= 75
    }
}

enum Format {
    static func km(_ meters: Double) -> String { (meters / 1000).formatted(.number.precision(.fractionLength(1))) }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    static func hour(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

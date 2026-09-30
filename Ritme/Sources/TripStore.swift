import Foundation
import SwiftData
import Observation
import CoreLocation

@MainActor @Observable final class TripStore {
    let container: ModelContainer
    var trips: [Trip] = []
    var vehicles: [Vehicle] = []
    var places: [SavedPlace] = []
    var rules: [WorkRule] = []
    var preferences: Preferences
    var error: String?
    var revision = 0
    var onChange: (() -> Void)?
    var cloudEnabled: Bool
    var context: ModelContext { container.mainContext }
    var activeTrip: Trip? { trips.first { $0.isActive } }
    var realTrips: [Trip] { trips.filter { !$0.isDemo } }
    var selectedVehicle: Vehicle? { vehicles.first { $0.id == preferences.selectedVehicleID } ?? vehicles.first }

    init(container: ModelContainer, cloudEnabled: Bool = false) throws {
        self.container = container; self.cloudEnabled = cloudEnabled
        let context = container.mainContext
        let settings = try context.fetch(FetchDescriptor<Preferences>())
        if let existing = settings.first { preferences = existing } else {
            preferences = Preferences(); context.insert(preferences); try context.save()
        }
        refresh()
    }
    func refresh() {
        do {
            trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\Trip.startedAt, order: .reverse)]))
            vehicles = try context.fetch(FetchDescriptor<Vehicle>())
            places = try context.fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\SavedPlace.name)]))
            rules = try context.fetch(FetchDescriptor<WorkRule>())
            revision += 1
        } catch { self.error = "Could not load your trips: \(error.localizedDescription)" }
    }
    @discardableResult func save() -> Bool {
        do { try context.save(); error = nil; refresh(); onChange?(); return true }
        catch { self.error = "Your latest changes could not be saved: \(error.localizedDescription)"; return false }
    }
    func vehicleName(for trip: Trip) -> String { vehicles.first { $0.id == trip.vehicleID }?.name ?? "No vehicle" }
    func mark(_ trip: Trip, as kind: TripKind, at date: Date = .now) {
        guard date >= trip.classificationUpdatedAt else { return }
        trip.kind = kind; trip.manuallyClassified = true; trip.classificationUpdatedAt = date
        trip.classificationReason = "Marked \(kind.title.lowercased()) by you"
        save()
    }
    func place(at point: RoutePoint?) -> SavedPlace? {
        guard let point else { return nil }
        return places.filter { $0.contains(point) }.min {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: point.location) < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: point.location)
        }
    }
    func applyRules(to trip: Trip) {
        guard !trip.manuallyClassified else { return }
        let result = RuleEngine.classify(start: trip.startedAt, destinationID: place(at: trip.points.last)?.id,
                                         holidayUntil: preferences.holidayUntil, rules: rules.map(\.snapshot), holidayFrom: preferences.holidayFrom)
        trip.kind = result.kind; trip.classificationReason = result.reason
    }
    func remove(_ trip: Trip) { guard !trip.isActive else { return }; context.delete(trip); save() }
    func addManual(origin: String, destination: String, date: Date, durationMinutes: Double, kilometers: Double, kind: TripKind) {
        let trip = Trip(startedAt: date, vehicleID: selectedVehicle?.id)
        trip.endedAt = date.addingTimeInterval(durationMinutes * 60); trip.origin = origin; trip.destination = destination
        trip.distanceMeters = kilometers * 1000; trip.source = "Manual"
        context.insert(trip); mark(trip, as: kind)
    }
    func deleteDemo() { for trip in trips where trip.isDemo { context.delete(trip) }; save() }
    func loadDemo() {
        guard !trips.contains(where: \.isDemo) else { return }
        let paths: [[(Double, Double)]] = [
            [(52.0907,5.1214),(52.096,5.113),(52.108,5.104),(52.12,5.093),(52.133,5.087)],
            [(52.133,5.087),(52.125,5.103),(52.112,5.12),(52.106,5.141),(52.098,5.15)],
            [(52.098,5.15),(52.095,5.14),(52.09,5.13),(52.0907,5.1214)]
        ]
        let today = Calendar.current.startOfDay(for: .now)
        let definitions: [(String,String,Double,TripKind,TimeInterval,String)] = [
            ("Home", "Office", 18.4, .work, 8*3600+15*60, "Work schedule · arriving at Office"),
            ("Office", "Client meeting", 12.8, .unclassified, 10*3600+30*60, "No matching rule · choose Work or Private"),
            ("Coffee stop", "Home", 6.2, .personal, -3600, "Marked private by you")
        ]
        for (i, item) in definitions.enumerated() {
            let trip = Trip(startedAt: today.addingTimeInterval(item.4)); trip.origin = item.0; trip.destination = item.1
            trip.distanceMeters = item.2 * 1000; trip.kind = item.3; trip.classificationReason = item.5
            trip.endedAt = trip.startedAt.addingTimeInterval(22*60); trip.isDemo = true
            trip.points = paths[i].enumerated().map { j, p in .init(latitude: p.0, longitude: p.1, timestamp: trip.startedAt.addingTimeInterval(Double(j)*330), speed: 12, accuracy: 5) }
            context.insert(trip)
        }
        save()
    }
}

import XCTest
import SwiftData
import CoreLocation
@testable import Ritme

final class RitmeTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDestinationMustMatchAndPassingOfficeDoesNotCount() {
        let office = UUID()
        let rule = RuleSnapshot(enabled: true, weekdays: [2,3,4,5,6], startMinute: 420, endMinute: 1140, destinationID: office)
        let start = date("2026-09-30T08:00:00Z")
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: office, holidayUntil: nil, rules: [rule], calendar: calendar).kind, .work)
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: UUID(), holidayUntil: nil, rules: [rule], calendar: calendar).kind, .unclassified)
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: nil, holidayUntil: nil, rules: [rule], calendar: calendar).kind, .unclassified)
    }
    func testHolidayAndReturnBoundary() {
        let rule = RuleSnapshot(enabled: true, weekdays: [4], startMinute: 0, endMinute: 1440, destinationID: nil)
        let start = date("2026-09-30T08:00:00Z")
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: nil, holidayUntil: start.addingTimeInterval(1), rules: [rule], calendar: calendar).kind, .personal)
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: nil, holidayUntil: start, rules: [rule], calendar: calendar).kind, .work)
        XCTAssertEqual(RuleEngine.classify(start: start, destinationID: nil, holidayUntil: start.addingTimeInterval(100), rules: [rule], calendar: calendar, holidayFrom: start.addingTimeInterval(1)).kind, .work)
    }
    func testOvernightScheduleUsesPreviousWeekday() {
        let rule = RuleSnapshot(enabled: true, weekdays: [3], startMinute: 22*60, endMinute: 6*60, destinationID: nil)
        XCTAssertEqual(RuleEngine.classify(start: date("2026-09-30T02:00:00Z"), destinationID: nil, holidayUntil: nil, rules: [rule], calendar: calendar).kind, .work)
        XCTAssertEqual(RuleEngine.classify(start: date("2026-09-30T06:00:00Z"), destinationID: nil, holidayUntil: nil, rules: [rule], calendar: calendar).kind, .unclassified)
        XCTAssertEqual(RuleEngine.classify(start: date("2026-10-01T02:00:00Z"), destinationID: nil, holidayUntil: nil, rules: [rule], calendar: calendar).kind, .unclassified)
    }
    func testGPSRejectsStaleInaccurateAndImpossibleJumps() {
        let now = Date.now
        let point = RoutePoint(latitude: 52, longitude: 5, timestamp: now, speed: 0, accuracy: 10)
        XCTAssertTrue(RouteFilter.accepts(point, after: nil, now: now))
        var bad = point; bad.accuracy = 100; XCTAssertFalse(RouteFilter.accepts(bad, after: nil, now: now))
        bad = point; bad.timestamp = now.addingTimeInterval(-60); XCTAssertFalse(RouteFilter.accepts(bad, after: nil, now: now))
        bad = point; bad.latitude = 53; bad.timestamp = now.addingTimeInterval(1); XCTAssertFalse(RouteFilter.accepts(bad, after: point, now: now))
        XCTAssertFalse(RouteFilter.accepts(point, after: point, now: now))
    }
    @MainActor func testManualChoiceWinsAndDelayedWatchCannotOverwriteNewerChoice() throws {
        let container = try ModelContainer(for: Trip.self, Vehicle.self, SavedPlace.self, WorkRule.self, Preferences.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = try TripStore(container: container)
        let trip = Trip(); container.mainContext.insert(trip); trip.endedAt = .now
        store.preferences.holidayUntil = Date.now.addingTimeInterval(100)
        let now = Date.now; store.mark(trip, as: .work, at: now)
        store.applyRules(to: trip); XCTAssertEqual(trip.kind, .work)
        store.mark(trip, as: .personal, at: now.addingTimeInterval(-10)); XCTAssertEqual(trip.kind, .work)
        let fetched = try container.mainContext.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(fetched.first?.kind, .work)
    }
    @MainActor func testDemoNeverBecomesRealMileage() throws {
        let container = try ModelContainer(for: Trip.self, Vehicle.self, SavedPlace.self, WorkRule.self, Preferences.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = try TripStore(container: container); store.loadDemo(); store.loadDemo()
        XCTAssertEqual(store.trips.count, 3); XCTAssertTrue(store.realTrips.isEmpty)
        store.deleteDemo(); XCTAssertTrue(store.trips.isEmpty)
    }
    func testCSVAndGPXEscapeUserContent() {
        XCTAssertEqual(TripExport.csvField("=1+1"), "\"'=1+1\"")
        XCTAssertEqual(TripExport.csvField("A, \"B\""), "\"A, \"\"B\"\"\"")
        XCTAssertEqual(TripExport.xml("A&B <C>"), "A&amp;B &lt;C&gt;")
    }
    @MainActor func testRecordingPipelineStoresRouteAndClassifiesArrival() throws {
        let container = try ModelContainer(for: Trip.self, Vehicle.self, SavedPlace.self, WorkRule.self, Preferences.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let store = try TripStore(container: container)
        let office = SavedPlace(name: "Office", address: "Test", latitude: 52.001, longitude: 5)
        let rule = WorkRule(); rule.weekdays = Set(1...7); rule.startMinute = 0; rule.endMinute = 1440; rule.destinationPlaceID = office.id
        container.mainContext.insert(office); container.mainContext.insert(rule)
        let trip = Trip(startedAt: .now.addingTimeInterval(-10)); container.mainContext.insert(trip); store.save()
        let recorder = Recorder(store: store)
        let start = CLLocation(coordinate: .init(latitude: 52, longitude: 5), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now.addingTimeInterval(-10))
        let end = CLLocation(coordinate: .init(latitude: 52.001, longitude: 5), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now)
        recorder.locationManager(CLLocationManager(), didUpdateLocations: [start, end]); recorder.stop()
        XCTAssertEqual(trip.points.count, 2); XCTAssertGreaterThan(trip.distanceMeters, 100)
        XCTAssertFalse(trip.isActive); XCTAssertEqual(trip.destination, "Office"); XCTAssertEqual(trip.kind, .work)
    }
    @MainActor func testDiskPersistenceAfterReopeningContainer() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trips.store")
        let schema = Schema([Trip.self, Vehicle.self, SavedPlace.self, WorkRule.self, Preferences.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let store = try TripStore(container: container)
            store.addManual(origin: "Home", destination: "Office", date: .now.addingTimeInterval(-3600), durationMinutes: 20, kilometers: 18.4, kind: .work)
            XCTAssertNil(store.error)
        }
        let reopened = try ModelContainer(for: schema, configurations: configuration)
        let store = try TripStore(container: reopened)
        XCTAssertEqual(store.trips.count, 1); XCTAssertEqual(store.trips[0].destination, "Office")
        XCTAssertEqual(store.trips[0].distanceMeters, 18400, accuracy: 0.01); XCTAssertEqual(store.trips[0].kind, .work)
    }
}

import Foundation
import CoreLocation
import Observation

@MainActor @Observable final class Recorder: NSObject, @preconcurrency CLLocationManagerDelegate {
    static var shared: Recorder?
    let store: TripStore
    private let manager = CLLocationManager()
    var authorization: CLAuthorizationStatus = .notDetermined
    var awaitingPermission = false
    var status = "Ready when you are"
    var locationError: String?
    init(store: TripStore) {
        self.store = store
        super.init()
        manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10; manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        Self.shared = self
        if store.activeTrip != nil {
            status = "Unfinished trip · resume or finish"
        }
    }
    var allowed: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }
    func requestAlways() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if authorization == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }
    func start(source: String = "Recorded") {
        guard store.activeTrip == nil else { return }
        guard CLLocationManager.locationServicesEnabled() else { locationError = "Location Services are off. Enable them in iPhone Settings."; return }
        guard allowed else {
            if authorization == .notDetermined { awaitingPermission = true; manager.requestWhenInUseAuthorization() }
            else { locationError = "Allow location access in iPhone Settings to record a trip." }
            return
        }
        let trip = Trip(vehicleID: store.selectedVehicle?.id); trip.source = source
        store.context.insert(trip)
        guard store.save() else { store.context.delete(trip); return }
        resume()
    }
    func resume() {
        guard allowed, store.activeTrip != nil else { return }
        manager.allowsBackgroundLocationUpdates = true; manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation(); status = "Recording your route"; locationError = nil
    }
    func stop() {
        guard let trip = store.activeTrip else { return }
        manager.stopUpdatingLocation(); trip.endedAt = .now
        let start = store.place(at: trip.points.first), end = store.place(at: trip.points.last)
        trip.origin = start?.name ?? trip.points.first.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "Unknown start"
        trip.destination = end?.name ?? trip.points.last.map { String(format: "%.4f, %.4f", $0.latitude, $0.longitude) } ?? "Unknown destination"
        store.applyRules(to: trip); store.save(); status = "Trip saved"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if awaitingPermission && allowed { awaitingPermission = false; start() }
        if !allowed && store.activeTrip != nil { manager.stopUpdatingLocation(); status = "Location access lost · finish or enable access" }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let trip = store.activeTrip else { return }
        var points = trip.points
        for location in locations {
            let point = RoutePoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timestamp: location.timestamp, speed: max(0,location.speed), accuracy: location.horizontalAccuracy)
            guard RouteFilter.accepts(point, after: points.last) else { continue }
            if let previous = points.last { trip.distanceMeters += previous.location.distance(from: point.location) }
            points.append(point)
        }
        trip.points = points
        if let first = points.first { trip.origin = store.place(at: first)?.name ?? "Recorded start" }
        store.save()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = "GPS unavailable: \(error.localizedDescription)"; status = "Waiting for GPS"
    }
}

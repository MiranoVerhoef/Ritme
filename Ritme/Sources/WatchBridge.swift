import Foundation
import WatchConnectivity

@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    let store: TripStore
    init(store: TripStore) {
        self.store = store; super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
        store.onChange = { [weak self] in self?.publish() }
    }
    func publish() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var payload: [String: Any] = ["hasTrip": false]
        if let trip = store.realTrips.first {
            payload = ["hasTrip": true, "id": trip.id.uuidString, "origin": trip.origin, "destination": trip.destination, "kind": trip.kindRaw, "active": trip.isActive, "km": Format.km(trip.distanceMeters), "updatedAt": trip.classificationUpdatedAt.timeIntervalSince1970]
        }
        do { try session.updateApplicationContext(payload) } catch { /* Re-publish on next store change or activation. */ }
    }
    private func receive(_ payload: [String: Any]) -> [String: Any] {
        guard let id = payload["id"] as? String, let kind = payload["kind"] as? String, let value = TripKind(rawValue: kind), value != .unclassified,
              let timestamp = payload["timestamp"] as? Double, timestamp.isFinite, timestamp <= Date.now.timeIntervalSince1970 + 60,
              let trip = store.realTrips.first(where: { $0.id.uuidString == id }) else { return ["success": false] }
        store.mark(trip, as: value, at: Date(timeIntervalSince1970: timestamp)); publish()
        return ["success": store.error == nil]
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { Task { @MainActor in self.publish() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            let response = self.receive(userInfo)
            if response["success"] as? Bool == true, let id = userInfo["id"] as? String, let timestamp = userInfo["timestamp"] as? Double {
                session.transferUserInfo(["ackID": id, "ackTimestamp": timestamp])
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in if message["requestSnapshot"] as? Bool == true { self.publish(); replyHandler(["success": true]) } else { replyHandler(self.receive(message)) } }
    }
}

import SwiftUI
import WatchConnectivity
import Observation

@MainActor @Observable final class WatchState: NSObject, WCSessionDelegate {
    var trip: [String: Any] = [:]
    var pending: [[String: Any]] = []
    var status = "Waiting for iPhone"
    private let pendingKey = "ritme.pendingClassifications"
    override init() {
        super.init()
        pending = UserDefaults.standard.array(forKey: pendingKey) as? [[String: Any]] ?? []
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func refresh() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if !session.receivedApplicationContext.isEmpty { update(session.receivedApplicationContext) }
        if session.isReachable { session.sendMessage(["requestSnapshot": true], replyHandler: nil, errorHandler: { _ in }) }
    }
    func update(_ context: [String: Any]) {
        trip = context
        if let id = context["id"] as? String, let updated = context["updatedAt"] as? Double {
            pending.removeAll { ($0["id"] as? String) == id && ($0["timestamp"] as? Double ?? 0) <= updated }
            persist()
        }
        status = pending.isEmpty ? "Updated from iPhone" : "Change queued for iPhone"
    }
    func mark(_ kind: String) {
        guard let id = trip["id"] as? String else { return }
        let payload: [String: Any] = ["id": id, "kind": kind, "timestamp": Date.now.timeIntervalSince1970]
        pending.append(payload); persist(); status = "Change queued for iPhone"
        if WCSession.default.activationState == .activated { send(payload) }
    }
    private func persist() { UserDefaults.standard.set(pending, forKey: pendingKey) }
    private func send(_ payload: [String: Any]) {
        // Background delivery is keyed to a specific trip. Retrying cannot mark a newer trip.
        WCSession.default.transferUserInfo(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: { response in
                Task { @MainActor in
                    guard response["success"] as? Bool == true else { self.status = "Trip unavailable on iPhone"; return }
                    self.pending.removeAll { ($0["id"] as? String) == (payload["id"] as? String) && ($0["timestamp"] as? Double) == (payload["timestamp"] as? Double) }
                    self.persist(); self.status = "Saved on iPhone"
                    if (self.trip["id"] as? String) == (payload["id"] as? String) { self.trip["kind"] = payload["kind"] }
                }
            }, errorHandler: { _ in })
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated else { self.status = "Watch connection unavailable"; return }
            self.refresh(); for payload in self.pending { self.send(payload) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { Task { @MainActor in self.update(applicationContext) } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            guard let id = userInfo["ackID"] as? String, let timestamp = userInfo["ackTimestamp"] as? Double else { return }
            self.pending.removeAll { ($0["id"] as? String) == id && ($0["timestamp"] as? Double) == timestamp }
            self.persist(); self.status = self.pending.isEmpty ? "Saved on iPhone" : "Change queued for iPhone"
        }
    }
}

@main struct RitmeWatchApp: App {
    @State private var state = WatchState()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ritme").font(.title3.bold()).foregroundStyle(.primary)
                    if state.trip["hasTrip"] as? Bool == true {
                        Text(state.trip["active"] as? Bool == true ? "CURRENT TRIP" : "LATEST TRIP").font(.caption2).foregroundStyle(.secondary)
                        Text("\(state.trip["origin"] as? String ?? "") → \(state.trip["destination"] as? String ?? "")").font(.headline)
                        Text("\(state.trip["km"] as? String ?? "0") km").font(.subheadline)
                        Button { state.mark("work") } label: { Label("Work", systemImage: "briefcase.fill").frame(maxWidth: .infinity) }.tint(.blue)
                        Button { state.mark("personal") } label: { Label("Private", systemImage: "house.fill").frame(maxWidth: .infinity) }.tint(.gray)
                        Text("Purpose: \((state.trip["kind"] as? String) == "work" ? "Work" : (state.trip["kind"] as? String) == "personal" ? "Private" : "Review")").font(.caption2)
                    } else { Image(systemName: "car.side").font(.largeTitle); Text("Record a trip on your iPhone to mark it here.").font(.subheadline) }
                    Text(state.status).font(.caption2).foregroundStyle(.secondary)
                    Button("Refresh") { state.refresh() }.font(.caption)
                }.padding(.horizontal, 4)
            }.onAppear { state.refresh() }.onChange(of: phase) { if phase == .active { state.refresh() } }
        }
    }
}

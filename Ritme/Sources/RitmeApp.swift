import SwiftUI
import SwiftData

@main struct RitmeApp: App {
    @State private var store: TripStore?
    @State private var recorder: Recorder?
    @State private var bridge: WatchBridge?
    @State private var startupError: String?
    init() {
        do {
            let schema = Schema([Trip.self, Vehicle.self, SavedPlace.self, WorkRule.self, Preferences.self])
            let cloud = Bundle.main.object(forInfoDictionaryKey: "RitmeCloudEnabled") as? Bool == true
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: cloud ? .automatic : .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let store = try TripStore(container: container, cloudEnabled: cloud)
            if ProcessInfo.processInfo.arguments.contains("--demo") { store.loadDemo() }
            _store = State(initialValue: store)
            _recorder = State(initialValue: Recorder(store: store))
            _bridge = State(initialValue: WatchBridge(store: store))
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    var body: some Scene {
        WindowGroup {
            if let store, let recorder {
                RootView().environment(store).environment(recorder).modelContainer(store.container).tint(Style.accent)
            } else {
                ContentUnavailableView("Your trips couldn't be opened", systemImage: "externaldrive.badge.exclamationmark", description: Text("Recording is paused to protect your data. Restart Ritme and try again.\n\n\(startupError ?? "Unknown storage error")"))
            }
        }
    }
}

struct RootView: View {
    @Environment(TripStore.self) private var store
    @Environment(Recorder.self) private var recorder
    @Environment(\.scenePhase) private var phase
    @State private var onboarding = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Trips", systemImage: "list.bullet", value: 0) { TripsView() }
            Tab("Places", systemImage: "mappin", value: 1) { PlacesView() }
            Tab("Reports", systemImage: "chart.bar", value: 2) { ReportsView() }
            Tab("Settings", systemImage: "gearshape", value: 3) { SettingsView() }
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            onboarding = !store.preferences.setupFinished && !args.contains("--demo")
            if let argument = args.first(where: { $0.hasPrefix("--preview-tab=") }), let value = Int(argument.split(separator: "=").last ?? "0") { selectedTab = value }
        }
        .onChange(of: phase) { if phase == .active { store.refresh() } }
        .sheet(isPresented: $onboarding) { WelcomeView() }
        .alert("Needs attention", isPresented: Binding(get: { store.error != nil || recorder.locationError != nil }, set: { if !$0 { store.error = nil; recorder.locationError = nil } })) {
            Button("OK") { store.error = nil; recorder.locationError = nil }
        } message: { Text(store.error ?? recorder.locationError ?? "") }
    }
}

struct WelcomeView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Welcome to Ritme").font(.title2.weight(.semibold))
                        Text("Record your drives, assign a purpose, and export your mileage.").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section("Getting started") {
                    Label("Add your vehicle in Settings", systemImage: "car.side")
                    Label("Save Home and Office in Places", systemImage: "mappin")
                    Label("Record a trip or configure Shortcuts", systemImage: "record.circle")
                }
                Section {
                    Button("Continue") { finish(demo: false) }
                    Button("Load sample trips") { finish(demo: true) }
                } footer: { Text("Sample trips are excluded from your mileage totals. Data is stored on this iPhone in this beta.") }
            }.navigationTitle("Ritme").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
    private func finish(demo: Bool) { store.preferences.setupFinished = true; if demo { store.loadDemo() }; if store.save() { dismiss() } }
}

import AppIntents

struct StartTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Trip"
    static var description = IntentDescription("Start recording a drive in Ritme. Opens the app in this beta.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        guard let recorder = Recorder.shared else { throw RitmeIntentError.unavailable }
        recorder.start(source: "Shortcut")
        return .result()
    }
}

struct EndTripIntent: AppIntent {
    static var title: LocalizedStringResource = "End Trip"
    static var description = IntentDescription("Finish and save the current recorded trip.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        guard let recorder = Recorder.shared else { throw RitmeIntentError.unavailable }
        recorder.stop(); return .result()
    }
}

enum PurposeIntent: String, AppEnum {
    case work, personal
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trip purpose")
    static var caseDisplayRepresentations: [PurposeIntent: DisplayRepresentation] = [.work: "Work", .personal: "Private"]
}

struct MarkTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Trip"
    static var description = IntentDescription("Mark the current or latest real trip as Work or Private.")
    static var openAppWhenRun = true
    @Parameter(title: "Purpose") var purpose: PurposeIntent
    @MainActor func perform() async throws -> some IntentResult {
        guard let store = Recorder.shared?.store, let trip = store.realTrips.first else { throw RitmeIntentError.noTrip }
        store.mark(trip, as: purpose == .work ? .work : .personal); return .result()
    }
}

enum RitmeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable, noTrip
    var localizedStringResource: LocalizedStringResource { switch self { case .unavailable: "Open Ritme once before using this action."; case .noTrip: "There is no recorded trip to mark yet." } }
}

struct RitmeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTripIntent(), phrases: ["Start a trip in \(.applicationName)"], shortTitle: "Start Trip", systemImageName: "record.circle")
        AppShortcut(intent: EndTripIntent(), phrases: ["End my trip in \(.applicationName)"], shortTitle: "End Trip", systemImageName: "stop.circle")
    }
}

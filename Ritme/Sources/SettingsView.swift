import SwiftUI
import UIKit
import WatchConnectivity

struct SettingsView: View {
    @Environment(TripStore.self) private var store
    @Environment(Recorder.self) private var recorder
    @State private var addVehicle = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Recording") {
                    NavigationLink { AutomationSetupView() } label: { Label { Text("Shortcuts setup") } icon: { Image(systemName: "bolt.fill").foregroundStyle(Style.accent) } }
                    LabeledContent("Location access", value: locationTitle)
                    Button("Allow background location") { recorder.requestAlways() }
                    Button("Open iPhone settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                Section("Vehicles") {
                    ForEach(store.vehicles) { vehicle in
                        NavigationLink { VehicleDetail(vehicle: vehicle) } label: {
                            HStack { Text(vehicle.name); Spacer(); if store.selectedVehicle?.id == vehicle.id { Text("Current").font(.subheadline).foregroundStyle(.secondary) } }
                        }
                    }
                    Button("Add vehicle") { addVehicle = true }
                }
                Section("Classification") {
                    NavigationLink { RulesView() } label: { Label { Text("Work schedules") } icon: { Image(systemName: "calendar").foregroundStyle(Style.accent) } }
                    NavigationLink { HolidayView() } label: { LabeledContent { Text(store.preferences.holidayActive ? "On" : "Off") } label: { Label { Text("Holiday mode") } icon: { Image(systemName: "sun.max.fill").foregroundStyle(.orange) } } }
                }
                Section("Data & devices") {
                    NavigationLink { DataSettingsView() } label: { LabeledContent("Storage", value: store.cloudEnabled ? "iCloud" : "On this iPhone") }
                    NavigationLink { WatchSettingsView() } label: { Label { Text("Apple Watch") } icon: { Image(systemName: "applewatch").foregroundStyle(Style.accent) } }
                }
                Section {
                    Button("Load sample trips") { store.loadDemo() }.disabled(store.trips.contains(where: \.isDemo))
                    if store.trips.contains(where: \.isDemo) { Button("Remove sample trips") { store.deleteDemo() } }
                } header: { Text("Sample data") } footer: { Text("Sample trips are excluded from mileage totals and exports.") }
                Section {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    Link("GitHub", destination: URL(string: "https://github.com/MiranoVerhoef/Ritme")!)
                } header: { Text("Ritme") } footer: { Text("Development beta") }
            }.listSectionSpacing(.custom(12)).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).sheet(isPresented: $addVehicle) { AddVehicleView() }
        }
    }
    private var locationTitle: String {
        switch recorder.authorization { case .authorizedAlways: "Always"; case .authorizedWhenInUse: "While in use"; case .denied, .restricted: "Not allowed"; default: "Not set up" }
    }
}

struct DataSettingsView: View {
    @Environment(TripStore.self) private var store
    var body: some View {
        Form {
            Section {
                LabeledContent("Storage", value: store.cloudEnabled ? "iCloud" : "On this iPhone")
            } footer: {
                Text(store.cloudEnabled ? "iCloud is enabled. Sync progress is not available in this beta." : "Trips are saved locally and work offline. iCloud is not enabled in this beta.")
            }
            Section { Text("Use Reports to export your mileage as CSV or PDF, or recorded routes as GPX.") }
        }.navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchSettingsView: View {
    var body: some View {
        Form {
            Section { LabeledContent("Companion app", value: watchStatus) } footer: { Text("The Watch app marks the current or most recent trip as Work or Private. Changes queue when the iPhone is unavailable.") }
            Section { Text("The AltStore download is for iPhone. Install the Watch companion through a signed Xcode build. Paired-device testing is still required for this beta.").font(.subheadline) }
        }.navigationTitle("Apple Watch").navigationBarTitleDisplayMode(.inline)
    }
    private var watchStatus: String {
        guard WCSession.isSupported() else { return "Unavailable" }
        if !WCSession.default.isPaired { return "No Watch paired" }
        return WCSession.default.isWatchAppInstalled ? "Installed" : "Not installed"
    }
}

struct AddVehicleView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var plate = ""
    var body: some View {
        NavigationStack {
            Form { Section("Your car") { TextField("Name, e.g. Volkswagen Polo", text: $name); TextField("License plate (optional)", text: $plate).textInputAutocapitalization(.characters) } }
                .navigationTitle("Add vehicle").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        let vehicle = Vehicle(name: name.trimmingCharacters(in: .whitespaces), plate: plate)
                        store.context.insert(vehicle); if store.preferences.selectedVehicleID == nil { store.preferences.selectedVehicleID = vehicle.id }
                        if store.save() { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
        }
    }
}

struct VehicleDetail: View {
    @Environment(TripStore.self) private var store
    @Bindable var vehicle: Vehicle
    var body: some View {
        Form {
            Section("Vehicle") { TextField("Name", text: $vehicle.name); TextField("License plate", text: $vehicle.plate) }
            Section("Odometer") { TextField("Dashboard reading (km)", value: $vehicle.odometer, format: .number).keyboardType(.decimalPad); Text("A manually entered reference reading. This beta does not update it automatically or connect to OBD scanners.").font(.caption).foregroundStyle(.secondary) }
            Section { Button("Use for new trips") { store.preferences.selectedVehicleID = vehicle.id; store.save() }.disabled(store.selectedVehicle?.id == vehicle.id) }
        }.navigationTitle(vehicle.name).onDisappear { store.save() }
    }
}

struct RulesView: View {
    @Environment(TripStore.self) private var store
    var body: some View {
        List {
            Section { Text("Rules use the departure day and time, optionally combined with the arrival place. Your manual choice always wins.").font(.subheadline).foregroundStyle(.secondary) }
            Section("Work schedules") {
                ForEach(store.rules) { rule in NavigationLink { RuleDetail(rule: rule) } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(rule.name); Text("\(Format.hour(rule.startMinute))–\(Format.hour(rule.endMinute)) · \(rule.enabled ? "Enabled" : "Paused")").font(.caption).foregroundStyle(.secondary) }
                } }.onDelete { indices in for i in indices { store.context.delete(store.rules[i]) }; store.save() }
                Button("Add work schedule", systemImage: "plus") { store.context.insert(WorkRule()); store.save() }
            }
            Section { Text("Rules classify trips when recording ends. Changes affect future trips, leaving existing classifications unchanged. Unmatched trips stay in Review.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Work rules")
    }
}

struct RuleDetail: View {
    @Environment(TripStore.self) private var store
    @Bindable var rule: WorkRule
    var body: some View {
        Form {
            Section { TextField("Name", text: $rule.name); Toggle("Enabled", isOn: $rule.enabled) }
            Section("Departure days") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { rule.weekdays.contains(day) }, set: { enabled in var days = rule.weekdays; if enabled { days.insert(day) } else { days.remove(day) }; rule.weekdays = days }))
                }
            }
            Section("Departure time") {
                DatePicker("From", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                Text(rule.startMinute > rule.endMinute ? "Overnight schedule: after-midnight trips belong to the previous departure day." : "Trips must depart during these hours.").font(.caption).foregroundStyle(.secondary)
                if rule.startMinute == rule.endMinute { Text("Choose different start and end times. This interval matches no trips.").font(.caption).foregroundStyle(.orange) }
            }
            Section("Arrival place") {
                Picker("Destination", selection: $rule.destinationPlaceID) {
                    Text("Any destination").tag(Optional<UUID>.none)
                    ForEach(store.places) { Text($0.name).tag(Optional($0.id)) }
                }
                Text("Choose Office to avoid classifying every drive during working hours as Work.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Edit rule").onDisappear { store.save() }
    }
    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minute = start ? rule.startMinute : rule.endMinute
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date); let value = (c.hour ?? 0)*60 + (c.minute ?? 0)
            if start { rule.startMinute = value } else { rule.endMinute = value }
        })
    }
}

struct HolidayView: View {
    @Environment(TripStore.self) private var store
    @State private var until = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
    var body: some View {
        Form {
            Section {
                Text("Work rules are paused during holiday mode.").font(.subheadline)
                Text("New trips departing during holiday mode default to Private. You can still mark any trip as Work yourself.").foregroundStyle(.secondary)
            }
            Section {
                DatePicker("Resume work rules", selection: $until, in: Date.now...)
                if store.preferences.holidayActive {
                    Text("Active until \((store.preferences.holidayUntil ?? .now).formatted(date: .abbreviated, time: .shortened))")
                    Button("Update return date") { store.preferences.holidayUntil = until; store.save() }
                    Button("End holiday mode") { store.preferences.holidayUntil = nil; store.preferences.holidayFrom = nil; store.save() }
                } else { Button("Turn on holiday mode") { store.preferences.holidayFrom = .now; store.preferences.holidayUntil = until; store.save() } }
            }
        }.navigationTitle("Holiday mode").onAppear { if let saved = store.preferences.holidayUntil, saved > .now { until = saved } }
    }
}

struct AutomationSetupView: View {
    @Environment(Recorder.self) private var recorder
    @State private var template = "CarPlay"
    var body: some View {
        Form {
            Section {
                Picker("Connection", selection: $template) { Text("CarPlay").tag("CarPlay"); Text("Bluetooth").tag("Bluetooth") }
            } footer: { Text("Create personal automations in Apple Shortcuts. The actions open Ritme in this beta.") }
            Section {
                Button("Allow location access") { recorder.requestAlways() }
            } header: { Text("1. Location access") } footer: { Text("Allow location access, then select Always to record while your iPhone is locked.") }
            Section("2. Start automation") {
                Text("Shortcuts → Automation → +")
                Text("Choose \(template) and your car\(template == "CarPlay" ? ", then Is Connected" : "").")
                Text("Select Run Immediately and add Ritme’s Start Trip action.")
            }
            Section("3. Stop automation") {
                Text(template == "CarPlay" ? "Create another CarPlay automation with Is Disconnected, Run Immediately, and Ritme’s End Trip action." : "Use a disconnection trigger if your iOS version provides one. Otherwise finish the trip in Ritme.")
            }
            Section {
                Button("Open Shortcuts") { if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) } }
            }
            Section {
                Text("While parked, connect and disconnect. Confirm that a trip starts, receives GPS updates, and finishes.")
                LabeledContent("Recording status", value: recorder.status)
            } header: { Text("4. Test the setup") } footer: { Text("Automatic motion detection and stop grouping are not available in this beta.") }
        }.navigationTitle("Shortcuts setup").navigationBarTitleDisplayMode(.inline)
    }
}

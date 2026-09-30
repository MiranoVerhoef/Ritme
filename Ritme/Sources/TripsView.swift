import SwiftUI
import MapKit

struct TripsView: View {
    @Environment(TripStore.self) private var store
    @Environment(Recorder.self) private var recorder
    @State private var filter = "All"
    @State private var search = ""
    @State private var showingSearch = false
    @State private var manual = false
    @State private var confirmStop = false
    private var visible: [Trip] {
        store.trips.filter { trip in
            !trip.isActive && (filter == "All" || trip.kind.title == filter) &&
            (search.isEmpty || "\(trip.origin) \(trip.destination) \(trip.notes)".localizedCaseInsensitiveContains(search))
        }
    }
    private var days: [Date] { Set(visible.map { Calendar.current.startOfDay(for: $0.startedAt) }).sorted(by: >) }
    private var todayTrips: [Trip] { store.realTrips.filter { !$0.isActive && Calendar.current.isDateInToday($0.startedAt) } }
    var body: some View {
        NavigationStack {
            List {
                if showingSearch {
                    Section {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search destinations or notes", text: $search)
                            Button { search = ""; showingSearch = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.borderless).accessibilityLabel("Close search")
                        }
                    }
                }
                Section {
                    recordingStatus
                    HStack(spacing: 24) {
                        total("Today", meters: todayTrips.reduce(0) { $0 + $1.distanceMeters })
                        Divider()
                        total("Work", meters: todayTrips.filter { $0.kind == .work }.reduce(0) { $0 + $1.distanceMeters })
                    }.padding(.vertical, 4)
                }
                if store.preferences.holidayActive {
                    Section {
                        Label("Holiday mode", systemImage: "sun.max")
                        Text("Work rules resume \((store.preferences.holidayUntil ?? .now).formatted(date: .abbreviated, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Purpose", selection: $filter) {
                        ForEach(["All", "Review", "Work", "Private"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                } footer: {
                    if store.trips.contains(where: \.isDemo) {
                        HStack {
                            Text("Sample data · excluded from totals")
                            Spacer()
                            Button("Remove") { store.deleteDemo() }.buttonStyle(.borderless)
                        }.font(.caption)
                    }
                }
                if visible.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(filter == "All" ? "No trips yet" : "No \(filter.lowercased()) trips").font(.headline)
                            Text(filter == "All" ? "Start recording or add a trip with the + button." : "Trips with this purpose will appear here.").font(.subheadline).foregroundStyle(.secondary)
                            if store.trips.isEmpty { Button("Load sample trips") { store.loadDemo() }.padding(.top, 4) }
                        }.padding(.vertical, 12)
                    }
                }
                ForEach(days, id: \.self) { day in
                    Section {
                        ForEach(visible.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }) { trip in
                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink { TripDetailView(trip: trip) } label: { TripSummary(trip: trip) }
                                if trip.kind == .unclassified { KindButtons(selected: trip.kind) { store.mark(trip, as: $0) } }
                            }.padding(.vertical, 4)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button("Work") { store.mark(trip, as: .work) }.tint(Style.accent)
                                    Button("Private") { store.mark(trip, as: .personal) }.tint(.gray)
                                }
                        }
                    } header: { Text(dayTitle(day)).textCase(nil) }
                }
            }
            .listStyle(.insetGrouped).navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showingSearch.toggle(); if !showingSearch { search = "" } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search trips") }
                ToolbarItem(placement: .topBarTrailing) { Button { manual = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a manual trip") }
            }
            .sheet(isPresented: $manual) { ManualTripView() }
            .confirmationDialog("Finish this trip?", isPresented: $confirmStop, titleVisibility: .visible) { Button("Finish and save") { recorder.stop() } }
        }
    }
    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(store.activeTrip == nil ? Color.secondary : Style.accent).frame(width: 7, height: 7).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.activeTrip == nil ? "Not recording" : "Trip in progress").font(.subheadline.weight(.semibold))
                    Text(store.selectedVehicle?.name ?? "No vehicle selected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.activeTrip == nil {
                    Button("Start") { recorder.start() }.buttonStyle(.bordered).accessibilityLabel("Start recording a trip").accessibilityIdentifier("startTrip")
                } else {
                    Button("Finish") { confirmStop = true }.buttonStyle(.bordered).accessibilityLabel("Finish recording this trip")
                }
            }
            if let trip = store.activeTrip {
                HStack {
                    Text("\(Format.km(trip.distanceMeters)) km").monospacedDigit()
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { _ in Text(Format.duration(trip.duration)).monospacedDigit() }
                }.font(.subheadline)
                HStack {
                    Text(recorder.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Resume GPS") { recorder.resume() }.font(.caption).buttonStyle(.borderless)
                }
            }
        }.padding(.vertical, 3)
    }
    private func total(_ title: String, meters: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Format.km(meters)) km").font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.day().month(.wide).year())
    }
}

struct TripSummary: View {
    var trip: Trip
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.startedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if trip.isDemo { Text("Sample").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                KindBadge(kind: trip.kind)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.origin).font(.subheadline).foregroundStyle(.secondary)
                    Text(trip.destination).font(.body.weight(.medium))
                }.lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Format.km(trip.distanceMeters)) km").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(Format.duration(trip.duration)).font(.caption).foregroundStyle(.secondary)
                }.fixedSize(horizontal: true, vertical: false)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct TripDetailView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    @State private var deleting = false
    var body: some View {
        List {
            if !trip.points.isEmpty {
                Section {
                    Map {
                        MapPolyline(coordinates: trip.points.map(\.coordinate)).stroke(Style.accent, lineWidth: 4)
                        if let first = trip.points.first { Marker(trip.origin, systemImage: "circle", coordinate: first.coordinate).tint(.gray) }
                        if let last = trip.points.last { Marker(trip.destination, coordinate: last.coordinate).tint(Style.accent) }
                    }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .frame(height: 220).listRowInsets(EdgeInsets())
                }
            }
            Section("Route") {
                LabeledContent("From", value: trip.origin)
                LabeledContent("To", value: trip.destination)
                LabeledContent("Distance", value: "\(Format.km(trip.distanceMeters)) km")
                LabeledContent("Duration", value: Format.duration(trip.duration))
                if trip.points.isEmpty { Text(trip.source == "Manual" ? "Distance entered manually. No recorded route." : "No usable GPS points were recorded.").font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                KindButtons(selected: trip.kind) { store.mark(trip, as: $0) }
            } header: { Text("Purpose") } footer: { Text(trip.classificationReason) }
            Section("Details") {
                LabeledContent("Vehicle", value: store.vehicleName(for: trip))
                LabeledContent("Source", value: trip.isDemo ? "Sample data" : trip.source)
                LabeledContent("Started", value: trip.startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Notes") {
                TextField("Client or trip purpose", text: $trip.notes, axis: .vertical).lineLimit(3...6).onChange(of: trip.notes) { store.save() }
            }
            Section { Button("Delete trip", role: .destructive) { deleting = true } }
        }.navigationTitle("Trip details").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this trip permanently?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete trip", role: .destructive) { store.remove(trip); dismiss() } }
    }
}

struct ManualTripView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var origin = ""
    @State private var destination = ""
    @State private var date = Date.now.addingTimeInterval(-30 * 60)
    @State private var kilometers = 0.0
    @State private var minutes = 20.0
    @State private var kind = TripKind.work
    var body: some View {
        NavigationStack {
            Form {
                Section("Route") { TextField("From", text: $origin); TextField("To", text: $destination) }
                Section("Trip") {
                    DatePicker("Departure", selection: $date, in: ...Date.now)
                    LabeledContent("Distance (km)") { TextField("0", value: $kilometers, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Stepper("Duration: \(Int(minutes)) minutes", value: $minutes, in: 1...1440, step: 5)
                    Picker("Purpose", selection: $kind) { ForEach(TripKind.allCases) { Text($0.title).tag($0) } }
                }
                Section { Text("Manual mileage is entered by you; no GPS route is created.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Add a trip").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            store.addManual(origin: origin.trimmingCharacters(in: .whitespaces), destination: destination.trimmingCharacters(in: .whitespaces), date: date, durationMinutes: minutes, kilometers: kilometers, kind: kind)
                            if store.error == nil { dismiss() }
                        }.disabled(origin.trimmingCharacters(in: .whitespaces).isEmpty || destination.trimmingCharacters(in: .whitespaces).isEmpty || !kilometers.isFinite || kilometers <= 0 || date.addingTimeInterval(minutes*60) > .now)
                    }
                }
        }
    }
}

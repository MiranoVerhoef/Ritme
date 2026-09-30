import SwiftUI
import MapKit

struct TripsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(TripStore.self) private var store
    @Environment(Recorder.self) private var recorder
    @State private var filter = "All"
    @State private var search = ""
    @State private var showingSearch = false
    @State private var manual = false
    @State private var addVehicle = false
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
                    VStack(alignment: .leading, spacing: 8) {
                        recordingStatus
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                total("Today", meters: todayTrips.reduce(0) { $0 + $1.distanceMeters }).fixedSize()
                                Spacer(minLength: 0)
                                recordingIndicator.fixedSize()
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                total("Today", meters: todayTrips.reduce(0) { $0 + $1.distanceMeters })
                                recordingIndicator
                            }
                        }
                    }.padding(.vertical, 2)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                        .listRowBackground(Style.accent.opacity(0.07))
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
                            VStack(alignment: .leading, spacing: 4) {
                                NavigationLink { TripDetailView(trip: trip) } label: { TripSummary(trip: trip, vehicle: store.vehicleName(for: trip), showRoute: trip.id == visible.first?.id) }
                                if trip.kind == .unclassified { KindButtons(selected: trip.kind) { store.mark(trip, as: $0) } }
                            }.listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 12))
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button("Work") { store.mark(trip, as: .work) }.tint(Style.accent)
                                    Button("Private") { store.mark(trip, as: .personal) }.tint(.gray)
                                }
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(day)).font(.caption.weight(.semibold))
                            Spacer()
                            let dayTrips = visible.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: day) }
                            Text(daySummary(dayTrips))
                                .font(.caption2).monospacedDigit()
                        }.textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped).listSectionSpacing(.custom(12))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Ritme").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showingSearch.toggle(); if !showingSearch { search = "" } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search trips") }
                ToolbarItem(placement: .topBarTrailing) { Button { manual = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a manual trip") }
            }
            .sheet(isPresented: $manual) { ManualTripView() }
            .sheet(isPresented: $addVehicle) { AddVehicleView() }
            .confirmationDialog("Finish this trip?", isPresented: $confirmStop, titleVisibility: .visible) { Button("Finish and save") { recorder.stop() } }
        }
    }
    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "car.fill").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Style.accent).frame(width: 34, height: 34)
                    .background(Style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.activeTrip == nil ? "Current vehicle" : "Trip in progress").font(.caption2).foregroundStyle(.secondary)
                    if let active = store.activeTrip {
                        Text(store.vehicleName(for: active)).font(.subheadline.weight(.semibold))
                    } else if let vehicle = store.selectedVehicle {
                        Menu {
                            ForEach(store.vehicles) { vehicle in
                                Button {
                                    store.preferences.selectedVehicleID = vehicle.id; store.save()
                                } label: {
                                    if vehicle.id == store.selectedVehicle?.id { Label(vehicle.name, systemImage: "checkmark") }
                                    else { Text(vehicle.name) }
                                }
                            }
                            Button("Add vehicle", systemImage: "plus") { addVehicle = true }
                        } label: {
                            HStack(spacing: 5) {
                                Text(vehicle.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Style.accent)
                            }.frame(minHeight: 28)
                        }.buttonStyle(.borderless).accessibilityLabel("Select vehicle, current vehicle \(vehicle.name)")
                    } else {
                        Button("Add your car") { addVehicle = true }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                    }
                }
                Spacer(minLength: 4)
                if store.activeTrip == nil {
                    Button { recorder.start() } label: { Label("Start", systemImage: "play.fill").font(.caption.weight(.semibold)).frame(minHeight: 32) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .accessibilityLabel("Start recording a trip").accessibilityIdentifier("startTrip")
                } else {
                    Button("Finish") { confirmStop = true }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                        .buttonStyle(.borderedProminent).controlSize(.small).accessibilityLabel("Finish recording this trip")
                }
            }
            if let trip = store.activeTrip {
                HStack {
                    Text("\(Format.km(trip.distanceMeters)) km").font(.headline).monospacedDigit()
                    TimelineView(.periodic(from: .now, by: 60)) { _ in Text(Format.duration(trip.duration)).monospacedDigit().font(.caption) }
                    Spacer()
                    Button("Resume GPS") { recorder.resume() }.font(.caption).buttonStyle(.borderless).frame(minHeight: 44)
                }
                Text(recorder.status).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var recordingIndicator: some View {
        HStack(spacing: 5) {
            Circle().fill(store.activeTrip == nil ? Color.secondary : .green).frame(width: 5, height: 5)
            Text(store.activeTrip == nil ? "Not recording" : "Recording").font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private func total(_ title: String, meters: Double) -> some View {
        (Text(title + " ").foregroundColor(.secondary)
         + Text("\(Format.km(meters)) km").bold()
         + Text(" · Work \(Format.km(todayTrips.filter { $0.kind == .work }.reduce(0) { $0 + $1.distanceMeters })) km").foregroundColor(.secondary))
            .font(.caption2).monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
    private func daySummary(_ trips: [Trip]) -> String {
        if trips.allSatisfy(\.isDemo) { return "\(trips.count) sample \(trips.count == 1 ? "trip" : "trips")" }
        let real = trips.filter { !$0.isDemo }
        return "\(real.count) \(real.count == 1 ? "trip" : "trips") · \(Format.km(real.reduce(0) { $0 + $1.distanceMeters })) km"
    }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.day().month(.wide).year())
    }
}

struct TripSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var trip: Trip
    var vehicle = "No vehicle"
    var showRoute = false
    private var previewRect: MKMapRect {
        let rect = trip.points.map { point in
            let position = MKMapPoint(point.coordinate)
            return MKMapRect(x: position.x, y: position.y, width: 1, height: 1)
        }.reduce(MKMapRect.null) { $0.union($1) }
        return rect.insetBy(dx: -max(rect.size.width * 0.2, 500), dy: -max(rect.size.height * 0.2, 500))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    timeRange
                    distance
                }
            } else {
                HStack(spacing: 5) { timeRange; Spacer(minLength: 4); distance }
            }
            HStack(alignment: .center, spacing: 10) {
                RouteStops(origin: trip.origin, destination: trip.destination, color: Style.color(trip.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showRoute && !trip.points.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                Map(initialPosition: .rect(previewRect)) {
                    MapPolyline(coordinates: trip.points.map(\.coordinate)).stroke(Style.accent, lineWidth: 3)
                    if let first = trip.points.first { Annotation("", coordinate: first.coordinate) { Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().stroke(Style.accent, lineWidth: 2)) } }
                    if let last = trip.points.last { Annotation("", coordinate: last.coordinate) { Circle().fill(Style.accent).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)) } }
                }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControlVisibility(.hidden).frame(width: 76, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8)).allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            }
            HStack(spacing: 8) {
                KindBadge(kind: trip.kind)
                Text(Format.duration(trip.duration)).monospacedDigit()
                if vehicle != "No vehicle" { Label(vehicle, systemImage: "car.fill").lineLimit(1) }
                Spacer(minLength: 0)
                Text(trip.isDemo ? "Sample" : trip.source == "Manual" ? "Manual" : "GPS").font(.caption2)
            }.font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private var timeRange: some View {
        Text(trip.startedAt.formatted(date: .omitted, time: .shortened)
             + (trip.endedAt.map { " – " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
             + (trip.isDemo ? " · Sample" : ""))
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
    }
    private var distance: some View {
        Text("\(Format.km(trip.distanceMeters)) km")
            .font(.subheadline.weight(.semibold)).foregroundStyle(Style.accent).monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
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
                RouteStops(origin: trip.origin, destination: trip.destination, color: Style.color(trip.kind))
                    .padding(.vertical, 4)
                HStack(spacing: 16) {
                    metric("Distance", value: "\(Format.km(trip.distanceMeters)) km")
                    metric("Duration", value: Format.duration(trip.duration))
                    metric("GPS points", value: "\(trip.points.count)")
                }.padding(.vertical, 2)
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
        }.listSectionSpacing(.custom(12)).navigationTitle("Trip details").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this trip permanently?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete trip", role: .destructive) { store.remove(trip); dismiss() } }
    }
    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
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

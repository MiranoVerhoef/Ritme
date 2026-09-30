import SwiftUI
import MapKit

struct TripsView: View {
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
                    VStack(alignment: .leading, spacing: 16) {
                        recordingStatus
                        Divider()
                        HStack(spacing: 24) {
                            total("Today", meters: todayTrips.reduce(0) { $0 + $1.distanceMeters })
                            total("Work today", meters: todayTrips.filter { $0.kind == .work }.reduce(0) { $0 + $1.distanceMeters })
                        }
                    }.padding(.vertical, 6)
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
                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink { TripDetailView(trip: trip) } label: { TripSummary(trip: trip, showRoute: trip.id == visible.first?.id) }
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
            .sheet(isPresented: $addVehicle) { AddVehicleView() }
            .confirmationDialog("Finish this trip?", isPresented: $confirmStop, titleVisibility: .visible) { Button("Finish and save") { recorder.stop() } }
        }
    }
    private var recordingStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PlaceSymbol(symbol: "car.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.activeTrip == nil ? "CURRENT VEHICLE" : "RECORDING")
                        .font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                    if let active = store.activeTrip {
                        Text(store.vehicleName(for: active)).font(.headline)
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
                                Text(vehicle.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(Style.accent)
                            }
                        }
                        .buttonStyle(.borderless).accessibilityLabel("Select vehicle, current vehicle \(vehicle.name)")
                    } else {
                        Button("Add your car") { addVehicle = true }.font(.headline).buttonStyle(.borderless)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(store.activeTrip == nil ? Color.secondary : Color.green).frame(width: 6, height: 6)
                    Text(store.activeTrip == nil ? "Not recording" : "Trip in progress").font(.subheadline).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
                Spacer()
                if store.activeTrip == nil {
                    Button { recorder.start() } label: { Label("Start trip", systemImage: "play.fill").font(.subheadline.weight(.semibold)) }
                        .buttonStyle(.borderedProminent).accessibilityLabel("Start recording a trip").accessibilityIdentifier("startTrip")
                } else {
                    Button("Finish trip") { confirmStop = true }.buttonStyle(.borderedProminent).accessibilityLabel("Finish recording this trip")
                }
            }
            if let trip = store.activeTrip {
                HStack {
                    Text("\(Format.km(trip.distanceMeters)) km").monospacedDigit()
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 60)) { _ in Text(Format.duration(trip.duration)).monospacedDigit() }
                }.font(.title3.weight(.semibold))
                HStack {
                    Text(recorder.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Resume GPS") { recorder.resume() }.font(.caption).buttonStyle(.borderless)
                }
            }
        }
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
    var showRoute = false
    private var previewRect: MKMapRect {
        let rect = trip.points.map { point in
            let position = MKMapPoint(point.coordinate)
            return MKMapRect(x: position.x, y: position.y, width: 1, height: 1)
        }.reduce(MKMapRect.null) { $0.union($1) }
        return rect.insetBy(dx: -max(rect.size.width * 0.2, 500), dy: -max(rect.size.height * 0.2, 500))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.startedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                if trip.isDemo { Text("Sample").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                KindBadge(kind: trip.kind)
            }
            HStack(alignment: .top, spacing: 12) {
                RouteStops(origin: trip.origin, destination: trip.destination, color: Style.color(trip.kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Format.km(trip.distanceMeters)) km").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(Format.duration(trip.duration)).font(.caption).foregroundStyle(.secondary)
                }.fixedSize(horizontal: true, vertical: false)
            }
            if showRoute && !trip.points.isEmpty {
                Map(initialPosition: .rect(previewRect)) {
                    MapPolyline(coordinates: trip.points.map(\.coordinate)).stroke(Style.accent, lineWidth: 3)
                    if let first = trip.points.first { Annotation("", coordinate: first.coordinate) { Circle().fill(.white).frame(width: 9, height: 9).overlay(Circle().stroke(Style.accent, lineWidth: 2)) } }
                    if let last = trip.points.last { Annotation("", coordinate: last.coordinate) { Circle().fill(Style.accent).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)) } }
                }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .mapControlVisibility(.hidden).frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).allowsHitTesting(false)
                    .accessibilityHidden(true)
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

import SwiftUI
import MapKit

struct PlacesView: View {
    @Environment(TripStore.self) private var store
    @State private var adding = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.places.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                PlaceSymbol(symbol: "house.fill", color: Style.color(.personal))
                                PlaceSymbol(symbol: "building.2.fill")
                                PlaceSymbol(symbol: "mappin", color: .orange)
                            }
                            Text("Your regular destinations").font(.headline)
                            Text("Add Home, Office, or a regular destination.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Add place") { adding = true }.padding(.top, 4)
                        }.padding(.vertical, 12)
                    }
                    ForEach(store.places) { place in
                        NavigationLink { PlaceDetail(place: place) } label: {
                            HStack(spacing: 12) {
                                PlaceSymbol(symbol: place.icon, color: place.icon == "house.fill" ? Style.color(.personal) : Style.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text("Saved places identify trip destinations and can be used in work rules. Nearby parking is included within each place’s recognition radius.")
                }
            }.listSectionSpacing(.custom(12)).navigationTitle("Places").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add place") } }
                .sheet(isPresented: $adding) { AddPlaceView() }
        }
    }
}

struct AddPlaceView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var name = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: MKMapItem?
    @State private var searching = false
    @State private var searchError: String?
    @State private var icon = "house.fill"
    var body: some View {
        NavigationStack {
            Form {
                Section("What do you call this place?") {
                    TextField("Home, Office, or a client", text: $name)
                    Picker("Icon", selection: $icon) { Text("Home").tag("house.fill"); Text("Office").tag("building.2.fill"); Text("Other").tag("mappin") }.pickerStyle(.segmented)
                }
                Section("Find the address") {
                    TextField("Search an address or place", text: $query).onSubmit { search() }
                    Button { search() } label: { HStack { Text("Search places"); Spacer(); if searching { ProgressView() } else { Image(systemName: "magnifyingglass") } } }.disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let searchError { Text(searchError).foregroundStyle(.red).font(.caption) }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button { selected = item; if name.isEmpty { name = item.name ?? "Place" } } label: {
                            HStack { VStack(alignment: .leading) { Text(item.name ?? "Place"); Text(item.address?.fullAddress ?? "").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selected === item { Image(systemName: "checkmark.circle.fill") } }
                        }
                    }
                }
                if let selected {
                    Section("Selected location") {
                        Map(initialPosition: .region(.init(center: selected.location.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) { Marker(name, coordinate: selected.location.coordinate) }.frame(height: 180)
                        Text("Recognition starts with a 150 m radius. You can adjust it afterward for nearby parking.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("New place").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let selected else { return }
                        let c = selected.location.coordinate
                        store.context.insert(SavedPlace(name: name.trimmingCharacters(in: .whitespaces), address: selected.address?.fullAddress ?? query, latitude: c.latitude, longitude: c.longitude, icon: icon))
                        if store.save() { dismiss() }
                    }.disabled(selected == nil || name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
        }
    }
    private func search() {
        searching = true; searchError = nil; selected = nil
        Task {
            do { let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query; results = try await MKLocalSearch(request: request).start().mapItems; if results.isEmpty { searchError = "No places found. Try a more specific address." } }
            catch { searchError = "Couldn't search places. Check your connection and try again." }
            searching = false
        }
    }
}

struct PlaceDetail: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var place: SavedPlace
    @State private var deleting = false
    var body: some View {
        Form {
            Section { Map(initialPosition: .region(.init(center: place.coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) { Marker(place.name, coordinate: place.coordinate); MapCircle(center: place.coordinate, radius: place.radiusMeters).foregroundStyle(Style.accent.opacity(0.12)) }.frame(height: 250) }
            Section("Place") { TextField("Name", text: $place.name); Text(place.address).foregroundStyle(.secondary) }
            Section("Nearby parking") { Slider(value: $place.radiusMeters, in: 50...500, step: 25); Text("Recognize destinations within \(Int(place.radiusMeters)) metres.").font(.caption) }
            Section { Button("Delete place", role: .destructive) { deleting = true } }
        }.navigationTitle(place.name).navigationBarTitleDisplayMode(.inline).onDisappear { store.save() }
            .confirmationDialog("Delete this place and its destination rules?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete place", role: .destructive) {
                    for rule in store.rules where rule.destinationPlaceID == place.id { store.context.delete(rule) }
                    store.context.delete(place); store.save(); dismiss()
                }
            }
    }
}

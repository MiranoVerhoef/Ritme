import SwiftUI
import UIKit

enum ExportFormat: String, CaseIterable { case csv = "CSV", pdf = "PDF", gpx = "GPX" }

enum TripExport {
    static func csvField(_ value: String) -> String {
        // Prevent spreadsheet software interpreting user input as a formula.
        let safe = ["=", "+", "-", "@", "\t", "\r", "\n"].contains(where: value.hasPrefix) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    static func csv(trips: [Trip], vehicle: (Trip) -> String) -> String {
        let iso = ISO8601DateFormatter()
        let rows = trips.map { trip in
            [iso.string(from: trip.startedAt), trip.endedAt.map(iso.string) ?? "", trip.origin, trip.destination,
             String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), trip.distanceMeters / 1000), trip.kind.title, vehicle(trip), trip.notes, trip.source].map(csvField).joined(separator: ",")
        }
        return (["Start,End,From,To,Distance (km),Purpose,Vehicle,Notes,Source"] + rows).joined(separator: "\r\n")
    }
    static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    static func gpx(trips: [Trip]) -> String {
        let iso = ISO8601DateFormatter()
        let tracks = trips.filter { !$0.points.isEmpty }.map { trip in
            let points = trip.points.map { "<trkpt lat=\"\($0.latitude)\" lon=\"\($0.longitude)\"><time>\(iso.string(from: $0.timestamp))</time></trkpt>" }.joined(separator: "\n")
            return "<trk><name>\(xml(trip.origin + " → " + trip.destination))</name><trkseg>\(points)</trkseg></trk>"
        }.joined(separator: "\n")
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"Ritme\" xmlns=\"http://www.topografix.com/GPX/1/1\">\(tracks)</gpx>"
    }
    static func pdf(trips: [Trip], vehicle: (Trip) -> String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var page = 0
            func text(_ value: String, x: CGFloat = 40, y: CGFloat, size: CGFloat = 11, bold: Bool = false, width: CGFloat = 515) {
                (value as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 60), withAttributes: [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            func newPage() {
                context.beginPage(); page += 1; y = 110
                text("Ritme · Mileage report", y: 36, size: 24, bold: true)
                text("\(trips.count) trips · \(Format.km(trips.reduce(0) { $0 + $1.distanceMeters })) km · Generated \(Date.now.formatted(date: .abbreviated, time: .omitted))", y: 74)
                text("Page \(page) · Distances may be recorded by GPS or entered manually.", y: 800, size: 9)
            }
            newPage()
            for trip in trips {
                if y > 685 { newPage() }
                text("\(trip.origin) → \(trip.destination)", y: y, size: 13, bold: true)
                text("\(trip.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Format.km(trip.distanceMeters)) km · \(trip.kind.title) · \(vehicle(trip)) · \(trip.source)", y: y + 38, size: 10)
                let note = trip.notes.isEmpty ? trip.classificationReason : String(trip.notes.prefix(140))
                text(note, y: y + 58, size: 10)
                context.cgContext.setStrokeColor(UIColor.lightGray.cgColor); context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: 40, y: y + 100)); context.cgContext.addLine(to: CGPoint(x: 555, y: y + 100)); context.cgContext.strokePath()
                y += 116
            }
        }
    }
}

struct ReportsView: View {
    @Environment(TripStore.self) private var store
    @State private var period = "This month"
    @State private var purpose = "All"
    @State private var format = ExportFormat.csv
    @State private var exportURL: URL?
    @State private var exportError: String?
    var trips: [Trip] {
        let now = Date.now; let cal = Calendar.current
        let start = period == "This month" ? cal.dateInterval(of: .month, for: now)?.start : period == "This year" ? cal.dateInterval(of: .year, for: now)?.start : nil
        return store.realTrips.filter { !$0.isActive && $0.startedAt <= now && (start == nil || $0.startedAt >= start!) && (purpose == "All" || $0.kind.title == purpose) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $period) { ForEach(["This month", "This year", "All time"], id: \.self) { Text($0) } }
                    Picker("Purpose", selection: $purpose) { ForEach(["All", "Work", "Private", "Review"], id: \.self) { Text($0) } }
                }
                Section("Mileage") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total distance").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(Format.km(trips.reduce(0) { $0 + $1.distanceMeters })) km").font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Style.accent)
                        }
                        Spacer()
                        Text("\(trips.count) trips").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    let distance = trips.reduce(0) { $0 + $1.distanceMeters }
                    if distance > 0 {
                        GeometryReader { geometry in
                            HStack(spacing: 2) {
                                ForEach(TripKind.allCases) { kind in
                                    let fraction = trips.filter { $0.kind == kind }.reduce(0) { $0 + $1.distanceMeters } / distance
                                    if fraction > 0 {
                                        RoundedRectangle(cornerRadius: 3).fill(Style.color(kind))
                                            .frame(width: max(0, geometry.size.width - 4) * fraction)
                                    }
                                }
                            }
                        }.frame(height: 9).accessibilityHidden(true)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(TripKind.allCases) { kind in
                        HStack {
                            KindBadge(kind: kind)
                            Spacer()
                            Text("\(Format.km(trips.filter { $0.kind == kind }.reduce(0) { $0 + $1.distanceMeters })) km")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Picker("File format", selection: $format) { ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Button("Create \(format.rawValue) export") { export() }
                        .disabled(trips.isEmpty || (format == .gpx && !trips.contains { !$0.points.isEmpty }))
                    if let exportURL { ShareLink(item: exportURL) { Label("Share \(format.rawValue)", systemImage: "square.and.arrow.up") } }
                    if let exportError { Text(exportError).font(.footnote).foregroundStyle(.red) }
                } header: { Text("Export") } footer: {
                    Text(format == .gpx ? "Recorded routes only. Manual trips have no GPS track." : format == .pdf ? "Dates, routes, distances, purposes, and vehicles in a printable report." : "Trip details and notes for spreadsheet applications.")
                }
                if trips.contains(where: { $0.kind == .unclassified }) {
                    Section { Label("Some trips need review", systemImage: "exclamationmark.circle").foregroundStyle(.secondary) } footer: { Text("Assign a purpose in Trips before submitting your mileage report.") }
                }
                if store.trips.contains(where: \.isDemo) {
                    Section { Text("Sample trips are excluded from reports and exports.").font(.footnote).foregroundStyle(.secondary) }
                }
            }.listSectionSpacing(.custom(12)).navigationTitle("Reports").navigationBarTitleDisplayMode(.inline)
                .onChange(of: period) { exportURL = nil }.onChange(of: purpose) { exportURL = nil }.onChange(of: format) { exportURL = nil }
                .onChange(of: store.revision) { exportURL = nil }
        }
    }
    private func export() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ritme-\(UUID().uuidString.prefix(8)).\(format.rawValue.lowercased())")
            let data: Data
            switch format { case .csv: data = Data(TripExport.csv(trips: trips, vehicle: store.vehicleName).utf8); case .gpx: data = Data(TripExport.gpx(trips: trips).utf8); case .pdf: data = TripExport.pdf(trips: trips, vehicle: store.vehicleName) }
            try data.write(to: url, options: .atomic); exportURL = url; exportError = nil
        } catch { exportError = "Couldn't prepare the export: \(error.localizedDescription)" }
    }
}

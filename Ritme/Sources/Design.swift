import SwiftUI

enum Style {
    static let accent = Color(uiColor: .systemBlue)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static func color(_ kind: TripKind) -> Color {
        switch kind {
        case .work: Color(uiColor: .systemBlue)
        case .personal: Color(uiColor: .systemTeal)
        case .unclassified: Color(uiColor: .systemOrange)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct KindBadge: View {
    var kind: TripKind
    var body: some View {
        Label(kind.title, systemImage: kind.icon).font(.caption.weight(.medium))
            .foregroundStyle(Style.color(kind))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Style.color(kind).opacity(0.10), in: Capsule())
    }
}

struct SectionLabel: View {
    var title: String
    var trailing: String = ""
    var body: some View {
        HStack { Text(title).font(.headline); Spacer(); Text(trailing).font(.caption).foregroundStyle(.secondary) }
            .padding(.horizontal, 4)
    }
}

struct KindButtons: View {
    var selected: TripKind
    var action: (TripKind) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach([TripKind.work, .personal]) { kind in
                Button { action(kind) } label: {
                    HStack(spacing: 6) {
                        Text(kind.title)
                        if selected == kind { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                    }.font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 30)
                }.buttonStyle(.bordered).tint(Style.color(kind))
            }
        }
    }
}

struct PlaceSymbol: View {
    var symbol: String
    var color: Color = Style.accent
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .medium))
            .foregroundStyle(color).frame(width: 42, height: 42)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct RouteStops: View {
    var origin: String
    var destination: String
    var color: Color
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5).frame(width: 7, height: 7)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 1, height: 12)
                Circle().fill(color).frame(width: 7, height: 7)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(origin).font(.caption).foregroundStyle(.secondary)
                Text(destination).font(.subheadline.weight(.semibold))
            }.lineLimit(2)
        }
    }
}

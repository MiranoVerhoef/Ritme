import SwiftUI

enum Style {
    static let accent = Color(uiColor: .systemBlue)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static func color(_ kind: TripKind) -> Color { kind == .unclassified ? Color(uiColor: .systemOrange) : .secondary }
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
        Label(kind.title, systemImage: kind.icon).font(.caption)
            .foregroundStyle(Style.color(kind))
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
        HStack(spacing: 12) {
            ForEach([TripKind.work, .personal]) { kind in
                Button { action(kind) } label: {
                    HStack(spacing: 6) {
                        Text(kind.title)
                        if selected == kind { Image(systemName: "checkmark").font(.caption.weight(.semibold)) }
                    }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 30)
                }.buttonStyle(.bordered).tint(selected == kind ? Style.accent : Color.secondary)
            }
        }
    }
}

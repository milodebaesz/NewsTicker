import SwiftUI

// De ochtendbriefing: de vijf belangrijkste verhalen voor jou, elk met één zin.
struct BriefingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reading: StoryClusters.Story?

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Goedemorgen"
        case 12..<18: "Goedemiddag"
        default: "Goedenavond"
        }
    }

    // Ouder dan 3 uur of van een andere dag: opnieuw samenstellen.
    private var needsRebuild: Bool {
        guard let b = store.briefing else { return true }
        return !b.isFromToday || Date.now.timeIntervalSince(b.createdAt) > 3 * 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let briefing = store.briefing, !briefing.entries.isEmpty, !(store.isBuildingBriefing && needsRebuild) {
                        ForEach(Array(briefing.entries.enumerated()), id: \.element.id) { index, entry in
                            row(index + 1, entry)
                        }
                        footer(briefing)
                    } else if store.isBuildingBriefing {
                        building
                    } else {
                        ContentUnavailableView("Nog geen nieuws voor je briefing",
                                               systemImage: "sun.horizon",
                                               description: Text("Ververs de feed en probeer het opnieuw."))
                    }
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Vernieuwen", systemImage: "arrow.clockwise") { Task { await store.buildBriefing() } }
                        .disabled(store.isBuildingBriefing)
                }
            }
        }
        .sheet(item: $reading) { ReaderView(story: $0) }
        .task { if needsRebuild { await store.buildBriefing() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Alleen de eerste letter: "Vrijdag 2 oktober", niet "Vrijdag 2 Oktober".
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).prefix(1).uppercased()
                 + Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).dropFirst())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Dit zijn de verhalen die er vandaag voor jou toe doen.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
        }
    }

    private func row(_ number: Int, _ entry: Briefing.Entry) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text("\(number)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.line.isEmpty {
                        Text(entry.line)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink.opacity(0.8))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(entry.sources.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
                Spacer(minLength: 0)
                if let url = URL(string: entry.image), !entry.image.isEmpty {
                    Theme.subtle
                        .overlay {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase { img.resizable().scaledToFill() } else { Theme.subtle }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 10))
                }
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line.opacity(0.7)) }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var building: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(AppleScoring.isAvailable ? "Apple Intelligence stelt je briefing samen…" : "Je briefing wordt samengesteld…")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func footer(_ briefing: Briefing) -> some View {
        Text("Samengesteld om \(briefing.createdAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
    }

    private func open(_ entry: Briefing.Entry) {
        let byId = Dictionary(store.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = entry.itemIds.compactMap { byId[$0] }
        guard let lead = items.first else { return }
        let story = StoryClusters.Story(lead: lead, others: Array(items.dropFirst()))
        reading = story
        store.learn(.opened, from: story)
    }
}

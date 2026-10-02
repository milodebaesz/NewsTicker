import SwiftUI

// "Jouw algoritme": laat zien wat de app van je geleerd heeft, en laat je het
// bijsturen. Niets gebeurt achter je rug om.
struct AlgorithmView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                Picker("Invloed", selection: $store.preferences.influence) {
                    Text("Uit").tag(0.0)
                    Text("Licht").tag(0.5)
                    Text("Normaal").tag(1.0)
                    Text("Sterk").tag(1.5)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("De app leert van wat je opent en verbergt, en van \"Meer hiervan\" en \"Minder hiervan\" (lang drukken op een kaart). Dit blijft op je iPhone en vervaagt langzaam, zodat je smaak mag veranderen.")
            }

            if store.preferences.isEmpty {
                Section {
                    ContentUnavailableView("Nog niets geleerd",
                                           systemImage: "brain",
                                           description: Text("Lees een paar artikelen, of druk lang op een kaart en kies \"Meer hiervan\" of \"Minder hiervan\"."))
                }
            } else {
                entries(liked: true)
                entries(liked: false)
                Section {
                    Button("Alles vergeten", role: .destructive) { confirmReset = true }
                }
            }
        }
        .navigationTitle("Jouw algoritme")
        .confirmationDialog("Alles wat de app geleerd heeft wissen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Alles vergeten", role: .destructive) { store.preferences.reset() }
        }
    }

    @ViewBuilder private func entries(liked: Bool) -> some View {
        let list = store.preferences.top(liked, limit: 15)
        if !list.isEmpty {
            Section {
                ForEach(list) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: icon(entry.kind))
                            .foregroundStyle(liked ? Theme.brand : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.label)
                            Text(entry.kind.rawValue) // "bron", "onderwerp", "woord"
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        strength(entry.weight, liked: liked)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { store.preferences.remove(list[i].key) }
                }
            } header: {
                Label(liked ? "Meer van" : "Minder van", systemImage: liked ? "hand.thumbsup" : "hand.thumbsdown")
            } footer: {
                if liked { Text("Veeg naar links om iets te laten vergeten.") }
            }
        }
    }

    private func icon(_ kind: LearnedPreferences.Kind) -> String {
        switch kind {
        case .source: "dot.radiowaves.up.forward"
        case .topic: "tag"
        case .word: "textformat"
        }
    }

    // 1–5 balkjes, zodat je ziet hoe sterk een voorkeur is.
    private func strength(_ weight: Double, liked: Bool) -> some View {
        let level = min(5, max(1, Int((abs(weight) / 2).rounded(.up))))
        return HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Capsule()
                    .fill(i < level ? (liked ? Theme.accent : Color.secondary) : Theme.line)
                    .frame(width: 4, height: 12)
            }
        }
        .accessibilityLabel("Sterkte \(level) van 5")
    }
}

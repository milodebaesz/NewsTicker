import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var profileChanged = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SourcesView()
                    } label: {
                        LabeledContent("Bronnen", value: "\(store.sources.filter(\.enabled).count) actief")
                    }
                }

                Section {
                    TextField("Waar ben je in geïnteresseerd?", text: $store.profile.description, axis: .vertical)
                        .lineLimit(3...8)
                    labeled("Interesses") { TextField("AI, React, beurs", text: listBinding($store.profile.keywords)) }
                    labeled("Niet interessant") { TextField("sport, showbizz", text: listBinding($store.profile.mute)) }
                } header: {
                    Text("Interesseprofiel")
                } footer: {
                    Text("Trefwoorden en negeerlijst scheiden met komma's. Het profiel bepaalt de relevantiescore (0–100).")
                }

                Section {
                    Toggle("AI-relevantiescore", isOn: $store.settings.scoringEnabled)
                    SecureField("OpenAI API-key", text: $store.openAIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Model", text: $store.settings.model)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    VStack(alignment: .leading) {
                        LabeledContent("Minimale relevantie", value: "\(store.settings.minRelevance)")
                        Slider(value: Binding(
                            get: { Double(store.settings.minRelevance) },
                            set: { store.settings.minRelevance = Int($0) }
                        ), in: 0...100, step: 5)
                    }
                } header: {
                    Text("Scoring")
                } footer: {
                    Text("De key staat alleen in de Keychain van dit apparaat. Alleen titel, bron en een korte samenvatting worden naar OpenAI gestuurd.")
                }

                Section {
                    Stepper("Elke \(store.settings.refreshMinutes) min", value: $store.settings.refreshMinutes, in: 15...240, step: 15)
                } header: {
                    Text("Verversen")
                } footer: {
                    Text("Op de achtergrond bepaalt iOS het exacte moment; bij openen wordt ververst als de laatste update ouder is dan dit interval.")
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .onChange(of: store.profile) { profileChanged = true }
            .onDisappear {
                // Nieuw profiel → bestaande scores zijn niet meer representatief.
                if profileChanged {
                    store.resetScores()
                    Task { await store.refresh() }
                }
            }
        }
    }

    private func labeled(_ title: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            field()
        }
    }

    private func listBinding(_ list: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { list.wrappedValue.joined(separator: ", ") },
            set: { list.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }
}

struct SourcesView: View {
    @Environment(AppStore.self) private var store
    @State private var showFinder = false

    var body: some View {
        @Bindable var store = store
        List {
            ForEach($store.sources) { $src in
                Toggle(isOn: $src.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(src.label)
                        Text(src.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .onDelete { store.sources.remove(atOffsets: $0) }
            .onMove { store.sources.move(fromOffsets: $0, toOffset: $1) }
        }
        .navigationTitle("Bronnen")
        .toolbar {
            EditButton()
            Button("Toevoegen", systemImage: "plus") { showFinder = true }
        }
        .sheet(isPresented: $showFinder) { FeedFinderView() }
    }
}

// Zoekt feeds bij een website-URL en voegt ze als bron toe.
struct FeedFinderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var searching = false
    @State private var results: [FeedCandidate] = []
    @State private var error = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Website of feed-URL, bv. nos.nl", text: $input)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(search)
                    Button(action: search) {
                        HStack {
                            Text("Feeds zoeken")
                            if searching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                } footer: {
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }

                if !results.isEmpty {
                    Section("Gevonden") {
                        ForEach(results) { c in
                            let added = store.sources.contains { $0.url == c.url }
                            Button { add(c) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.title).foregroundStyle(.primary)
                                        Text(c.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                }
                            }
                            .disabled(added)
                        }
                    }
                }
            }
            .navigationTitle("Bron toevoegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
        }
    }

    private func search() {
        let q = input
        searching = true
        error = ""
        results = []
        Task {
            do {
                results = try await Discover.feeds(for: q)
                if results.isEmpty { error = "Geen feeds gevonden op deze site." }
            } catch {
                self.error = "Kon de site niet laden: \(error.localizedDescription)"
            }
            searching = false
        }
    }

    private func add(_ c: FeedCandidate) {
        let host = URL(string: c.url)?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? c.url
        let label = c.title == c.url ? host : c.title
        store.sources.append(Source(id: UUID().uuidString, url: c.url, label: label, enabled: true))
        Task { await store.refresh() }
    }
}

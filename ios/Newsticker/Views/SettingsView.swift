import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var profileChanged = false
    @State private var notificationsDenied = false

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
                    Text("Trefwoorden en negeerlijst scheiden met komma's. Het profiel bepaalt hoe relevant een artikel voor je is.")
                }

                Section {
                    Picker("AI", selection: $store.settings.engine) {
                        ForEach(AIEngine.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if store.settings.engine == .openAI {
                        SecureField("OpenAI API-key", text: $store.openAIKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Model", text: $store.settings.model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    if store.settings.engine != .off {
                        Picker("Toon", selection: $store.settings.minRelevance) {
                            Text("Alles").tag(0)
                            Text("Ook een beetje relevant").tag(40)
                            Text("Relevant en hoger").tag(70)
                            Text("Alleen zeer relevant").tag(90)
                        }
                    }
                } header: {
                    Text("Relevantie")
                } footer: {
                    switch store.settings.engine {
                    case .apple:
                        if case .unavailable(let reason) = AppleScoring.status {
                            Text(reason).foregroundStyle(.orange)
                        } else {
                            Text("Draait volledig op je iPhone: gratis, zonder key, en er gaat niets naar een server.")
                        }
                    case .openAI:
                        Text("De key staat alleen in de Keychain van dit apparaat. Alleen titel, bron en een korte samenvatting worden naar OpenAI gestuurd.")
                    case .off:
                        Text("Nieuws wordt op tijd gesorteerd, zonder relevantiescore.")
                    }
                }

                Section {
                    Toggle("Ochtendbriefing", isOn: Binding(
                        get: { store.settings.briefingEnabled },
                        set: { on in
                            store.settings.briefingEnabled = on
                            if on { Task { notificationsDenied = !(await BriefingNotifications.shared.requestPermission()) } }
                        }
                    ))
                    if store.settings.briefingEnabled {
                        DatePicker("Tijd", selection: Binding(
                            get: { Calendar.current.date(bySettingHour: store.settings.briefingMinutes / 60, minute: store.settings.briefingMinutes % 60, second: 0, of: .now) ?? .now },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                store.settings.briefingMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 30)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Briefing")
                } footer: {
                    if notificationsDenied {
                        Text("Meldingen staan uit voor Newsticker. Zet ze aan in Instellingen › Meldingen om de briefing te ontvangen.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Elke ochtend een melding met de vijf belangrijkste verhalen voor jou, elk met één zin uitleg. Je kunt de briefing ook altijd openen met de zon bovenaan.")
                    }
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
            .onChange(of: store.settings.engine) { profileChanged = true }
            .onDisappear {
                Task { await store.scheduleBriefingNotification() }
                // Nieuw profiel of andere AI → bestaande scores zijn niet meer representatief.
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
        .sheet(isPresented: $showFinder) { AddSourceView() }
    }
}

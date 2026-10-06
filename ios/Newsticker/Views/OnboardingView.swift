import SwiftUI

// Eerste start: bronnen en interesses kiezen, uitleg over Apple Intelligence,
// en eventueel de ochtendbriefing aanzetten. Geen account nodig.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store

    private enum Step: Int, CaseIterable { case welcome, sources, interests, ready }

    @State private var step = Step.welcome
    @State private var chosen: Set<String> = OnboardingView.defaultSources
    @State private var interest: [String: Interest] = [:]
    @State private var extraKeywords = ""
    @State private var aboutMe = ""
    @State private var briefing = false
    @State private var briefingTime = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: .now) ?? .now

    enum Interest { case like, mute }

    private static let topics = [
        "Binnenland", "Wereld", "Politiek", "Economie", "Beurs", "Tech & AI", "Startups", "Wetenschap",
        "Klimaat", "Gezondheid", "Cultuur", "Entertainment", "Sport", "Voetbal", "Misdaad",
    ]

    // Voorgeselecteerd, zodat je met één tik kunt beginnen.
    private static let defaultSources: Set<String> = [
        "https://feeds.nos.nl/nosnieuwsalgemeen",
        "https://www.nu.nl/rss/Algemeen",
        "https://feeds.feedburner.com/tweakers/mixed",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .sources: sources
                case .interests: interests
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            bottomBar
        }
        .background(Theme.canvas)
        .interactiveDismissDisabled()
    }

    // MARK: - Stappen

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image("AppIconImage")
                    .resizable()
                    .frame(width: 88, height: 88)
                    .clipShape(.rect(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                    .padding(.top, 40)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welkom bij Newsticker")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("Het nieuws van jouw bronnen, op één plek.")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 20) {
                    feature("square.stack", "Zelfde nieuws, één kaart", "Brengen NOS en NU.nl hetzelfde verhaal? Dan zie je het één keer, met alle bronnen erbij.")
                    feature("lock.shield", "Privé, zonder account", "Geen login en geen tracking. Wat je leest en wat de app van je leert, blijft op je iPhone.")
                    feature("sun.horizon", "Ochtendbriefing", "Elke ochtend de vijf verhalen die er voor jou toe doen.")
                    feature("brain", "Jouw eigen algoritme", "De app leert van wat je leest, en je ziet en stuurt precies wat hij geleerd heeft.")
                }
            }
            .padding(24)
        }
    }

    private var sources: some View {
        List {
            Section {
                header("Kies je bronnen", "Je kunt later altijd bronnen toevoegen of zoeken via het menu bovenin.")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
            }
            ForEach(FeedCatalog.categories) { cat in
                Section {
                    ForEach(cat.feeds) { feed in
                        Button {
                            if chosen.contains(feed.url) { chosen.remove(feed.url) } else { chosen.insert(feed.url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.title).foregroundStyle(Theme.ink)
                                    Text(feed.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: chosen.contains(feed.url) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(chosen.contains(feed.url) ? Theme.brand : Color.secondary.opacity(0.5))
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen.contains(feed.url) ? .isSelected : [])
                    }
                } header: {
                    Label(cat.name, systemImage: cat.symbol)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var interests: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header("Waar ben je in geïnteresseerd?",
                       "Tik één keer voor meer hiervan, twee keer voor minder. Je kunt dit later aanpassen.")
                FlowLayout(spacing: 8) {
                    ForEach(Self.topics, id: \.self) { topic in
                        topicChip(topic)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Iets specifieks?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    TextField("Bijvoorbeeld: Formule 1, Apple, woningmarkt", text: $extraKeywords)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("In één zin: wat wil je volgen? (optioneel)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    TextField("Bijvoorbeeld: ik werk in de zorg en volg graag politiek", text: $aboutMe, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Text("Apple Intelligence gebruikt dit om je nieuws te sorteren, op je iPhone zelf.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header("Klaar om te beginnen", "Nog twee dingen om te weten.")
                if AppleScoring.isAvailable {
                    feature("sparkles", "Apple Intelligence staat aan",
                            "Je nieuws wordt op je iPhone beoordeeld en samengevat. Er gaat niets naar een server.")
                } else {
                    feature("sparkles", "Zonder Apple Intelligence",
                            "Op deze iPhone is Apple Intelligence niet beschikbaar. Je nieuws staat op tijd, en de app leert nog steeds van wat je leest; alleen de AI-samenvattingen ontbreken.")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $briefing) {
                        Label("Ochtendbriefing", systemImage: "sun.horizon").font(.headline)
                    }
                    if briefing {
                        DatePicker("Tijd", selection: $briefingTime, displayedComponents: .hourAndMinute)
                    }
                    Text("Elke ochtend een melding met de vijf belangrijkste verhalen voor jou.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Theme.card, in: .rect(cornerRadius: 16))
            }
            .padding(24)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Theme.brand : Theme.line)
                        .frame(width: s == step ? 20 : 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Terug") { go(-1) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(action: next) {
                    Text(primaryTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.button)
                .controlSize(.large)
                .disabled(step == .sources && chosen.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Aan de slag"
        case .sources: chosen.isEmpty ? "Kies minstens één bron" : "Verder met \(chosen.count) \(chosen.count == 1 ? "bron" : "bronnen")"
        case .interests: "Verder"
        case .ready: "Start"
        }
    }

    // MARK: - Onderdelen

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.weight(.bold)).foregroundStyle(Theme.ink)
            Text(subtitle).font(.callout).foregroundStyle(Theme.muted)
        }
        .padding(.top, 24)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func topicChip(_ topic: String) -> some View {
        let state = interest[topic]
        return Button {
            withAnimation(.snappy) {
                switch state {
                case nil: interest[topic] = .like
                case .like?: interest[topic] = .mute
                case .mute?: interest[topic] = nil
                }
            }
        } label: {
            HStack(spacing: 5) {
                if state == .like { Image(systemName: "plus") }
                if state == .mute { Image(systemName: "minus") }
                Text(topic).strikethrough(state == .mute)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(state == .like ? Color.white : state == .mute ? Color.secondary : Theme.ink)
            .background(state == .like ? Theme.button : state == .mute ? Theme.subtle : Theme.card, in: .capsule)
            .overlay { if state == nil { Capsule().strokeBorder(Theme.line) } }
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == .like ? "meer hiervan" : state == .mute ? "minder hiervan" : "neutraal")
    }

    // MARK: - Acties

    private func go(_ delta: Int) {
        guard let target = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.snappy) { step = target }
    }

    private func next() {
        if step == .ready { finish() } else { go(1) }
    }

    private func finish() {
        let catalog = FeedCatalog.categories.flatMap(\.feeds)
        let picked = catalog.filter { chosen.contains($0.url) }
        var seen = Set<String>()
        let sources = picked.compactMap { feed -> Source? in
            guard seen.insert(feed.url).inserted else { return nil }
            return Source(id: UUID().uuidString, url: feed.url, label: feed.title, enabled: true)
        }

        let extra = extraKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let liked = Self.topics.filter { interest[$0] == .like }
        let muted = Self.topics.filter { interest[$0] == .mute }
        let profile = InterestProfile(
            description: aboutMe.trimmingCharacters(in: .whitespacesAndNewlines),
            keywords: liked + extra,
            mute: muted.map { $0.lowercased() }
        )

        let c = Calendar.current.dateComponents([.hour, .minute], from: briefingTime)
        store.settings.briefingEnabled = briefing
        store.settings.briefingMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 30)
        store.completeOnboarding(sources: sources, profile: profile)
        if briefing {
            Task {
                _ = await BriefingNotifications.shared.requestPermission()
                await store.scheduleBriefingNotification()
            }
        }
    }
}

// Eenvoudige "woord-terugloop"-layout voor de onderwerpknoppen.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

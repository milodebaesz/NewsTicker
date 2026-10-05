import BackgroundTasks
import SwiftUI

@main
struct NewstickerApp: App {
    static let refreshTaskID = "com.mkdebie.newsticker.refresh"
    static let scoringTaskID = "com.mkdebie.newsticker.scoring"

    @State private var store = AppStore.shared

    init() {
        BriefingNotifications.shared.activate()
        // Zware AI-taak: iOS kiest een rustig moment (scherm uit, vaak aan de lader).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.scoringTaskID, using: nil) { task in
            let work = Task { @MainActor in
                await AppStore.shared.scoreBacklog()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(Theme.brand)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active where store.isStale:
                Task { await store.refresh() }
            case .background:
                store.pauseScoring()
                Task { await store.updateWidget() } // gelezen artikelen eruit
                scheduleAppRefresh()
                scheduleScoring()
                Task { await store.scheduleBriefingNotification() }
            default: break
            }
        }
        // Vervangt chrome.alarms: iOS bepaalt zelf wanneer dit precies draait.
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await scheduleAppRefresh()
            await store.refresh()
            await store.waitForScoring()
            await store.prepareBriefingIfDue()
            await scheduleScoring()
        }
    }

    @MainActor private func scheduleScoring() {
        guard store.hasScoringBacklog else { return }
        let request = BGProcessingTaskRequest(identifier: Self.scoringTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        var earliest = Date.now.addingTimeInterval(Double(max(15, store.settings.refreshMinutes)) * 60)
        // Ruim vóór de briefing verversen, zodat die met vers nieuws klaarstaat.
        if store.settings.briefingEnabled {
            let prep = BriefingNotifications.nextDate(minutes: store.settings.briefingMinutes).addingTimeInterval(-75 * 60)
            if prep > .now { earliest = min(earliest, prep) }
        }
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request)
    }
}

// Navy + goud, afgestemd op de extensie (Goalflow-palet), met donkere variant.
enum Theme {
    static let brand = dynamic(light: 0x2C4F87, dark: 0x8CA7CC)
    /// Vulkleur van hoofdknoppen met witte tekst: in het donker niet het lichte
    /// merkblauw (te weinig contrast), maar navy-500.
    static let button = dynamic(light: 0x2C4F87, dark: 0x3B63A0)
    static let accent = Color(hex: 0xF59E0B)
    static let ink = dynamic(light: 0x1B2A44, dark: 0xF1F4FA)
    static let muted = dynamic(light: 0x3B63A0, dark: 0x8CA7CC)
    static let canvas = dynamic(light: 0xF5F7FB, dark: 0x0F1726)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1B2A44)
    static let line = dynamic(light: 0xD0DAEA, dark: 0x25406B)
    static let subtle = dynamic(light: 0xEDF0F8, dark: 0x213553)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

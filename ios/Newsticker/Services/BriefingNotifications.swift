import Foundation
import Observation
import UserNotifications
import os

private let log = Logger(subsystem: "com.mkdebie.newsticker", category: "Briefing")

// Meldingen voor de ochtendbriefing. Er staat altijd één melding klaar voor
// het volgende moment; zodra de briefing op de achtergrond is samengesteld,
// wordt die vervangen door een melding met de echte koppen.
@MainActor @Observable
final class BriefingNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BriefingNotifications()
    nonisolated private static let requestID = "briefing"

    /// Gezet als de gebruiker op de melding tikt; de feed opent dan de briefing.
    var openRequested = false

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Eerstvolgende briefingmoment (vandaag als dat nog komt, anders morgen).
    static func nextDate(minutes: Int, after now: Date = .now) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!
        return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)!
    }

    /// Zet (of verwijdert) de melding voor het volgende moment. Met `briefing`
    /// komen de koppen erin; anders een algemene tekst.
    func schedule(settings: AppSettings, briefing: Briefing? = nil) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard settings.briefingEnabled else { return }

        let date = Self.nextDate(minutes: settings.briefingMinutes)
        let content = UNMutableNotificationContent()
        content.title = "Je ochtendbriefing"
        content.sound = .default
        if let briefing, !briefing.entries.isEmpty {
            content.body = briefing.entries.prefix(3).map { "• \($0.title)" }.joined(separator: "\n")
            content.subtitle = "\(briefing.entries.count) verhalen voor jou"
        } else {
            content.body = "Tik om de belangrijkste verhalen van vandaag te lezen."
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: Self.requestID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        do {
            try await center.add(request)
            log.info("Briefingmelding gepland voor \(date.formatted(date: .abbreviated, time: .shortened), privacy: .public) (\(briefing == nil ? "algemeen" : "met koppen", privacy: .public))")
        } catch {
            log.error("Briefingmelding plannen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.requestID else { return }
        log.info("Briefingmelding geopend")
        await MainActor.run { openRequested = true }
    }

    // Ook tonen als de app open is.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
final class ReminderService {
    var isAuthorized = false

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule

    func scheduleReminder(for bill: Bill) {
        guard bill.reminderEnabled, isAuthorized else { return }
        removeReminder(for: bill)

        guard let nextDue = bill.nextDueDate else { return }
        let calendar = Calendar.current
        guard let reminderDate = calendar.date(
            byAdding: .day,
            value: -bill.reminderDaysBefore,
            to: nextDue
        ) else { return }

        // Don't schedule if reminder date is in the past
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Bill Due"
        if bill.reminderDaysBefore == 0 {
            content.body = "\(bill.name) is due today"
        } else {
            content.body = "\(bill.name) is due in \(bill.reminderDaysBefore) day\(bill.reminderDaysBefore == 1 ? "" : "s")"
        }
        if let amount = bill.expectedAmount {
            content.body += " — \(amount.currencyFormatted)"
        }
        content.sound = .default
        content.categoryIdentifier = "BILL_REMINDER"

        guard let notificationDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDate) else { return }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: "bill-\(bill.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func removeReminder(for bill: Bill) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["bill-\(bill.id.uuidString)"])
    }

    func rescheduleAll(bills: [Bill]) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for bill in bills where bill.reminderEnabled && bill.isActive {
            scheduleReminder(for: bill)
        }
    }
}

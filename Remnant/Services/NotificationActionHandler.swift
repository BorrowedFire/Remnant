import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let modelContext: ModelContext
    private let paymentService: PaymentService
    private let accountService: AccountService
    private let reminderService: ReminderService

    init(
        modelContext: ModelContext,
        paymentService: PaymentService,
        accountService: AccountService,
        reminderService: ReminderService
    ) {
        self.modelContext = modelContext
        self.paymentService = paymentService
        self.accountService = accountService
        self.reminderService = reminderService
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let bodyText = response.notification.request.content.body

        guard let billIDString = userInfo["billID"] as? String else { return }
        let billName = userInfo["billName"] as? String ?? ""

        switch response.actionIdentifier {
        case ReminderService.markPaidAction:
            await handleMarkPaid(billIDString: billIDString)

        case ReminderService.snoozeAction:
            await handleSnooze(billID: billIDString, billName: billName, bodyText: bodyText)

        default:
            break
        }
    }

    private func handleMarkPaid(billIDString: String) async {
        await MainActor.run {
            guard let billUUID = UUID(uuidString: billIDString) else { return }

            let descriptor = FetchDescriptor<Bill>(
                predicate: #Predicate { $0.id == billUUID }
            )
            guard let bill = try? modelContext.fetch(descriptor).first else { return }
            guard let amount = bill.expectedAmount, amount > 0 else { return }

            // Use the first account as the default
            let accountDescriptor = FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])
            let account = try? modelContext.fetch(accountDescriptor).first

            _ = paymentService.recordPayment(bill: bill, amount: amount, account: account)
            try? modelContext.save()
        }
    }

    private func handleSnooze(billID: String, billName: String, bodyText: String) async {
        await MainActor.run {
            reminderService.snoozeBillReminder(billID: billID, billName: billName, bodyText: bodyText)
        }
    }
}

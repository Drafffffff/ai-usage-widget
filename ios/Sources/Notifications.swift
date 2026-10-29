import Foundation
import UserNotifications
import UIKit

final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private var lastSnapshot: CachedSnapshot?

    func setup() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            NSLog("Headroom notifications authorization granted=\(granted) error=\(String(describing: error))")
            if granted, let snapshot = self?.lastSnapshot {
                self?.sync(snapshot)
            }
        }
    }

    /// Schedules one notification per future quota reset. Identifiers are
    /// deterministic, so re-syncing the same reset replaces instead of duplicating.
    func sync(_ snapshot: CachedSnapshot?) {
        guard let snapshot else { return }
        lastSnapshot = snapshot
        let now = Date()

        var desired: [UNNotificationRequest] = []
        for provider in snapshot.providers {
            for window in provider.windows {
                guard let reset = window.resetsAt, reset > now.addingTimeInterval(30) else { continue }
                let identifier = "reset.\(provider.kind.rawValue).\(window.label).\(Int(reset.timeIntervalSince1970))"
                let content = UNMutableNotificationContent()
                content.title = "\(provider.kind.title) · \(periodName(window.label))额度已重置"
                content.body = "新的用量周期已开始，可以继续使用。"
                content.sound = .default
                content.userInfo = ["kind": provider.kind.rawValue, "window": window.label]
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, reset.timeIntervalSince(now)),
                    repeats: false
                )
                desired.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }

        let desiredIDs = Set(desired.map(\.identifier))
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("reset.") && !desiredIDs.contains($0) }
            if !stale.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            for request in desired {
                self.center.add(request) { error in
                    if let error {
                        NSLog("Headroom notification add failed: \(error)")
                    }
                }
            }
            self.center.getPendingNotificationRequests { pending in
                NSLog("Headroom notifications pending=\(pending.count) desired=\(desired.count)")
            }
        }
    }

    func scheduleTest() {
        let content = UNMutableNotificationContent()
        content.title = "Headroom 通知测试"
        content.body = "额度重置提醒已开启；这条通知 5 秒后到达。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(
            identifier: "test.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        ))
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func periodName(_ label: String) -> String {
        switch label {
        case "5H": return "5 小时"
        case "WEEK": return "周"
        case "MONTH": return "月"
        case "BILLING CYCLE": return "账单周期"
        default: return label + " "
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

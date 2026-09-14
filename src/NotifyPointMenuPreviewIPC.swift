// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation

enum NotifyPointInstanceIPC {
    static let terminateInstanceNotification = Notification.Name("io.github.bric3.notifypoint.instance.terminate")
    static let senderProcessIDKey = "senderProcessID"
    static let launchModeKey = "launchMode"

    static func terminationUserInfo(senderProcessID: Int32, launchMode: NotifyPointLaunchMode) -> [String: String] {
        [
            senderProcessIDKey: String(senderProcessID),
            launchModeKey: launchMode.rawValue,
        ]
    }

    static func shouldTerminateInstance(
        currentProcessID: Int32,
        currentLaunchMode: NotifyPointLaunchMode,
        userInfo: [AnyHashable: Any]?
    ) -> Bool {
        guard let rawSenderProcessID = userInfo?[senderProcessIDKey] as? String,
              let senderProcessID = Int32(rawSenderProcessID),
              let rawLaunchMode = userInfo?[launchModeKey] as? String,
              let launchMode = NotifyPointLaunchMode(rawValue: rawLaunchMode)
        else {
            return false
        }

        return senderProcessID != currentProcessID && launchMode == currentLaunchMode
    }
}

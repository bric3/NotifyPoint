// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

enum NotificationWindowCreatedMoveResult {
    case moved(needsSettleFollowUp: Bool)
    case moveFailed
    case noBannerContainer
    case nonMovableCandidate
}

enum NotificationMovePolicy {
    static func isPositionVerified(actual: CGPoint?, target: CGPoint) -> Bool {
        guard let actual else { return false }
        return abs(actual.x - target.x) <= 1 && abs(actual.y - target.y) <= 1
    }

    static func cacheIdentifier(windowIdentifier: String?, notificationIdentifier: String?) -> String? {
        notificationIdentifier ?? windowIdentifier
    }

    static func shouldScheduleSettleFollowUp(windowCreatedMoveResult: NotificationWindowCreatedMoveResult) -> Bool {
        switch windowCreatedMoveResult {
        case let .moved(needsSettleFollowUp):
            return needsSettleFollowUp
        case .noBannerContainer, .moveFailed:
            return true
        case .nonMovableCandidate:
            return false
        }
    }

    static func moveDecision(
        identifier: String?,
        focused: Bool,
        isNotificationCenterPanelOpen: Bool,
        hasWidgetDescendant: Bool = false,
        notificationSubrole: String?
    ) -> NotificationMoveDecision {
        if isNotificationCenterPanelOpen,
           shouldSkipForPanelOpen(notificationSubrole: notificationSubrole) {
            return .skipPanelOpen
        }
        if hasWidgetDescendant {
            return .skipWidget
        }
        if let identifier, identifier.hasPrefix("widget") {
            return .skipWidget
        }
        if focused, shouldSkipForFocusedWindow(notificationSubrole: notificationSubrole) {
            return .skipFocused
        }
        return .move
    }

    static func shouldResetCache(cachedWindowIdentifier: String?, currentWindowIdentifier: String?) -> Bool {
        guard let cachedWindowIdentifier, let currentWindowIdentifier else {
            return false
        }
        return cachedWindowIdentifier != currentWindowIdentifier
    }

    private static func shouldSkipForPanelOpen(notificationSubrole: String?) -> Bool {
        switch notificationSubrole {
        case "AXNotificationCenterAlert":
            return false
        case "AXNotificationCenterBanner",
             "AXNotificationCenterNotification",
             "AXNotificationCenterBannerWindow":
            return true
        default:
            return true
        }
    }

    private static func shouldSkipForFocusedWindow(notificationSubrole: String?) -> Bool {
        switch notificationSubrole {
        case "AXNotificationCenterAlert":
            return false
        default:
            return true
        }
    }
}

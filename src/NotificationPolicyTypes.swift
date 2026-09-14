// SPDX-License-Identifier: GPL-3.0-only

import CoreGraphics

struct ScreenDescriptor: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
    let isBuiltIn: Bool
    let backingScaleFactor: CGFloat

    init(
        frame: CGRect,
        visibleFrame: CGRect,
        isMain: Bool,
        isBuiltIn: Bool = false,
        backingScaleFactor: CGFloat
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.backingScaleFactor = backingScaleFactor
    }
}

struct NotificationCenterPanelSignal: Equatable {
    let hasSystemWideFocusedApplication: Bool
    let hasSystemWideFocusedWindow: Bool
    let hasFocusedWindow: Bool
    let hasWidgetUI: Bool

    init(
        hasFocusedWindow: Bool,
        hasWidgetUI: Bool,
        hasSystemWideFocusedApplication: Bool = false,
        hasSystemWideFocusedWindow: Bool = false
    ) {
        self.hasSystemWideFocusedApplication = hasSystemWideFocusedApplication
        self.hasSystemWideFocusedWindow = hasSystemWideFocusedWindow
        self.hasFocusedWindow = hasFocusedWindow
        self.hasWidgetUI = hasWidgetUI
    }
}

enum NotificationMoveDecision: Equatable {
    case skipPanelOpen
    case skipWidget
    case skipFocused
    case move
}

enum NotificationCenterStateChange: Equatable {
    case unchanged
    case opened
    case closed
}

enum RecoveryRetryAction: Equatable {
    case stop
    case retry
}

enum NotificationScanResult: Equatable {
    case movedNotification
    case noMovableCandidates
    case placeholderOnly
}

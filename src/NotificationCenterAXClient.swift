// SPDX-License-Identifier: GPL-3.0-only

import ApplicationServices
import Cocoa

enum NotificationCenterAXTraversalPolicy {
    static let bannerSubroles: [String] = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXNotificationCenterNotification",
        "AXNotificationCenterBannerWindow",
        "AXNotificationCenterAlertStack",
    ]

    static let descendantAttributes: [String] = [
        kAXChildrenAttribute as String,
        "AXContents",
        "AXVisibleChildren",
        "AXRows",
        "AXColumns",
        "AXSelectedChildren",
        "AXTabs",
    ]

    static let ignoredFallbackAttributes: Set<String> = [
        kAXParentAttribute as String,
        kAXWindowAttribute as String,
        kAXTopLevelUIElementAttribute as String,
        kAXFocusedApplicationAttribute as String,
        kAXFocusedWindowAttribute as String,
        kAXTitleUIElementAttribute as String,
    ]

    static func shouldInspectFallbackAttribute(_ attribute: String) -> Bool {
        !descendantAttributes.contains(attribute) && !ignoredFallbackAttributes.contains(attribute)
    }
}

protocol NotificationCenterAXClient {
    func notificationCenterProcessIdentifier(bundleID: String) -> pid_t?
    func notificationWindows(pid: pid_t) -> (windows: [AXUIElement]?, error: AXError)
    func windowIdentifier(_ element: AXUIElement) -> String?
    func isFocused(_ element: AXUIElement) -> Bool
    func position(of element: AXUIElement) -> CGPoint?
    func size(of element: AXUIElement) -> CGSize?
    @discardableResult
    func setPosition(_ element: AXUIElement, point: CGPoint) -> AXError
    func firstElement(root: AXUIElement, targetSubroles: [String], diagnoseMissing: Bool) -> AXUIElement?
    func hasSystemWideFocusedApplication(pid: pid_t) -> Bool
    func hasSystemWideFocusedWindow(pid: pid_t) -> Bool
    func hasFocusedWindow(pid: pid_t) -> Bool
    func hasWidgetUI(pid: pid_t) -> Bool
    func hasWidgetDescendant(root: AXUIElement) -> Bool
    func role(of element: AXUIElement) -> String?
    func subrole(of element: AXUIElement) -> String?
}

struct SystemNotificationCenterAXClient: NotificationCenterAXClient {
    var log: (String) -> Void = { _ in }

    func notificationCenterProcessIdentifier(bundleID: String) -> pid_t? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        })?.processIdentifier
    }

    func notificationWindows(pid: pid_t) -> (windows: [AXUIElement]?, error: AXError) {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef)
        guard error == .success else {
            return (nil, error)
        }
        guard let windows = windowsRef as? [AXUIElement] else {
            log("AXWindows returned an unexpected value type (pid=\(pid)).")
            return (nil, .failure)
        }
        return (windows, .success)
    }

    func windowIdentifier(_ element: AXUIElement) -> String? {
        var identifierRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierRef) == .success else {
            return nil
        }
        return identifierRef as? String
    }

    func isFocused(_ element: AXUIElement) -> Bool {
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef as? Bool else {
            return false
        }
        return focused
    }

    func position(of element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        guard error == .success else {
            log("AXPosition read failed: \(error.diagnosticSummary), trusted=\(AXIsProcessTrusted())")
            return nil
        }
        guard let posVal = positionValue,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              AXValueGetType(posVal as! AXValue) == .cgPoint else {
            return nil
        }
        var position = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
        return position
    }

    func size(of element: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard error == .success else {
            log("AXSize read failed: \(error.diagnosticSummary), trusted=\(AXIsProcessTrusted())")
            return nil
        }
        guard let sizeVal = sizeValue,
              CFGetTypeID(sizeVal) == AXValueGetTypeID(),
              AXValueGetType(sizeVal as! AXValue) == .cgSize else {
            return nil
        }
        var size = CGSize.zero
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return size
    }

    func setPosition(_ element: AXUIElement, point: CGPoint) -> AXError {
        var point = point
        let value = AXValueCreate(.cgPoint, &point)!
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func firstElement(root: AXUIElement, targetSubroles: [String], diagnoseMissing: Bool) -> AXUIElement? {
        if let preferredMatch = firstMatchingElement(
            roots: [root],
            childProvider: { preferredChildren(of: $0) },
            targetSubroles: targetSubroles
        ) {
            return preferredMatch
        }

        return firstMatchingElement(
            roots: [root],
            childProvider: { fallbackChildren(of: $0) },
            targetSubroles: targetSubroles,
            diagnoseMissing: diagnoseMissing
        )
    }

    func hasSystemWideFocusedApplication(pid: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplicationRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApplicationRef) == .success,
              let focusedApplicationRef else {
            return false
        }
        let focusedApplication = focusedApplicationRef as! AXUIElement
        var focusedApplicationPID: pid_t = 0
        AXUIElementGetPid(focusedApplication, &focusedApplicationPID)
        return focusedApplicationPID == pid
    }

    func hasSystemWideFocusedWindow(pid: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
              let focusedWindowRef else {
            return false
        }
        let focusedWindow = focusedWindowRef as! AXUIElement
        var focusedWindowPID: pid_t = 0
        AXUIElementGetPid(focusedWindow, &focusedWindowPID)
        return focusedWindowPID == pid
    }

    func hasFocusedWindow(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedWindowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success else {
            return false
        }
        return focusedWindowRef != nil
    }

    func hasWidgetUI(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        return hasWidgetIdentifier(roots: [axApp])
    }

    func hasWidgetDescendant(root: AXUIElement) -> Bool {
        hasWidgetIdentifier(roots: [root])
    }

    private func hasWidgetIdentifier(roots: [AXUIElement]) -> Bool {
        return TreeTraversal.firstMatchingNode(
            roots: roots,
            childProvider: { fallbackChildren(of: $0) },
            matches: { element in
                guard let identifier = windowIdentifier(element) else {
                    return false
                }
                return identifier.hasPrefix("widget-local")
            }
        ) != nil
    }

    func role(of element: AXUIElement) -> String? {
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else {
            return nil
        }
        return roleRef as? String
    }

    func subrole(of element: AXUIElement) -> String? {
        var subroleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success else {
            return nil
        }
        return subroleRef as? String
    }

    private func firstMatchingElement(
        roots: [AXUIElement],
        childProvider: (AXUIElement) -> [AXUIElement],
        targetSubroles: [String],
        diagnoseMissing: Bool = false
    ) -> AXUIElement? {
        var visitedCount = 0
        var samples: [String] = []
        let match = TreeTraversal.firstMatchingNode(
            roots: roots,
            childProvider: childProvider,
            matches: { element in
                var subroleRef: AnyObject?
                let error = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
                let subrole = error == .success ? subroleRef as? String : nil
                if diagnoseMissing {
                    visitedCount += 1
                    // Sample only metadata from the existing search; never notification text.
                    if samples.count < 64 {
                        let detail = subrole ?? "missing(\(error.diagnosticSummary))"
                        samples.append("\(role(of: element) ?? "unknown")/\(detail)")
                    }
                }
                guard let subrole else { return false }
                return targetSubroles.contains(subrole)
            }
        )
        if diagnoseMissing, match == nil {
            log("Unrecognised notification tree: visited=\(visitedCount), sampled=\(samples.count), " +
                "roles/subroles=[\(samples.joined(separator: ", "))]")
        }
        return match
    }

    private func preferredChildren(of element: AXUIElement) -> [AXUIElement] {
        var combined: [AXUIElement] = []
        var seen: Set<AXUIElement> = []

        for attribute in NotificationCenterAXTraversalPolicy.descendantAttributes {
            for child in attributeElements(of: element, attribute: attribute) where seen.insert(child).inserted {
                combined.append(child)
            }
        }

        return combined
    }

    private func fallbackChildren(of element: AXUIElement) -> [AXUIElement] {
        var combined = preferredChildren(of: element)
        var seen = Set(combined)

        for attribute in attributeNames(of: element)
            where NotificationCenterAXTraversalPolicy.shouldInspectFallbackAttribute(attribute)
        {
            for child in attributeElements(of: element, attribute: attribute) where seen.insert(child).inserted {
                combined.append(child)
            }
        }

        return combined
    }

    private func attributeElements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let valueRef else {
            return []
        }

        if let children = valueRef as? [AXUIElement] {
            return children
        }

        if CFGetTypeID(valueRef) == AXUIElementGetTypeID() {
            let child = unsafeBitCast(valueRef, to: AXUIElement.self)
            return [child]
        }

        return []
    }

    private func attributeNames(of element: AXUIElement) -> [String] {
        var attributeNamesRef: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributeNamesRef) == .success,
              let attributeNamesRef,
              let attributeNames = attributeNamesRef as? [String] else {
            return []
        }
        return attributeNames
    }
}

extension AXError {
    var diagnosticSummary: String {
        let name: String
        switch self {
        case .success: name = "success"
        case .failure: name = "failure"
        case .illegalArgument: name = "illegalArgument"
        case .invalidUIElement: name = "invalidUIElement"
        case .invalidUIElementObserver: name = "invalidUIElementObserver"
        case .cannotComplete: name = "cannotComplete"
        case .attributeUnsupported: name = "attributeUnsupported"
        case .notificationUnsupported: name = "notificationUnsupported"
        case .notificationAlreadyRegistered: name = "notificationAlreadyRegistered"
        case .apiDisabled: name = "apiDisabled"
        case .noValue: name = "noValue"
        default: name = "AXError"
        }
        return "\(name)(\(rawValue))"
    }
}

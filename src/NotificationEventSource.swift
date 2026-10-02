// SPDX-License-Identifier: GPL-3.0-only

import ApplicationServices
import Cocoa

protocol NotificationEventHandler: AnyObject {
    func notificationCenterWindowCreated(_ element: AXUIElement)
    func notificationCenterStateMonitorTick()
    func screenParametersChanged()
    func sessionDidBecomeActive()
    func systemWillSleep()
    func systemDidWake()
    func notificationEnvironmentDidBecomeAvailable(reason: String)
    func screenLockChanged(isLocked: Bool)
}

final class NotificationEventSource {
    private let notificationCenterBundleID: String
    private weak var handler: NotificationEventHandler?
    private let log: (String) -> Void
    private let workspaceNotificationCenter: NotificationCenter
    private let screenLockNotificationCenter: NotificationCenter

    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var nextObserverCheck: Date = .distantPast
    private var lastObserverFailure: String?
    private var lastWindowCreatedAt: Date?
    private var widgetMonitorTimer: Timer?
    private var screenParametersObserver: NSObjectProtocol?
    private var sessionDidBecomeActiveObserver: NSObjectProtocol?
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?
    private var screensDidWakeObserver: NSObjectProtocol?
    private var screenLockObservers: [NSObjectProtocol] = []

    var diagnosticSummary: String {
        "observerPID=\(observedPID.map(String.init) ?? "none"), " +
            "lastWindowCreated=\(lastWindowCreatedAt.map { String(describing: $0) } ?? "none"), " +
            "trusted=\(AXIsProcessTrusted())"
    }

    init(
        notificationCenterBundleID: String,
        handler: NotificationEventHandler,
        log: @escaping (String) -> Void,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        screenLockNotificationCenter: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        self.notificationCenterBundleID = notificationCenterBundleID
        self.handler = handler
        self.log = log
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.screenLockNotificationCenter = screenLockNotificationCenter
    }

    deinit {
        stop()
    }

    func start() {
        ensureAXObserver()
        setupWidgetMonitor()
        setupScreenChangeObserver()
        setupSessionActivityObservers()
        setupSleepWakeObservers()
        setupScreenLockObservers()
    }

    func stop() {
        widgetMonitorTimer?.invalidate()
        widgetMonitorTimer = nil

        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }

        if let sessionDidBecomeActiveObserver {
            workspaceNotificationCenter.removeObserver(sessionDidBecomeActiveObserver)
            self.sessionDidBecomeActiveObserver = nil
        }
        if let willSleepObserver {
            workspaceNotificationCenter.removeObserver(willSleepObserver)
            self.willSleepObserver = nil
        }
        if let didWakeObserver {
            workspaceNotificationCenter.removeObserver(didWakeObserver)
            self.didWakeObserver = nil
        }
        if let screensDidWakeObserver {
            workspaceNotificationCenter.removeObserver(screensDidWakeObserver)
            self.screensDidWakeObserver = nil
        }
        for observer in screenLockObservers {
            screenLockNotificationCenter.removeObserver(observer)
        }
        screenLockObservers.removeAll()

        removeAXObserver()
    }

    private func removeAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil
        observedPID = nil
    }

    // Reuse the existing monitor; retry a missing observer at most every five seconds.
    @discardableResult
    func ensureAXObserver(force: Bool = false) -> Bool {
        guard force || Date() >= nextObserverCheck else { return false }
        nextObserverCheck = Date().addingTimeInterval(5)
        let pid = notificationCenterProcessIdentifier()
        let trusted = AXIsProcessTrusted()
        if !force, trusted, let pid, observedPID == pid, axObserver != nil {
            return false
        }

        if observedPID != nil {
            log("Removing Notification Center observer: \(diagnosticSummary), currentPID=\(pid.map(String.init) ?? "none"), forced=\(force)")
        }
        removeAXObserver()
        guard trusted, let pid else {
            reportObserverFailure("Notification Center observer unavailable: pid=\(pid.map(String.init) ?? "none"), trusted=\(trusted)")
            return false
        }

        let app = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let createError = AXObserverCreate(pid, eventSourceObserverCallback, &observer)
        guard createError == .success, let observer else {
            reportObserverFailure("AXObserverCreate failed: pid=\(pid), error=\(createError.diagnosticSummary), trusted=\(trusted)")
            return false
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let addError = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, context)
        guard addError == .success else {
            reportObserverFailure("AXObserverAddNotification failed: pid=\(pid), error=\(addError.diagnosticSummary), trusted=\(trusted)")
            return false
        }
        axObserver = observer
        observedPID = pid
        lastWindowCreatedAt = nil
        lastObserverFailure = nil
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        log("Observer setup complete for Notification Center (PID: \(pid))")
        return true
    }

    private func reportObserverFailure(_ message: String) {
        if lastObserverFailure != message { log(message) }
        lastObserverFailure = message
    }

    private func setupWidgetMonitor() {
        widgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.ensureAXObserver() {
                self.handler?.notificationEnvironmentDidBecomeAvailable(reason: "notificationCenterObserverRestored")
            }
            self.handler?.notificationCenterStateMonitorTick()
        }
    }

    private func setupScreenChangeObserver() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.screenParametersChanged()
        }
    }

    private func setupSleepWakeObservers() {
        willSleepObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?.systemWillSleep()
        }

        didWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureAXObserver(force: true)
            self?.handler?.systemDidWake()
        }

        screensDidWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureAXObserver(force: true)
            self?.handler?.notificationEnvironmentDidBecomeAvailable(reason: "screensDidWakeNotification")
        }
    }

    private func setupScreenLockObservers() {
        // These distributed names are undocumented. Keep workspace wake/session recovery too.
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let observer = screenLockNotificationCenter.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                if !isLocked { self?.ensureAXObserver(force: true) }
                self?.handler?.screenLockChanged(isLocked: isLocked)
            }
            screenLockObservers.append(observer)
        }
    }

    private func setupSessionActivityObservers() {
        sessionDidBecomeActiveObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureAXObserver(force: true)
            self?.handler?.sessionDidBecomeActive()
        }
    }

    private func notificationCenterProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        })?.processIdentifier
    }

    fileprivate func handleAXWindowCreated(_ element: AXUIElement) {
        lastWindowCreatedAt = Date()
        var pid: pid_t = 0
        let error = AXUIElementGetPid(element, &pid)
        log("AXWindowCreated received: elementPID=\(pid), pidError=\(error.diagnosticSummary), \(diagnosticSummary)")
        handler?.notificationCenterWindowCreated(element)
    }
}

private func eventSourceObserverCallback(observer _: AXObserver, element: AXUIElement, notification: CFString, context: UnsafeMutableRawPointer?) {
    guard notification as String == kAXWindowCreatedNotification as String,
          let context else {
        return
    }

    let eventSource = Unmanaged<NotificationEventSource>.fromOpaque(context).takeUnretainedValue()
    eventSource.handleAXWindowCreated(element)
}

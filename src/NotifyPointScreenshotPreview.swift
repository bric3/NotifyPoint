// SPDX-License-Identifier: GPL-3.0-only

import Cocoa
import Darwin

// The Java runner owns orchestration; AppKit owns native menu presentation and geometry.
final class NotifyPointScreenshotPreview {
    private let configuration: NotifyPointScreenshotConfiguration
    private var background: NSWindow?
    private var header: NSWindow?
    private var timer: Timer?
    private var watchdog: Timer?
    private weak var menu: NSMenu?
    private let startedAt = Date()
    private let originalPointer = NSEvent.mouseLocation
    private var movedPointer = false
    private var lastState = ""

    init(configuration: NotifyPointScreenshotConfiguration) {
        self.configuration = configuration
    }

    func start(button: NSStatusBarButton, menu: NSMenu, picker: NotificationPositionPickerView?,
               displayPicker: NotificationDisplayTargetPickerView?,
               displayTarget: NotificationDisplayTarget)
    {
        let watchdog = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.configuration.directory.appendingPathComponent("stop").path)
                || kill(self.configuration.parentPID, 0) != 0 || Date().timeIntervalSince(self.startedAt) > 60
            {
                self.close()
                NSApp.terminate(nil)
            }
        }
        self.watchdog = watchdog
        RunLoop.main.add(watchdog, forMode: .common)
        RunLoop.main.add(watchdog, forMode: .eventTracking)
        guard let picker, let screen = button.window?.screen else {
            fail("The preview status item is not on a visible screen.")
            return
        }
        if configuration.hardware, configuration.scene == "display", displayPicker == nil {
            publish("status=skipped\nreason=Laptop display unavailable\n")
            return
        }
        guard screen.backingScaleFactor == 2 else {
            fail("Screenshots require a display with 2x backing scale. Display settings were left unchanged.")
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            fail("Allow Screen Recording for the launching terminal or agent, then run make screenshots again.")
            return
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        else {
            fail("Screenshots require Reduce transparency and Increase contrast to be off. Settings were left unchanged.")
            return
        }
        guard let image = NSImage(contentsOf: configuration.directory.appendingPathComponent("background.png")) else {
            fail("Cannot load the screenshot background.")
            return
        }
        let frame = CGRect(x: screen.visibleFrame.maxX - 440, y: screen.visibleFrame.maxY - 560,
                           width: 400, height: 520)
        guard screen.visibleFrame.contains(frame) else {
            fail("The display is too small for the screenshot canvas.")
            return
        }
        let backdrop = makeWindow(frame: frame)
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        backdrop.contentView = imageView
        backdrop.orderFrontRegardless()
        background = backdrop

        let headerFrame = CGRect(x: frame.minX + 36, y: frame.maxY - 48, width: 328, height: 32)
        let headerWindow = makeWindow(frame: headerFrame)
        headerWindow.isOpaque = false
        headerWindow.backgroundColor = .clear
        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: headerFrame.size))
        glass.material = .menu
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 10
        glass.layer?.masksToBounds = true
        glass.autoresizingMask = [.width]
        let icon = NSButton(frame: CGRect(x: 8, y: 1, width: 40, height: 30))
        icon.image = button.image
        icon.imagePosition = .imageOnly
        icon.bezelStyle = .recessed
        icon.setButtonType(.pushOnPushOff)
        icon.state = .on
        icon.contentTintColor = .labelColor
        glass.addSubview(icon)
        headerWindow.contentView = glass
        headerWindow.orderFrontRegardless()
        header = headerWindow
        self.menu = menu
        menu.minimumWidth = 328
        picker.setFrameSize(NSSize(width: 328, height: picker.frame.height))
        if let displayPicker {
            displayPicker.setFrameSize(NSSize(width: 328, height: displayPicker.frame.height))
        }

        // Menu tracking runs a nested event loop, so readiness and parent checks must run there too.
        let poll = Timer(timeInterval: 0.1, repeats: true) { [weak self, weak picker, weak displayPicker] _ in
            guard let self else { return }
            guard let picker, let window = picker.window, window.isVisible else {
                self.publish("status=waiting\nreason=Menu is not visible.\n")
                return
            }
            let hover: NotificationPosition = self.configuration.scene == "position" ? .topLeft : .middleRight
            if !self.movedPointer {
                let point = picker.convert(picker.screenshotHoverPoint(for: hover), to: nil)
                let screenPoint = window.convertPoint(toScreen: point)
                let quartzPoint = self.quartzPoint(screenPoint, on: screen)
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartzPoint,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                self.movedPointer = true
                return
            }
            guard picker.hoveredPosition == hover else {
                self.publish("status=waiting\nreason=Hover automation did not reach the grid; check Accessibility permission for the launching terminal or agent.\n")
                return
            }
            let menuFrame = window.frame
            if self.header?.frame.width != menuFrame.width {
                self.header?.setFrame(CGRect(x: menuFrame.minX, y: frame.maxY - 48,
                                            width: menuFrame.width, height: 32), display: true)
                return
            }
            guard frame.insetBy(dx: 12, dy: 12).contains(menuFrame) else {
                self.fail("The native menu does not fit inside the fixed capture canvas.")
                return
            }
            let origin = self.quartzPoint(CGPoint(x: frame.minX, y: frame.maxY), on: screen)
            self.publish("status=ready\nx=\(Int(origin.x))\ny=\(Int(origin.y))\nwidth=400\nheight=520\nscale=2\n" +
                "scene=\(self.configuration.scene)\nappearance=\(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light")\n" +
                "position=\(picker.selectedPosition.rawValue)\nhover=\(hover.rawValue)\n" +
                "displayTarget=\(displayPicker?.selectedTarget.rawValue ?? displayTarget.rawValue)\n" +
                "displaySelector=\(displayPicker != nil)\nmenuX=\(Int(menuFrame.minX - frame.minX))\n" +
                "menuY=\(Int(frame.maxY - menuFrame.maxY))\nmenuWidth=\(Int(menuFrame.width))\nmenuHeight=\(Int(menuFrame.height))\n")
        }
        timer = poll
        RunLoop.main.add(poll, forMode: .common)
        RunLoop.main.add(poll, forMode: .eventTracking)
        DispatchQueue.main.async { [weak self] in
            menu.popUp(positioning: nil, at: CGPoint(x: frame.minX + 36, y: frame.maxY - 56), in: nil)
            if let self, self.timer != nil {
                self.fail("The menu closed before capture completed. Please leave the mouse and keyboard idle during capture.")
            }
        }
    }

    func close() {
        watchdog?.invalidate()
        watchdog = nil
        timer?.invalidate()
        timer = nil
        menu?.cancelTracking()
        header?.orderOut(nil)
        background?.orderOut(nil)
        if movedPointer, let screen = NSScreen.screens.first(where: { $0.frame.contains(originalPointer) }) {
            CGWarpMouseCursorPosition(quartzPoint(originalPointer, on: screen))
            movedPointer = false
        }
    }

    private func makeWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        return window
    }

    private func quartzPoint(_ point: CGPoint, on screen: NSScreen) -> CGPoint {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber
        let bounds = CGDisplayBounds(CGDirectDisplayID(truncating: number))
        return CGPoint(x: bounds.minX + point.x - screen.frame.minX,
                       y: bounds.minY + screen.frame.maxY - point.y)
    }

    private func publish(_ state: String) {
        guard state != lastState else { return }
        do {
            try state.write(to: configuration.directory.appendingPathComponent("state.properties"), atomically: true, encoding: .utf8)
            lastState = state
        } catch {
            fputs("Cannot publish screenshot state: \(error)\n", stderr)
            close()
            NSApp.terminate(nil)
        }
    }

    private func fail(_ message: String) {
        fputs("\(message)\n", stderr)
        publish("status=error\nreason=\(message)\n")
        close()
        NSApp.terminate(nil)
    }
}

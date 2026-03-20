/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore
import Defaults

@MainActor
final class LockScreenReminderWidgetPanelManager {
    static let shared = LockScreenReminderWidgetPanelManager()

    private var windows: [NSScreen: NSWindow] = [:]
    private var hasDelegated: [NSScreen: Bool] = [:]
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    var isVisible: Bool {
        windows.values.contains { $0.isVisible }
    }

    private init() {
        registerScreenChangeObservers()
    }

    func show(with snapshot: LockScreenReminderWidgetSnapshot) {
        render(snapshot: snapshot, makeVisible: true)
    }

    func update(with snapshot: LockScreenReminderWidgetSnapshot) {
        render(snapshot: snapshot, makeVisible: false)
    }

    func hide() {
        for window in windows.values {
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    func refreshPosition(animated: Bool) {
        for (screen, window) in windows {
            guard window.isVisible else { continue }
            let target = frame(for: window.frame.size, on: screen)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(target, display: true)
                }
            } else {
                window.setFrame(target, display: true)
            }
        }
    }

    private func render(snapshot: LockScreenReminderWidgetSnapshot, makeVisible: Bool) {
        if !makeVisible && windows.isEmpty {
            return
        }

        let view = LockScreenReminderWidget(snapshot: snapshot)
        let prototypeHostingView = NSHostingView(rootView: view)
        let fittingSize = prototypeHostingView.fittingSize

        for screen in NSScreen.screens {
            let window = ensureWindow(for: screen)
            window.setFrame(frame(for: fittingSize, on: screen), display: true)
            
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: fittingSize)
            window.contentView = hostingView

            if makeVisible {
                window.orderFrontRegardless()
            }
        }
    }

    private func ensureWindow(for screen: NSScreen) -> NSWindow {
        if let window = windows[screen] {
            return window
        }

        let frame = NSRect(origin: .zero, size: CGSize(width: 220, height: 48))
        let newWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.ignoresMouseEvents = true
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)

        windows[screen] = newWindow
        if hasDelegated[screen] != true {
            SkyLightOperator.shared.delegateWindow(newWindow)
            hasDelegated[screen] = true
        }
        return newWindow
    }

    private func frame(for size: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let horizontalPadding: CGFloat = 24
        let alignment = Defaults[.lockScreenReminderWidgetHorizontalAlignment].lowercased()
        let originX: CGFloat

        switch alignment {
        case "leading", "left":
            originX = screenFrame.minX + horizontalPadding
        case "trailing", "right":
            originX = screenFrame.maxX - size.width - horizontalPadding
        default:
            originX = screenFrame.midX - (size.width / 2)
        }
        let musicTop = LockScreenPanelManager.shared.latestFrame(for: screen)?.maxY ?? (screenFrame.midY - 32)
        let timerFrame = LockScreenTimerWidgetPanelManager.shared.latestFrame(for: screen)

        let marginAboveMusic: CGFloat = 16
        let marginAboveTimer: CGFloat = 24
        let marginBelowWeather: CGFloat = 16

        let baseLowerBound = musicTop + marginAboveMusic
        let timerLowerBound = timerFrame.map { $0.maxY + marginAboveTimer }
        let minYFloor = screenFrame.minY + 80
        let lowerBound = max(timerLowerBound ?? baseLowerBound, minYFloor)

        let defaultWeatherBottom = screenFrame.midY + (screenFrame.height * 0.14)
        let minimumWeatherBottom = lowerBound + size.height + marginBelowWeather
        let weatherBottom = LockScreenWeatherPanelManager.shared.latestFrame(for: screen)?.minY ?? min(screenFrame.maxY - 120, max(defaultWeatherBottom, minimumWeatherBottom))

        let upperBound = weatherBottom - marginBelowWeather - size.height
        let clampedUpperBound = max(upperBound, lowerBound)

        let prefersTopAlignment = timerFrame != nil
        var proposedY: CGFloat

        if prefersTopAlignment {
            proposedY = clampedUpperBound
        } else {
            proposedY = (lowerBound + clampedUpperBound) / 2
        }

        let rawOffset = CGFloat(Defaults[.lockScreenReminderWidgetVerticalOffset])
        let clampedOffset = min(max(rawOffset, -160), 160)
        proposedY = max(lowerBound, min(proposedY + clampedOffset, clampedUpperBound))

        return NSRect(x: originX, y: proposedY, width: size.width, height: size.height)
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screens-did-wake")
        }

        workspaceObservers = [wakeObserver]
    }

    private func handleScreenGeometryChange(reason: String) {
        let anyVisible = windows.values.contains { $0.isVisible }
        guard anyVisible else { return }
        refreshPosition(animated: false)
        print("LockScreenReminderWidgetPanelManager: realigned window due to \(reason)")
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }
}


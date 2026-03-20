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

import SwiftUI
import AppKit
import SkyLightWindow
import Defaults
import QuartzCore
import Combine

@MainActor
final class LockScreenPanelAnimator: ObservableObject {
    @Published var isPresented: Bool = false
}

@MainActor
class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var windows: [NSScreen: NSWindow] = [:]
    private var hasDelegated: [NSScreen: Bool] = [:]
    private var collapsedFrames: [NSScreen: NSRect] = [:]
    private var isPanelExpanded = false
    private var currentAdditionalHeight: CGFloat = 0
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    
    private var latestFrames: [NSScreen: NSRect] = [:]
    func latestFrame(for screen: NSScreen) -> NSRect? { return latestFrames[screen] }

    private let panelAnimator = LockScreenPanelAnimator()
    private var hideTask: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("[\(timestamp())] LockScreenPanelManager: initialized")
        registerScreenChangeObservers()
        observeDefaultChanges()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
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

    func showPanel() {
        print("[\(timestamp())] LockScreenPanelManager: showPanel")

        guard Defaults[.enableLockScreenMediaWidget] else {
            print("[\(timestamp())] LockScreenPanelManager: widget disabled")
            hidePanel()
            return
        }

        hideTask?.cancel()
        panelAnimator.isPresented = false

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let targetFrame = collapsedFrame(for: screenFrame, on: screen)
            collapsedFrames[screen] = targetFrame

            let window: NSWindow
            if let existingWindow = windows[screen] {
                window = existingWindow
            } else {
                let newWindow = NSWindow(
                    contentRect: targetFrame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )

                newWindow.isReleasedWhenClosed = false
                newWindow.isOpaque = false
                newWindow.backgroundColor = .clear
                newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
                newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
                newWindow.isMovable = false
                newWindow.hasShadow = false

                ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)

                windows[screen] = newWindow
                window = newWindow
            }

            window.setFrame(targetFrame, display: true)
            latestFrames[screen] = targetFrame

            let hosting = NSHostingView(rootView: LockScreenMusicPanel(animator: panelAnimator))
            hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting

            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.masksToBounds = true
                content.layer?.cornerRadius = collapsedPanelCornerRadius
                content.layer?.backgroundColor = NSColor.clear.cgColor
            }

            if hasDelegated[screen] != true {
                SkyLightOperator.shared.delegateWindow(window)
                hasDelegated[screen] = true
            }

            window.orderFrontRegardless()
        }

        isPanelExpanded = false
        currentAdditionalHeight = 0
        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: false)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelAnimator.isPresented = true
        }

        print("[\(timestamp())] LockScreenPanelManager: panel visible")
    }

    func updatePanelSize(expanded: Bool, additionalHeight: CGFloat = 0, animated: Bool = true) {
        for (screen, window) in windows {
            guard let baseFrame = collapsedFrames[screen] else { continue }

            let baseSize = expanded ? LockScreenMusicPanel.expandedSize : LockScreenMusicPanel.collapsedSize
            let targetWidth = baseSize.width
            let targetHeight = baseSize.height + additionalHeight
            let originX = baseFrame.midX - (targetWidth / 2)
            let originY = baseFrame.origin.y
            let targetFrame = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.45
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                window.setFrame(targetFrame, display: true)
            }

            latestFrames[screen] = targetFrame

            let targetRadius = expanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.28)
                window.contentView?.layer?.cornerRadius = targetRadius
                CATransaction.commit()
            } else {
                window.contentView?.layer?.cornerRadius = targetRadius
            }
        }

        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: animated)
        isPanelExpanded = expanded
        currentAdditionalHeight = additionalHeight
    }

    func notifyTimerWidgetFrameChanged(animated: Bool) {
        let anyVisible = windows.values.contains { $0.isVisible }
        guard anyVisible || panelAnimator.isPresented else { return }
        applyOffsetAdjustment(animated: animated)
    }

    func applyOffsetAdjustment(animated: Bool = true) {
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            collapsedFrames[screen] = collapsedFrame(for: screenFrame, on: screen)
        }
        guard !windows.isEmpty else { return }
        updatePanelSize(expanded: isPanelExpanded, additionalHeight: currentAdditionalHeight, animated: animated)
    }

    func hidePanel() {
        print("[\(timestamp())] LockScreenPanelManager: hidePanel")

        panelAnimator.isPresented = false
        hideTask?.cancel()

        guard !windows.isEmpty else {
            print("LockScreenPanelManager: no panel to hide")
            latestFrames.removeAll()
            return
        }

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard let self else { return }
            await MainActor.run {
                for window in self.windows.values {
                    window.orderOut(nil)
                    window.contentView = nil
                }
                self.latestFrames.removeAll()
                print("[\(self.timestamp())] LockScreenPanelManager: panel hidden")
            }
        }
    }

    private func handleScreenGeometryChange(reason: String) {
        let anyVisible = windows.values.contains { $0.isVisible }
        guard anyVisible || panelAnimator.isPresented else { return }

        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            collapsedFrames[screen] = collapsedFrame(for: screenFrame, on: screen)
        }
        updatePanelSize(expanded: isPanelExpanded, additionalHeight: currentAdditionalHeight, animated: false)

        print("[\(timestamp())] LockScreenPanelManager: realigned window due to \(reason)")
    }

    private func observeDefaultChanges() {
        Defaults.publisher(.lockScreenMusicPanelWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyOffsetAdjustment(animated: true)
            }
            .store(in: &cancellables)
    }

    private func collapsedFrame(for screenFrame: NSRect, on screen: NSScreen) -> NSRect {
        let collapsedSize = LockScreenMusicPanel.collapsedSize
        let originX = screenFrame.midX - (collapsedSize.width / 2)
        let baseOriginY = screenFrame.origin.y + (screenFrame.height / 2) - collapsedSize.height - 32
        let defaultLowering: CGFloat = -28
        let userOffset = CGFloat(Defaults[.lockScreenMusicVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        var originY = baseOriginY + defaultLowering + clampedOffset

        if let timerFrame = LockScreenTimerWidgetPanelManager.shared.latestFrame(for: screen) {
            let maxAllowedTop = timerFrame.minY - 12
            let maxOriginY = maxAllowedTop - collapsedSize.height
            originY = min(originY, maxOriginY)
        }

        return NSRect(x: originX, y: originY, width: collapsedSize.width, height: collapsedSize.height)
    }
}

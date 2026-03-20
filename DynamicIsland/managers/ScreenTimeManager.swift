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

import Foundation
import AppKit
import Defaults
import Combine

class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    
    @Published var appUsages: [String: AppUsage] = [:]
    @Published var temporaryLimits: [String: TimeInterval] = [:]
    private var notifiedLimits: Set<String> = []
    
    @Published var isFocusModeActive: Bool = false
    
    var distractingApps: [String] {
        Defaults[.distractingApps].map { $0.lowercased() }
    }
    
    private var currentAppBundleId: String?
    private var currentAppStartTime: Date?
    private var timer: Timer?
    private var isLocked: Bool = false
    
    private init() {
        self.appUsages = Defaults[.screenTimeData]
        setupObservers()
        startTrackingCurrentApp()
        
        // Check for daily reset on startup
        checkDailyReset()
        
        // Periodic save every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDailyReset() // Check for day change BEFORE updating duration
            self?.updateCurrentAppDuration()
            self?.saveData()
        }
    }
    
    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    @objc private func screenLocked() {
        updateCurrentAppDuration()
        isLocked = true
    }
    
    @objc private func screenUnlocked() {
        isLocked = false
        currentAppStartTime = Date()
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard !isLocked else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        if isFocusModeActive, let appName = app.localizedName, distractingApps.contains(appName.lowercased()) {
            app.hide()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Focus Mode Active"
                alert.informativeText = "\(app.localizedName ?? "App") is blocked right now."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
            return
        }
        
        updateCurrentAppDuration()
        
        currentAppBundleId = app.bundleIdentifier
        currentAppStartTime = Date()
        
        if let bundleId = currentAppBundleId, appUsages[bundleId] == nil {
            appUsages[bundleId] = AppUsage(
                bundleId: bundleId,
                appName: app.localizedName ?? "Unknown",
                duration: 0,
                lastActive: Date()
            )
        }
    }
    
    private func startTrackingCurrentApp() {
        guard !isLocked else { return }
        if let app = NSWorkspace.shared.frontmostApplication {
            currentAppBundleId = app.bundleIdentifier
            currentAppStartTime = Date()
            
            if let bundleId = currentAppBundleId, appUsages[bundleId] == nil {
                appUsages[bundleId] = AppUsage(
                    bundleId: bundleId,
                    appName: app.localizedName ?? "Unknown",
                    duration: 0,
                    lastActive: Date()
                )
            }
        }
    }
    
    private func updateCurrentAppDuration() {
        guard !isLocked, let bundleId = currentAppBundleId, let startTime = currentAppStartTime else {
            return
        }
        
        let now = Date()
        let duration = now.timeIntervalSince(startTime)
        
        if var usage = appUsages[bundleId] {
            usage.duration += duration
            usage.lastActive = now
            appUsages[bundleId] = usage
            
            checkLimit(for: usage)
        }
        
        currentAppStartTime = now
    }
    
    private func checkLimit(for usage: AppUsage) {
        if let limit = temporaryLimits[usage.bundleId], usage.duration >= limit {
            if !notifiedLimits.contains(usage.bundleId) {
                notifiedLimits.insert(usage.bundleId)
                
                // Show notification via NSAlert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Limit Reached"
                    alert.informativeText = "You've exceeded your temporary limit for \(usage.appName)."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Ignore for 15 minutes")
                    
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    
                    if response == .alertSecondButtonReturn {
                        // Ignore for 15 minutes
                        if let currentLimit = self.temporaryLimits[usage.bundleId] {
                            self.temporaryLimits[usage.bundleId] = currentLimit + (15 * 60)
                            self.notifiedLimits.remove(usage.bundleId)
                        }
                    }
                }
            }
        }
    }
    
    func setTemporaryLimit(for bundleId: String, minutes: Double) {
        temporaryLimits[bundleId] = minutes * 60
        notifiedLimits.remove(bundleId) // Reset notification flag when limit is explicitly changed
    }
    
    func removeLimit(for bundleId: String) {
        temporaryLimits.removeValue(forKey: bundleId)
        notifiedLimits.remove(bundleId)
    }
    
    private func saveData() {
        Defaults[.screenTimeData] = appUsages
    }
    
    func resetStats() {
        print("ScreenTimeManager: Resetting stats for new day")
        appUsages.removeAll()
        notifiedLimits.removeAll()
        Defaults[.screenTimeData] = [:]
        startTrackingCurrentApp()
    }
    
    private func checkDailyReset() {
        let calendar = Calendar.current
        let now = Date()
        let resetHour = Defaults[.screenTimeResetHour]
        
        // Find the "most recent" reset time boundary
        var resetComponents = calendar.dateComponents([.year, .month, .day], from: now)
        resetComponents.hour = resetHour
        resetComponents.minute = 0
        resetComponents.second = 0
        
        guard var recentResetBoundary = calendar.date(from: resetComponents) else { return }
        
        // If the calculated boundary is in the future, it means the last reset should have happened 24h ago
        if recentResetBoundary > now {
            recentResetBoundary = calendar.date(byAdding: .day, value: -1, to: recentResetBoundary) ?? recentResetBoundary
        }
        
        guard let lastReset = Defaults[.lastScreenTimeResetDate] else {
            // First time, set it to the current boundary so we don't reset immediately
            Defaults[.lastScreenTimeResetDate] = recentResetBoundary
            return
        }
        
        // If our last recorded reset is older than the most recent boundary, reset now
        if lastReset < recentResetBoundary {
            resetStats()
            Defaults[.lastScreenTimeResetDate] = now
        }
    }
    
    var sortedUsages: [AppUsage] {
        appUsages.values.sorted { $0.duration > $1.duration }
    }
}

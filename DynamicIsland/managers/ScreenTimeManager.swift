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
    
    private var currentAppBundleId: String?
    private var currentAppStartTime: Date?
    private var timer: Timer?
    private var isLocked: Bool = false
    
    private init() {
        self.appUsages = Defaults[.screenTimeData]
        setupObservers()
        startTrackingCurrentApp()
        
        // Periodic save every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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
                
                // Show notification via ViewCoordinator
                DispatchQueue.main.async {
                    DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                        status: true,
                        type: .screenTimeLimit,
                        duration: 5.0,
                        icon: "hourglass.bottomhalf.filled",
                        title: "Limit Reached",
                        subtitle: "You've exceeded your temporary limit for \(usage.appName)."
                    )
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
        appUsages.removeAll()
        Defaults[.screenTimeData] = [:]
        startTrackingCurrentApp()
    }
    
    var sortedUsages: [AppUsage] {
        appUsages.values.sorted { $0.duration > $1.duration }
    }
}

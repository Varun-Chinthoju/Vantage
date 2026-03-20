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
import SwiftUI

@MainActor
class ContextualActionManager: ObservableObject {
    static let shared = ContextualActionManager()
    
    @Published var activeAppName: String = ""
    @Published var activeBundleId: String = ""
    @Published var actions: [ContextualAction] = []
    
    private init() {
        setupObservers()
        updateActiveApp()
    }
    
    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        updateActiveApp()
    }
    
    private func updateActiveApp() {
        if let app = NSWorkspace.shared.frontmostApplication {
            activeAppName = app.localizedName ?? "Unknown"
            activeBundleId = app.bundleIdentifier ?? ""
            updateActions(for: activeBundleId)
        }
    }
    
    private func updateActions(for bundleId: String) {
        var newActions: [ContextualAction] = []
        
        switch bundleId {
        case "com.apple.Safari":
            newActions = [
                ContextualAction(title: "Copy URL", icon: "link", color: .blue) {
                    try? await AppleScriptHelper.executeVoid("tell application \"Safari\" to set theURL to URL of front document\nset the clipboard to theURL")
                },
                ContextualAction(title: "Reader Mode", icon: "doc.text.magnifyingglass", color: .gray) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to tell process \"Safari\" to keystroke \"r\" using {command shift}")
                }
            ]
            
        case "com.google.Chrome":
            newActions = [
                ContextualAction(title: "Copy URL", icon: "link", color: .red) {
                    try? await AppleScriptHelper.executeVoid("tell application \"Google Chrome\" to set theURL to URL of active tab of front window\nset the clipboard to theURL")
                },
                ContextualAction(title: "Mute Tab", icon: "speaker.slash", color: .orange) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to tell process \"Google Chrome\" to keystroke \"m\" using {command shift}")
                }
            ]
            
        case "com.apple.dt.Xcode":
            newActions = [
                ContextualAction(title: "Build", icon: "hammer.fill", color: .blue) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to tell process \"Xcode\" to keystroke \"b\" using command down")
                },
                ContextualAction(title: "Clean", icon: "trash", color: .red) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to tell process \"Xcode\" to keystroke \"k\" using {command shift}")
                },
                ContextualAction(title: "Run", icon: "play.fill", color: .green) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to tell process \"Xcode\" to keystroke \"r\" using command down")
                }
            ]
            
        case "com.apple.Terminal", "com.googlecode.iterm2":
            newActions = [
                ContextualAction(title: "New Tab", icon: "plus", color: .gray) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to keystroke \"t\" using command down")
                },
                ContextualAction(title: "Clear", icon: "text.badge.xmark", color: .red) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to keystroke \"k\" using command down")
                }
            ]

        case "com.apple.Notes":
            newActions = [
                ContextualAction(title: "New Note", icon: "square.and.pencil", color: .yellow) {
                    try? await AppleScriptHelper.executeVoid("tell application \"Notes\" to make new note")
                }
            ]

        default:
            // Generic actions for any app
            newActions = [
                ContextualAction(title: "Copy", icon: "doc.on.doc", color: .gray) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to keystroke \"c\" using command down")
                },
                ContextualAction(title: "Paste", icon: "doc.on.clipboard", color: .gray) {
                    try? await AppleScriptHelper.executeVoid("tell application \"System Events\" to keystroke \"v\" using command down")
                }
            ]
        }
        
        self.actions = newActions
    }
}

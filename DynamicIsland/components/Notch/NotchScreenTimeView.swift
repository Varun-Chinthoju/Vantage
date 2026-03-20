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
import Defaults

struct NotchScreenTimeView: View {
    @ObservedObject var screenTimeManager = ScreenTimeManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    
    private let appIcons = AppIcons()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screen Time")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: {
                    screenTimeManager.resetStats()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            
            ScrollView {
                VStack(spacing: 8) {
                    if screenTimeManager.appUsages.isEmpty {
                        Text("No app usage recorded yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        ForEach(screenTimeManager.sortedUsages.prefix(10)) { usage in
                            AppUsageRow(usage: usage, icon: appIcons.getIcon(bundleID: usage.bundleId))
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AppUsageRow: View {
    let usage: AppUsage
    let icon: NSImage?
    
    @ObservedObject var screenTimeManager = ScreenTimeManager.shared
    @State private var showLimitPopover = false
    @State private var limitString = ""
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "app")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.appName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(usage.bundleId)
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(usage.formattedDuration)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
                
            Button(action: {
                showLimitPopover.toggle()
            }) {
                Image(systemName: "timer")
                    .foregroundColor(screenTimeManager.temporaryLimits[usage.bundleId] != nil ? .green : Color.gray.opacity(0.8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showLimitPopover, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    Text("Set Limit (mins)")
                        .font(.caption)
                    TextField("E.g., 30", text: $limitString)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 80)
                    
                    HStack {
                        Button("Apply") {
                            if let mins = Double(limitString) {
                                screenTimeManager.setTemporaryLimit(for: usage.bundleId, minutes: mins)
                            }
                            showLimitPopover = false
                        }
                        Button("Clear") {
                            screenTimeManager.removeLimit(for: usage.bundleId)
                            limitString = ""
                            showLimitPopover = false
                        }
                    }
                }
                .padding()
                .frame(width: 150)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

//
//  SettingsView.swift
//  Figlog
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var tracker: FocusTracker
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    let gracePeriodOptions: [TimeInterval] = [
        1 * 60,
        3 * 60,
        5 * 60,
        10 * 60,
        15 * 60
    ]

    let breakThresholdOptions: [TimeInterval] = [
        25 * 60,
        45 * 60,
        50 * 60,
        60 * 60,
        90 * 60
    ]

    var body: some View {
        TabView {
            Form {
                Section {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    if launchAtLogin.statusText != "On" && launchAtLogin.statusText != "Off" {
                        Text("Status: \(launchAtLogin.statusText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Picker("Grace period", selection: Binding(
                        get: { tracker.nonFigmaGracePeriod },
                        set: { tracker.setNonFigmaGracePeriod($0) }
                    )) {
                        ForEach(gracePeriodOptions, id: \.self) { duration in
                            Text(formatMinutes(duration)).tag(duration)
                        }
                    }
                    Text("Time allowed outside Figma before a session ends.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Break reminder", isOn: Binding(
                        get: { tracker.breakRemindersEnabled },
                        set: { tracker.setBreakRemindersEnabled($0) }
                    ))

                    Picker("Remind me after", selection: Binding(
                        get: { tracker.breakReminderThreshold },
                        set: { tracker.setBreakReminderThreshold($0) }
                    )) {
                        ForEach(breakThresholdOptions, id: \.self) { duration in
                            Text(formatMinutes(duration)).tag(duration)
                        }
                    }
                    .disabled(!tracker.breakRemindersEnabled)
                }
            }
            .padding(20)
            .frame(width: 400, height: 260)
            .tabItem {
                Label("General", systemImage: "gear")
            }
        }
    }

    private func formatMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        return "\(minutes) minutes"
    }
}

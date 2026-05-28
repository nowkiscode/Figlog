import SwiftUI
import AppKit

struct SettingsRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .frame(width: 160, alignment: .trailing)
                .padding(.top, 4) // Align with typical control heights
            
            content
            Spacer(minLength: 0)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var tracker: FocusTracker
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @AppStorage("appLanguage") private var appLanguage = "en"

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

    let idleThresholdOptions: [TimeInterval] = [
        30,
        60,
        120,
        180,
        300,
        600
    ]

    var body: some View {
        TabView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Language
                    SettingsRow("Language") {
                        Picker("", selection: $appLanguage) {
                            Text("English").tag("en")
                            Text("Korean").tag("ko")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    
                    Divider()
                    
                    // Launch
                    SettingsRow("Launch at login") {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("", isOn: Binding(
                                get: { launchAtLogin.isEnabled },
                                set: { launchAtLogin.setEnabled($0) }
                            ))
                            .labelsHidden()
                            
                            if launchAtLogin.statusText != "On" && launchAtLogin.statusText != "Off" {
                                Text("Status: \(launchAtLogin.statusText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Focus Tracker Settings
                    VStack(alignment: .leading, spacing: 20) {
                        SettingsRow("Idle after") {
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("", selection: Binding(
                                    get: { tracker.idleThreshold },
                                    set: { tracker.setIdleThreshold($0) }
                                )) {
                                    ForEach(idleThresholdOptions, id: \.self) { duration in
                                        Text(formatDuration(duration)).tag(duration)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                                
                                Text("Time without activity before a session is marked idle.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        SettingsRow("Grace period") {
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("", selection: Binding(
                                    get: { tracker.nonFigmaGracePeriod },
                                    set: { tracker.setNonFigmaGracePeriod($0) }
                                )) {
                                    ForEach(gracePeriodOptions, id: \.self) { duration in
                                        Text(formatMinutes(duration)).tag(duration)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 140)
                                
                                Text("Time allowed outside Figma before a session ends.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        
                        SettingsRow("Break reminder") {
                            Toggle("", isOn: Binding(
                                get: { tracker.breakRemindersEnabled },
                                set: { tracker.setBreakRemindersEnabled($0) }
                            ))
                            .labelsHidden()
                        }
                        
                        SettingsRow("Remind me after") {
                            Picker("", selection: Binding(
                                get: { tracker.breakReminderThreshold },
                                set: { tracker.setBreakReminderThreshold($0) }
                            )) {
                                ForEach(breakThresholdOptions, id: \.self) { duration in
                                    Text(formatMinutes(duration)).tag(duration)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            .disabled(!tracker.breakRemindersEnabled)
                        }
                    }
                    
                    Divider()
                    
                    // Privacy
                    SettingsRow("Privacy") {
                        VStack(alignment: .leading, spacing: 4) {
                            let shareBinding = Binding(
                                get: { FirebaseManager.shared.currentUserProfile?.shareHistory ?? true },
                                set: { FirebaseManager.shared.updateShareHistory($0) }
                            )
                            Toggle("Share My Detailed Focus Statistics with Party Members", isOn: shareBinding)
                        }
                    }
                }
                .padding(32)
            }
            .frame(minWidth: 480, minHeight: 450)
            .tabItem {
                Label("General", systemImage: "gear")
            }
        }
    }

    private func formatMinutes(_ duration: TimeInterval) -> String {
        FocusTracker.formatCompactDuration(duration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        FocusTracker.formatCompactDuration(duration)
    }
}

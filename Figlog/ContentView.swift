//
//  ContentView.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import SwiftUI
import AppKit

struct ContentView: View {

    @ObservedObject var tracker: FocusTracker
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(tracker.formattedTodayFocusTime)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                statusRow
            }

            Divider()

            statsRow

            timeline

            controls

            recentSessions

            Spacer(minLength: 0)

            footer
        }
        .padding(24)
        .frame(width: 420, height: 520)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FigLog")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Real Figma focus time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("v\(appVersion) Beta")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text(tracker.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Quit FigLog") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statBlock(title: "Sessions", value: "\(tracker.todaySessionCount)")
            statBlock(title: "Idle after", value: tracker.formattedIdleThreshold)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("00:00 - 24:00")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            TimelineStrip(
                sessions: tracker.timelineSessions,
                dayStart: tracker.timelineStart,
                dayEnd: tracker.timelineEnd,
                isTracking: tracker.isTracking
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            settingRow(
                title: "Break reminder",
                detail: tracker.breakReminderLabel,
                isOn: Binding(
                    get: { tracker.breakRemindersEnabled },
                    set: { tracker.setBreakRemindersEnabled($0) }
                )
            )

            settingRow(
                title: "Launch at login",
                detail: launchAtLogin.statusText,
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)

            if tracker.hasRecentSessions {
                VStack(spacing: 6) {
                    ForEach(tracker.recentSessions) { session in
                        sessionRow(session)
                    }
                }
            } else {
                Text("No Figma focus sessions yet today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(height: 54, alignment: .topLeading)
            }
        }
    }

    private var statusColor: Color {
        if tracker.isTracking {
            return .green
        }

        if tracker.isIdle {
            return .orange
        }

        return .gray
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                    .font(.caption)

                Spacer()

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func sessionRow(_ session: FocusSession) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.id == tracker.recentSessions.first?.id && tracker.isTracking ? .green : .gray.opacity(0.55))
                .frame(width: 6, height: 6)

            Text(FocusTracker.formatTimeRange(for: session))
                .font(.caption)
                .monospacedDigit()

            Spacer()

            Text(FocusTracker.formatCompactDuration(session.duration))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: 16)
    }
}

private struct TimelineStrip: View {

    let sessions: [FocusSession]
    let dayStart: Date
    let dayEnd: Date
    let isTracking: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                ForEach(sessions) { session in
                    Capsule()
                        .fill(session.id == sessions.last?.id && isTracking ? .green : .secondary.opacity(0.55))
                        .frame(
                            width: segmentWidth(for: session, totalWidth: proxy.size.width),
                            height: 10
                        )
                        .offset(x: segmentOffset(for: session, totalWidth: proxy.size.width))
                }
            }
        }
        .frame(height: 10)
    }

    private func segmentOffset(for session: FocusSession, totalWidth: CGFloat) -> CGFloat {
        let dayDuration = max(1, dayEnd.timeIntervalSince(dayStart))
        let secondsFromStart = max(0, session.startedAt.timeIntervalSince(dayStart))
        let ratio = min(1, secondsFromStart / dayDuration)

        return totalWidth * ratio
    }

    private func segmentWidth(for session: FocusSession, totalWidth: CGFloat) -> CGFloat {
        let dayDuration = max(1, dayEnd.timeIntervalSince(dayStart))
        let rawWidth = totalWidth * max(0, session.duration) / dayDuration

        return max(3, rawWidth)
    }
}

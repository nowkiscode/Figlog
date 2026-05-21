//
//  ContentView.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import SwiftUI
import AppKit

struct ContentView: View {

    @Environment(\.openSettings) private var openSettings
    @ObservedObject var tracker: FocusTracker
    @State private var showingHistory = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showingHistory {
                historyView
            } else {
                mainView
            }
        }
        .padding(24)
        .frame(width: 420, height: 520)
    }

    private var mainView: some View {
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

            recentSessions

            Spacer(minLength: 0)

            footer
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button(action: { showingHistory = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Spacer()

                Text("Weekly History")
                    .font(.headline)

                Spacer()
                
                Color.clear.frame(width: 40, height: 1)
            }

            let stats = tracker.getWeeklyStats()
            let totalTime = stats.reduce(0) { $1.totalFocusTime + $0 }
            let totalIdle = stats.reduce(0) { $1.totalIdleTime + $0 }
            let avgTime = stats.isEmpty ? 0 : totalTime / Double(stats.count)
            let avgIdle = stats.isEmpty ? 0 : totalIdle / Double(stats.count)
            let maxTime = stats.map { $0.totalFocusTime }.max() ?? 1

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 40) {
                    VStack(alignment: .leading) {
                        Text("Total Focus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FocusTracker.formatCompactDuration(totalTime))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Daily Avg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FocusTracker.formatCompactDuration(avgTime))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                
                HStack(spacing: 40) {
                    VStack(alignment: .leading) {
                        Text("Total Idle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FocusTracker.formatCompactDuration(totalIdle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Avg Idle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FocusTracker.formatCompactDuration(avgIdle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)

            // Simple Bar Chart
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(lastSevenDays(), id: \.self) { date in
                    let record = stats.first { Calendar.current.isDate($0.day, inSameDayAs: date) }
                    let height = record.map { CGFloat(($0.totalFocusTime / maxTime) * 140) } ?? 0
                    
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(record != nil ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: max(4, height))
                        
                        Text(dayLabel(for: date))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 160)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                Text("Insights")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let bestDay = stats.max(by: { $0.totalFocusTime < $1.totalFocusTime }) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)
                        Text("Best focus on \(dayLabel(for: bestDay.day)): \(FocusTracker.formatCompactDuration(bestDay.totalFocusTime))")
                            .font(.subheadline)
                    }
                } else {
                    Text("Start focusing to see your trends!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private func lastSevenDays() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
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

            Text("v\(appVersion)")
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

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "Settings" || window.title == "Figlog Settings" {
                    window.makeKeyAndOrderFront(nil)
                }
                
                if #available(macOS 14.0, *) {
                    openSettings()
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")

            Text("•")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("History") {
                showingHistory = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Text("•")
                .font(.caption)
                .foregroundStyle(.tertiary)

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
            statBlock(title: "Idle Today", value: FocusTracker.formatCompactDuration(tracker.todayIdleTime))
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

    @State private var hoveredSegmentId: UUID? = nil

    struct TimelineSegment: Identifiable {
        let id: UUID
        let startedAt: Date
        var endedAt: Date
        var duration: TimeInterval
        var isCurrent: Bool
    }

    private var processedSegments: [TimelineSegment] {
        guard !sessions.isEmpty else { return [] }
        
        var segments: [TimelineSegment] = []
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        
        for session in sorted {
            let isCurrent = (session.id == sessions.last?.id && isTracking)
            
            if let last = segments.last,
               !last.isCurrent,
               !isCurrent,
               session.startedAt.timeIntervalSince(last.endedAt) <= 120 {
                segments[segments.count - 1].endedAt = session.endedAt
                segments[segments.count - 1].duration += session.duration
            } else {
                segments.append(TimelineSegment(
                    id: session.id,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    duration: session.duration,
                    isCurrent: isCurrent
                ))
            }
        }
        return segments
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)

                ForEach(processedSegments) { segment in
                    let isHovered = hoveredSegmentId == segment.id
                    
                    Capsule()
                        .fill(segmentColor(for: segment))
                        .frame(
                            width: segmentWidth(for: segment, totalWidth: proxy.size.width),
                            height: isHovered ? 14 : 12
                        )
                        .offset(x: segmentOffset(for: segment, totalWidth: proxy.size.width))
                        .scaleEffect(isHovered ? 1.05 : 1.0, anchor: .center)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
                        .help(tooltipText(for: segment))
                        .onHover { hovering in
                            hoveredSegmentId = hovering ? segment.id : nil
                        }
                }
            }
        }
        .frame(height: 14)
    }

    private func segmentColor(for segment: TimelineSegment) -> Color {
        if segment.isCurrent {
            return .green
        }
        if segment.duration > 15 * 60 {
            return Color.accentColor
        }
        return Color.accentColor.opacity(0.7)
    }

    private func tooltipText(for segment: TimelineSegment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: segment.startedAt)
        let end = formatter.string(from: segment.endedAt)
        let durationStr = FocusTracker.formatCompactDuration(segment.duration)
        return "\(start) - \(end) (\(durationStr))"
    }

    private func segmentOffset(for segment: TimelineSegment, totalWidth: CGFloat) -> CGFloat {
        let dayDuration = max(1, dayEnd.timeIntervalSince(dayStart))
        let secondsFromStart = max(0, segment.startedAt.timeIntervalSince(dayStart))
        let ratio = min(1, secondsFromStart / dayDuration)

        return totalWidth * ratio
    }

    private func segmentWidth(for segment: TimelineSegment, totalWidth: CGFloat) -> CGFloat {
        let dayDuration = max(1, dayEnd.timeIntervalSince(dayStart))
        let rawWidth = totalWidth * max(0, segment.duration) / dayDuration

        let visualWidth = max(3, rawWidth)
        let offset = segmentOffset(for: segment, totalWidth: totalWidth)
        if offset + visualWidth > totalWidth {
            return max(3, totalWidth - offset)
        }
        return visualWidth
    }
}

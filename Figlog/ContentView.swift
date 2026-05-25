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
    @Environment(\.locale) private var locale
    @ObservedObject var tracker: FocusTracker
    @State private var showingHistory = false
    @State private var showingHelp = false
    @State private var historyPeriod: Int = 30
    @State private var cachedStats: [DailyFocusRecord] = []
    
    enum Tab {
        case stats, social
    }
    @State private var selectedTab: Tab = .stats

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.2"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showingHistory {
                historyView
            } else {
                header
                
                Picker("", selection: $selectedTab) {
                    Text("My Stats").tag(Tab.stats)
                    Text("Friends").tag(Tab.social)
                }
                .pickerStyle(.segmented)
                
                if selectedTab == .stats {
                    mainViewContent
                } else {
                    SocialView()
                }
                
                Spacer(minLength: 0)
                
                footer
            }
        }
        .padding(24)
        .frame(width: 420, height: 520, alignment: .top)
        .onChange(of: showingHistory) { _, newValue in
            if newValue {
                Task { await loadStats() }
            }
        }
    }
    
    private func loadStats() async {
        let period = historyPeriod
        let newStats = tracker.getStats(days: period)
        self.cachedStats = newStats
    }
    
    private var mainViewContent: some View {
        VStack(alignment: .leading, spacing: 20) {

            VStack(alignment: .leading, spacing: 8) {
                Text(tracker.formattedTodayFocusTime)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))

                statusRow
            }

            Divider()

            statsRow

            timeline

            recentSessions
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
            }

            HStack {
                Picker("", selection: $historyPeriod) {
                    Text("Weekly").tag(7)
                    Text("Monthly").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: historyPeriod) { _, _ in
                    Task { await loadStats() }
                }
                Spacer()
            }
            .padding(.bottom, 4)

            let stats = cachedStats
            let totalTime = stats.reduce(0) { $1.totalFocusTime + $0 }
            let totalIdle = stats.reduce(0) { $1.totalIdleTime + $0 }
            let periodTitle: LocalizedStringKey = historyPeriod == 7 ? "Last 7 Days" : "Last 30 Days"
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 40) {
                    statBlock(title: periodTitle, value: FocusTracker.formatCompactDuration(totalTime))
                    statBlock(title: "Idle Total", value: FocusTracker.formatCompactDuration(totalIdle))
                }
            }
            .padding(.vertical, 8)

            Text("Activity Heatmap")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading) {
                if historyPeriod == 7 {
                    weeklyBarChart(stats: stats)
                        .padding(.top, 4)
                } else {
                    calendarHeatmap(stats: stats, period: historyPeriod)
                        .padding(.top, 4)
                }
            }
            .frame(height: 160, alignment: .top)
            
            Spacer()
        }
    }

    private func calendarHeatmap(stats: [DailyFocusRecord], period: Int) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let days = lastNDays(period)
        let maxTime = stats.map { $0.totalFocusTime }.max() ?? 1

        var localCalendar = Calendar.current
        localCalendar.locale = locale
        let weekdays = localCalendar.shortWeekdaySymbols

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if date > Calendar.current.startOfDay(for: Date()) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.clear)
                            .aspectRatio(1, contentMode: .fit)
                    } else if let record = stats.first(where: { Calendar.current.isDate($0.day, inSameDayAs: date) }) {
                        let intensity = record.totalFocusTime / maxTime
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(max(0.15, intensity)))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(dayLabel(for: date)): \(FocusTracker.formatCompactDuration(record.totalFocusTime))")
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .aspectRatio(1, contentMode: .fit)
                            .help("\(dayLabel(for: date)): No activity")
                    }
                }
            }
        }
    }

    private func weeklyBarChart(stats: [DailyFocusRecord]) -> some View {
        let days = lastNDays(7)
        let maxTime = stats.map { $0.totalFocusTime }.max() ?? 1

        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(days, id: \.self) { date in
                let record = stats.first(where: { Calendar.current.isDate($0.day, inSameDayAs: date) })
                let focusTime = record?.totalFocusTime ?? 0
                let heightRatio = focusTime > 0 ? (focusTime / maxTime) : 0
                
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(focusTime > 0 ? Color.accentColor : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: max(4, 100 * heightRatio))
                        .help("\(dayLabel(for: date)): \(FocusTracker.formatCompactDuration(focusTime))")
                        
                    Text(shortDayLabel(for: date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(date > Date() ? .clear : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func shortDayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }

    private func lastNDays(_ daysCount: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today)!
        
        let gridCells = daysCount <= 7 ? 7 : 35
        return (0..<gridCells).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: endOfWeek) }
    }

    private func dayLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
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

            Button(action: {
                tracker.togglePause()
            }) {
                Image(systemName: tracker.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.title2)
                    .foregroundStyle(tracker.isPaused ? .green : .orange)
            }
            .buttonStyle(.borderless)
            .help(tracker.isPaused ? String(localized: "Resume tracking") : String(localized: "Pause tracking"))

            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
                
            Button(action: { showingHelp.toggle() }) {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .popover(isPresented: $showingHelp) {
                HelpView()
                    .environment(\.locale, locale)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            Text(LocalizedStringKey(tracker.statusText))
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
        if tracker.isPaused {
            return .orange
        }
        if tracker.isTracking {
            return .green
        }
        if tracker.isIdle {
            return .yellow
        }
        return .gray
    }

    private func statBlock(title: LocalizedStringKey, value: String) -> some View {
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
            ZStack(alignment: .bottomLeading) {
                // Background Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)
                    .offset(y: -1)

                // 6-hour Ticks (06:00, 12:00, 18:00)
                ForEach(1..<4, id: \.self) { i in
                    let ratio = CGFloat(i) / 4.0
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: 12)
                        .offset(x: proxy.size.width * ratio, y: -1)
                }

                ForEach(processedSegments) { segment in
                    TimelineSegmentView(
                        segment: segment,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        totalWidth: proxy.size.width
                    )
                }
                
                // Current Time Indicator
                if Calendar.current.isDate(Date(), inSameDayAs: dayStart) {
                    let nowRatio = min(1, max(0, Date().timeIntervalSince(dayStart) / max(1, dayEnd.timeIntervalSince(dayStart))))
                    Rectangle()
                        .fill(Color.red.opacity(0.6))
                        .frame(width: 2, height: 14)
                        .offset(x: proxy.size.width * nowRatio, y: 0)
                }
            }
        }
        .frame(height: 14)
    }

}

private struct TimelineSegmentView: View {
    let segment: TimelineStrip.TimelineSegment
    let dayStart: Date
    let dayEnd: Date
    let totalWidth: CGFloat

    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(segmentColor(for: segment))
            .frame(
                width: segmentWidth(for: segment, totalWidth: totalWidth),
                height: isHovered ? 14 : 12
            )
            .offset(
                x: segmentOffset(for: segment, totalWidth: totalWidth),
                y: isHovered ? .zero : -1
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
            .help(tooltipText(for: segment))
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func segmentColor(for segment: TimelineStrip.TimelineSegment) -> Color {
        if segment.isCurrent {
            return .green
        }
        if segment.duration > 15 * 60 {
            return Color.accentColor
        }
        return Color.accentColor.opacity(0.7)
    }

    private func tooltipText(for segment: TimelineStrip.TimelineSegment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: segment.startedAt)
        let end = formatter.string(from: segment.endedAt)
        let durationStr = FocusTracker.formatCompactDuration(segment.duration)
        return "\(start) - \(end) (\(durationStr))"
    }

    private func segmentOffset(for segment: TimelineStrip.TimelineSegment, totalWidth: CGFloat) -> CGFloat {
        let dayDuration = max(1, dayEnd.timeIntervalSince(dayStart))
        let secondsFromStart = max(0, segment.startedAt.timeIntervalSince(dayStart))
        let ratio = min(1, secondsFromStart / dayDuration)

        return totalWidth * ratio
    }

    private func segmentWidth(for segment: TimelineStrip.TimelineSegment, totalWidth: CGFloat) -> CGFloat {
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

struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use FigLog")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Timeline Colors:")
                    .font(.subheadline).bold()
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("Green: Currently tracking Figma session")
                }
                HStack {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    Text("Blue: Completed focus session (> 15m)")
                }
                HStack {
                    Circle().fill(Color.accentColor.opacity(0.7)).frame(width: 8, height: 8)
                    Text("Light Blue: Short focus session (< 15m)")
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Grace Period:")
                    .font(.subheadline).bold()
                Text("Allows you to switch to other apps briefly without breaking your current focus session. If you return to Figma within this time, the session continues uninterrupted. If not, the timer stops and deducts the grace period.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Pause/Resume:")
                    .font(.subheadline).bold()
                Text("Manually pause tracking if you want to keep Figma open but stop the timer. It will automatically resume the next time you actively use Figma.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

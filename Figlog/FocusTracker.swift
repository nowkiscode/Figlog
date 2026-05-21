//
//  FocusTracker.swift
//  Figlog
//
//  Created by Codex on 5/21/26.
//

import AppKit
import Combine
import Foundation
import UserNotifications

struct FocusSession: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
}

@MainActor
final class FocusTracker: ObservableObject {

    enum TrackingState {
        case tracking
        case activeOutsideFigma
        case idle
        case waitingForFigma
    }

    @Published private(set) var isTracking = false
    @Published private(set) var isIdle = false
    @Published private(set) var isUsingFigma = false
    @Published private(set) var todayFocusTime: TimeInterval = 0
    @Published private(set) var todaySessions: [FocusSession] = []
    @Published private(set) var breakRemindersEnabled = true

    let idleThreshold: TimeInterval = 60
    let nonFigmaGracePeriod: TimeInterval = 5 * 60
    let breakReminderThreshold: TimeInterval = 50 * 60

    private let figmaBundleIdentifier = "com.figma.Desktop"
    private let storageKey = "FigLog.FocusTracker.Snapshot"
    private let breakReminderKey = "FigLog.FocusTracker.BreakRemindersEnabled"
    private var timerCancellable: AnyCancellable?
    private var activeSession: FocusSession?
    private var didSendBreakReminderForActiveSession = false
    private var currentDay = Calendar.current.startOfDay(for: Date())
    private var hasEnteredFocusSession = false
    private var nonFigmaActivityDuration: TimeInterval = 0

    init() {
        restoreSettings()
        restoreSnapshot()
        requestNotificationAuthorization()
        start()
    }

    var trackingState: TrackingState {
        if isTracking {

            if isUsingFigma {
                return .tracking
            }

            return .activeOutsideFigma
        }

        if isIdle {
            return .idle
        }

        return .waitingForFigma
    }

    var statusText: String {
        switch trackingState {
        case .tracking:
            return "Tracking Figma"

        case .activeOutsideFigma:
            return "Out of Figma but still tracking"

        case .idle:
            return "Idle"

        case .waitingForFigma:
            return "Waiting for Figma"
        }
    }

    var formattedTodayFocusTime: String {
        Self.formatDuration(todayFocusTime)
    }

    var formattedIdleThreshold: String {
        "\(Int(idleThreshold))s"
    }

    var todaySessionCount: Int {
        todaySessions.count + (activeSession == nil ? 0 : 1)
    }

    var breakReminderLabel: String {
        "After \(Self.formatCompactDuration(breakReminderThreshold))"
    }

    var recentSessions: [FocusSession] {
        let sessions = todaySessions + [activeSession].compactMap { $0 }
        return Array(sessions.suffix(3).reversed())
    }

    var timelineSessions: [FocusSession] {
        todaySessions + [activeSession].compactMap { $0 }
    }

    var hasRecentSessions: Bool {
        !recentSessions.isEmpty
    }

    var timelineStart: Date {
        currentDay
    }

    var timelineEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay.addingTimeInterval(24 * 60 * 60)
    }

    func setBreakRemindersEnabled(_ enabled: Bool) {
        breakRemindersEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: breakReminderKey)

        if enabled {
            requestNotificationAuthorization()
        }
    }

    func start() {
        guard timerCancellable == nil else { return }

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        endActiveSession(at: Date())
        persistSnapshot()
    }

    private func tick() {
        let now = Date()
        rollOverDayIfNeeded(now)

        let activeApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let mouseIdle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )

        let keyboardIdle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .keyDown
        )

        let clickIdle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .leftMouseDown
        )

        let idleTime = min(mouseIdle, keyboardIdle, clickIdle)

        isIdle = idleTime >= idleThreshold

        let isFigmaActive = activeApp == figmaBundleIdentifier
        isUsingFigma = isFigmaActive

        if isFigmaActive && !isIdle {
            hasEnteredFocusSession = true
            nonFigmaActivityDuration = 0
        }

        if hasEnteredFocusSession && !isIdle {

            if !isFigmaActive {
                nonFigmaActivityDuration += 1
            } else {
                nonFigmaActivityDuration = 0
            }

            if nonFigmaActivityDuration >= nonFigmaGracePeriod {
                isTracking = false
                hasEnteredFocusSession = false
                endActiveSession(at: now)
            } else {
                isTracking = true
                todayFocusTime += 1
                updateActiveSession(at: now)
            }

        } else {
            isTracking = false

            if isIdle {
                nonFigmaActivityDuration = 0
                hasEnteredFocusSession = false
                endActiveSession(at: now)
            }
        }

        persistSnapshot()
    }

    private func updateActiveSession(at date: Date) {
        if activeSession == nil {
            activeSession = FocusSession(
                id: UUID(),
                startedAt: date,
                endedAt: date,
                duration: 0
            )
        }

        activeSession?.endedAt = date
        activeSession?.duration += 1

        if let activeSession {
            sendBreakReminderIfNeeded(for: activeSession)
        }
    }

    private func endActiveSession(at date: Date) {
        guard var session = activeSession else { return }

        session.endedAt = date

        if session.duration > 0 {
            todaySessions.append(session)
        }

        activeSession = nil
        hasEnteredFocusSession = false
        nonFigmaActivityDuration = 0
        didSendBreakReminderForActiveSession = false
    }

    private func rollOverDayIfNeeded(_ date: Date) {
        let startOfToday = Calendar.current.startOfDay(for: date)

        guard startOfToday != currentDay else { return }

        endActiveSession(at: date)
        currentDay = startOfToday
        todayFocusTime = 0
        todaySessions = []
        persistSnapshot()
    }

    private func restoreSettings() {
        guard UserDefaults.standard.object(forKey: breakReminderKey) != nil else { return }
        breakRemindersEnabled = UserDefaults.standard.bool(forKey: breakReminderKey)
    }

    private func restoreSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())

        guard snapshot.day == startOfToday else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            currentDay = startOfToday
            return
        }

        currentDay = snapshot.day
        todayFocusTime = snapshot.todayFocusTime
        todaySessions = snapshot.todaySessions
    }

    private func persistSnapshot() {
        let snapshot = Snapshot(
            day: currentDay,
            todayFocusTime: todayFocusTime,
            todaySessions: todaySessions
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendBreakReminderIfNeeded(for session: FocusSession) {
        guard breakRemindersEnabled else { return }
        guard !didSendBreakReminderForActiveSession else { return }
        guard session.duration >= breakReminderThreshold else { return }
        
        print("🔥 BREAK REMINDER TRIGGERED")
        

        let content = UNMutableNotificationContent()
        content.title = "Time for a short break"
        content.body = "You have focused in Figma for \(Self.formatCompactDuration(breakReminderThreshold))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "figlog.break-reminder.\(session.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in

            if let error {
                print("❌ Notification error: \(error.localizedDescription)")
                return
            }

            print("✅ Break reminder delivered")

            Task { @MainActor in
                self?.didSendBreakReminderForActiveSession = true
            }
        }
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func formatCompactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int(duration) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    static func formatTimeRange(for session: FocusSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        return "\(formatter.string(from: session.startedAt)) - \(formatter.string(from: session.endedAt))"
    }
}

private struct Snapshot: Codable {
    let day: Date
    let todayFocusTime: TimeInterval
    let todaySessions: [FocusSession]
}

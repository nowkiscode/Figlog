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
import os

struct FocusSession: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var appName: String?
}

@MainActor
final class FocusTracker: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    enum TrackingState {
        case tracking
        case activeOutsideTargetApp
        case idle
        case waitingForTargetApp
        case paused
    }

    @Published private(set) var isTracking = false
    @Published private(set) var isIdle = false
    @Published private(set) var isPaused = false
    @Published private(set) var isUsingTargetApp = false
    @Published private(set) var todayFocusTime: TimeInterval = 0
    @Published private(set) var todayIdleTime: TimeInterval = 0
    @Published private(set) var todaySessions: [FocusSession] = []
    @Published private(set) var breakRemindersEnabled = true

    @Published private(set) var idleThreshold: TimeInterval = 60
    @Published private(set) var nonTargetAppGracePeriod: TimeInterval = 5 * 60
    @Published private(set) var breakReminderThreshold: TimeInterval = 50 * 60

    private let idleThresholdKey = "FigLog.FocusTracker.IdleThreshold"
    private let breakReminderKey = "FigLog.FocusTracker.BreakRemindersEnabled"
    private let gracePeriodKey = "FigLog.FocusTracker.NonFigmaGracePeriod"
    private let breakThresholdKey = "FigLog.FocusTracker.BreakReminderThreshold"
    private let sessionStore = FocusSessionStore()
    private var timerTask: Task<Void, Never>?
    private var activeSession: FocusSession?
    private var didSendBreakReminderForActiveSession = false
    private var currentDay = Calendar.current.startOfDay(for: Date())
    
    // Firebase Syncing
    private var lastSyncedTrackingState: TrackingState?
    private var lastSyncedAppName: String?
    private var lastFirebaseSyncDate: Date?
    private var hasEnteredFocusSession = false
    private var nonTargetAppActivityDuration: TimeInterval = 0

    private var lastTickDate = Date()
    private var lastEmergencyAutosaveAt = Date()
    private var notificationCancellables = Set<AnyCancellable>()

    
    struct TargetApp: Identifiable, Equatable {
        let id: String // Main identifier
        let name: String
        let bundleIDs: [String]
    }

    static let supportedApps: [TargetApp] = [
        TargetApp(id: "Figma", name: "Figma", bundleIDs: ["com.figma.Desktop"]),
        TargetApp(id: "Framer", name: "Framer", bundleIDs: ["com.framer.electron", "com.framer.desktop"]),
        TargetApp(id: "PowerPoint", name: "PowerPoint", bundleIDs: ["com.microsoft.Powerpoint"])
    ]

    @Published private(set) var activeTargetAppName: String? = nil
    @Published private(set) var enabledTargetAppIDs: Set<String> = ["Figma", "Framer", "PowerPoint"]


    override init() {
        super.init()
        restoreSettings()
        restoreSnapshot()
        setupNotificationCategories()
        requestNotificationAuthorization()
        setupNotificationObservers()
        start()
        UNUserNotificationCenter.current().delegate = self
    }

    private func setupNotificationCategories() {
        let skipAction = UNNotificationAction(identifier: "SKIP_BREAK", title: "Skip", options: [])
        let takeBreakAction = UNNotificationAction(identifier: "TAKE_BREAK", title: "Take Break", options: [.foreground])
        
        let category = UNNotificationCategory(
            identifier: "BREAK_REMINDER_CATEGORY",
            actions: [skipAction, takeBreakAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func setupNotificationObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        
        wsCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleWillSleep()
                }
            }
            .store(in: &notificationCancellables)
            
        wsCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleDidWake()
                }
            }
            .store(in: &notificationCancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleWillTerminate()
                }
            }
            .store(in: &notificationCancellables)
    }

    private func handleWillSleep() {
        print("💤 System will sleep. Ending active session and saving...")
        let now = Date()
        endActiveSession(at: now)
        persistSnapshot()
        timerTask?.cancel()
        timerTask = nil
    }

    private func handleDidWake() {
        print("☀️ System did wake. Resetting timers...")
        lastTickDate = Date()
        lastEmergencyAutosaveAt = Date()
        start()
    }

    private func handleWillTerminate() {
        print("🛑 App will terminate. Saving...")
        stop()
    }

    var trackingState: TrackingState {
        if isPaused {
            return .paused
        }

        if isTracking {
            if isUsingTargetApp {
                return .tracking
            }
            return .activeOutsideTargetApp
        }

        if isIdle {
            return .idle
        }

        return .waitingForTargetApp
    }

    var statusText: String {
        switch trackingState {
        case .paused:
            return "Paused"
        case .tracking:
            let app = activeTargetAppName ?? "app"
            return String(localized: "Working in \(app)")
        case .activeOutsideTargetApp:
            return "Out of app but still tracking"
        case .idle:
            return "Idle"
        case .waitingForTargetApp:
            return "Waiting for app"
        }
    }

    var formattedTodayFocusTime: String {
        Self.formatDuration(todayFocusTime)
    }

    var formattedIdleThreshold: String {
        Self.formatCompactDuration(idleThreshold)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            let now = Date()
            isTracking = false
            hasEnteredFocusSession = false
            endActiveSession(at: now)
        } else {
            // Resume updates implicitly on next tick if Figma is active
        }
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
        print("Break reminder set to \(enabled)")
    }

    func setEnabledTargetAppIDs(_ ids: Set<String>) {
        enabledTargetAppIDs = ids
        UserDefaults.standard.set(Array(ids), forKey: "FigLog.FocusTracker.EnabledTargetAppIDs")
    }
    
    func setNonTargetAppGracePeriod(_ period: TimeInterval) {
        nonTargetAppGracePeriod = period
        UserDefaults.standard.set(period, forKey: gracePeriodKey)
        print("GracePeriod Time set \(period)")
    }

    func setBreakReminderThreshold(_ threshold: TimeInterval) {
        breakReminderThreshold = threshold
        UserDefaults.standard.set(threshold, forKey: breakThresholdKey)
        print("Break reminder Time set \(threshold)")
    }

    func setIdleThreshold(_ threshold: TimeInterval) {
        idleThreshold = threshold
        UserDefaults.standard.set(threshold, forKey: idleThresholdKey)
        print("Idle after Time set \(threshold)")
    }

    func start() {
        guard timerTask == nil else { return }
        lastTickDate = Date()
        lastEmergencyAutosaveAt = Date()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil

        endActiveSession(at: Date())
        persistSnapshot()
        
        FirebaseManager.shared.updateMyStatus(status: "offline", activeAppName: nil, todayFocusTime: todayFocusTime)
    }

    private func tick() {
        let now = Date()
        
        let delta = now.timeIntervalSince(lastTickDate)
        if delta >= 60.0 {
            print("🛡️ Gap protection triggered: delta of \(String(format: "%.2f", delta)) seconds detected. Ending previous session at \(lastTickDate)")
            endActiveSession(at: lastTickDate)
            rollOverDayIfNeeded(now)
            lastTickDate = now
            lastEmergencyAutosaveAt = now
            return
        }
        
        lastTickDate = now
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
        
        if isIdle {
            todayIdleTime += 1
        }

        var isTargetAppActive = false
        var currentAppName: String? = nil
        if let activeApp = activeApp, let matchedApp = Self.supportedApps.first(where: { $0.bundleIDs.contains(activeApp) }), enabledTargetAppIDs.contains(matchedApp.id) {
            isTargetAppActive = true
            currentAppName = matchedApp.name
        }
        isUsingTargetApp = isTargetAppActive
        if isTargetAppActive {
            if activeTargetAppName != currentAppName {
                let msg = "🎯 Target App Changed to: \(currentAppName ?? "Unknown")"
                print(msg)
                Logger().info("Figlog_Test: \(msg)")
                
                if isTracking && hasEnteredFocusSession && activeSession != nil {
                    let oldApp = activeSession?.appName
                    if oldApp != nil && oldApp != currentAppName {
                        endActiveSession(at: now)
                        hasEnteredFocusSession = true // Keep tracking state active for new app
                        isTracking = true
                    }
                }
            }
            activeTargetAppName = currentAppName
        } else if !isTracking {
            activeTargetAppName = nil
        }

        if isTargetAppActive && !isIdle && isPaused {
            isPaused = false
        }

        if isPaused {
            return
        }

        if isTargetAppActive && !isIdle {
            if hasEnteredFocusSession && nonTargetAppActivityDuration > 0 {
                todayFocusTime += nonTargetAppActivityDuration
                if activeSession != nil {
                    activeSession?.duration += nonTargetAppActivityDuration
                }
            }
            hasEnteredFocusSession = true
            nonTargetAppActivityDuration = 0
        }

        if hasEnteredFocusSession && !isIdle {

            if !isTargetAppActive {
                nonTargetAppActivityDuration += 1
            } else {
                nonTargetAppActivityDuration = 0
            }

            if nonTargetAppActivityDuration >= nonTargetAppGracePeriod {
                isTracking = false
                hasEnteredFocusSession = false
                
                let backdatedEnd = now.addingTimeInterval(-nonTargetAppGracePeriod)
                endActiveSession(at: backdatedEnd)
            } else {
                isTracking = true
                if isTargetAppActive {
                    todayFocusTime += 1
                    updateActiveSession(at: now)
                }
            }

        } else {
            isTracking = false

            if isIdle {
                nonTargetAppActivityDuration = 0
                hasEnteredFocusSession = false
                endActiveSession(at: now)
            }
        }

        // Emergency Autosave (Every 5 minutes = 300 seconds)
        if now.timeIntervalSince(lastEmergencyAutosaveAt) >= 300 {
            print("⏳ Emergency autosave triggered")
            persistSnapshot()
            lastEmergencyAutosaveAt = now
        }
        
        // Firebase Status Sync (Every 5 minutes or on state change)
        let newState = self.trackingState
        let stateChanged = lastSyncedTrackingState != newState
        let appChanged = lastSyncedAppName != activeTargetAppName
        let timeSinceLastSync = lastFirebaseSyncDate.map { now.timeIntervalSince($0) } ?? 100
        
        if stateChanged || appChanged || timeSinceLastSync >= 300 {
            var statusString = "offline"
            switch newState {
            case .tracking, .activeOutsideTargetApp: statusString = "tracking"
            case .idle: statusString = "idle"
            case .paused: statusString = "paused"
            case .waitingForTargetApp: statusString = "waiting"
            }
            
            FirebaseManager.shared.updateMyStatus(status: statusString, activeAppName: activeTargetAppName, todayFocusTime: todayFocusTime)
            
            lastSyncedTrackingState = newState
            lastSyncedAppName = activeTargetAppName
            lastFirebaseSyncDate = now
        }
    }

    private func updateActiveSession(at date: Date) {
        if activeSession == nil {
            activeSession = FocusSession(
                id: UUID(),
                startedAt: date,
                endedAt: date,
                duration: 0,
                appName: activeTargetAppName
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
        nonTargetAppActivityDuration = 0
        didSendBreakReminderForActiveSession = false
        persistSnapshot()
    }

    private func rollOverDayIfNeeded(_ date: Date) {
        let startOfToday = Calendar.current.startOfDay(for: date)

        guard startOfToday != currentDay else { return }

        endActiveSession(at: date)
        currentDay = startOfToday
        todayFocusTime = 0
        todayIdleTime = 0
        todaySessions = []
        persistSnapshot()
    }

    private func restoreSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: breakReminderKey) != nil {
            breakRemindersEnabled = defaults.bool(forKey: breakReminderKey)
        }
        if defaults.object(forKey: gracePeriodKey) != nil {
            nonTargetAppGracePeriod = defaults.double(forKey: gracePeriodKey)
        }
        if let savedIDs = defaults.stringArray(forKey: "FigLog.FocusTracker.EnabledTargetAppIDs") {
            enabledTargetAppIDs = Set(savedIDs)
        }
        if defaults.object(forKey: breakThresholdKey) != nil {
            breakReminderThreshold = defaults.double(forKey: breakThresholdKey)
        }
        if defaults.object(forKey: idleThresholdKey) != nil {
            idleThreshold = defaults.double(forKey: idleThresholdKey)
        }
    }

    private func restoreSnapshot() {
        guard let record = sessionStore.loadTodayRecord() else {
            currentDay = Calendar.current.startOfDay(for: Date())
            return
        }

        currentDay = record.day
        todayFocusTime = record.totalFocusTime
        todayIdleTime = record.totalIdleTime
        todaySessions = record.sessions
    }

    private func persistSnapshot() {
        sessionStore.saveTodayRecord(
            totalFocusTime: todayFocusTime,
            totalIdleTime: todayIdleTime,
            sessions: todaySessions
        )
        FirebaseManager.shared.uploadDailyHistory(
            date: currentDay,
            totalFocusTime: todayFocusTime,
            totalIdleTime: todayIdleTime,
            sessions: todaySessions
        )
    }

    func getStats(days: Int = 30) -> [DailyFocusRecord] {
        sessionStore.loadRecordsForLast(days: days)
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
        content.title = String(localized: "Time for a short break")
        content.body = String(format: String(localized: "You have focused in Figma for %@."), Self.formatCompactDuration(breakReminderThreshold))
        content.sound = .default
        content.categoryIdentifier = "BREAK_REMINDER_CATEGORY"

        let request = UNNotificationRequest(
            identifier: "figlog.break-reminder.\(session.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in

            if let error {
                print("❌ Notification error: \(error.localizedDescription)")
                return
            }

            print("✅ Break reminder delivered")

            Task { @MainActor in
                self.didSendBreakReminderForActiveSession = true
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "TAKE_BREAK" {
            Task { @MainActor in
                print("☕️ Take Break clicked. Pausing tracking.")
                if !self.isPaused {
                    self.togglePause()
                }
            }
        }
        completionHandler()
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func formatCompactDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        }
        
        let totalMinutes = Int(duration) / 60
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

//
//  FocusSessionStore.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import Foundation

struct DailyFocusRecord: Codable, Sendable {
    let day: Date
    var totalFocusTime: TimeInterval
    var totalIdleTime: TimeInterval = 0
    var sessions: [FocusSession]
}

final class FocusSessionStore: @unchecked Sendable {

    private let storageKey = "FigLog.FocusSessionStore.Records"

    private var baseDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDirectory = paths[0].appendingPathComponent("com.figlog.Desktop", isDirectory: true)
        let recordsDirectory = appSupportDirectory.appendingPathComponent("records", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: recordsDirectory.path) {
            try? FileManager.default.createDirectory(at: recordsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        return recordsDirectory
    }

    init() {
        migrateFromUserDefaultsIfNeeded()
    }

    private func fileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        return baseDirectory.appendingPathComponent("\(dateString).json")
    }

    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey) else { return }
        
        print("📦 Found legacy UserDefaults records. Starting migration...")
        
        do {
            let records = try JSONDecoder().decode([DailyFocusRecord].self, from: data)
            for record in records {
                saveRecord(record)
            }
            defaults.removeObject(forKey: storageKey)
            print("✅ Successfully migrated \(records.count) records to files and cleared legacy UserDefaults data.")
        } catch {
            print("❌ Error parsing legacy records for migration: \(error.localizedDescription)")
        }
    }

    func loadTodayRecord() -> DailyFocusRecord? {
        let today = Calendar.current.startOfDay(for: Date())
        return loadRecord(for: today)
    }

    private func loadRecord(for date: Date) -> DailyFocusRecord? {
        let url = fileURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DailyFocusRecord.self, from: data)
    }

    private func saveRecord(_ record: DailyFocusRecord) {
        let url = fileURL(for: record.day)
        guard let data = try? JSONEncoder().encode(record) else {
            print("❌ Failed to encode focus record")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            print("💾 Saved focus record for \(record.day) to \(url.lastPathComponent)")
        } catch {
            print("❌ Failed to write record to file: \(error.localizedDescription)")
        }
    }

    func saveTodayRecord(
        totalFocusTime: TimeInterval,
        totalIdleTime: TimeInterval,
        sessions: [FocusSession]
    ) {
        let today = Calendar.current.startOfDay(for: Date())
        let record = DailyFocusRecord(
            day: today,
            totalFocusTime: totalFocusTime,
            totalIdleTime: totalIdleTime,
            sessions: sessions
        )
        saveRecord(record)
    }

    func getDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    func loadAllRecords() -> [DailyFocusRecord] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        
        let records = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DailyFocusRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(DailyFocusRecord.self, from: data)
            }
        
        return records.sorted { $0.day < $1.day }
    }

    func loadRecordsForLast(days: Int) -> [DailyFocusRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var records: [DailyFocusRecord] = []
        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                if let record = loadRecord(for: date) {
                    records.append(record)
                }
            }
        }
        return records.sorted { $0.day < $1.day }
    }

    func totalFocusTimeForLast(days: Int) -> TimeInterval {
        loadRecordsForLast(days: days)
            .reduce(0) { partialResult, record in
                partialResult + record.totalFocusTime
            }
    }
}

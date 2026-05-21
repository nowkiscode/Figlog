//
//  FocusSessionStore.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//


//
//  FocusSessionStore.swift
//  Figlog
//
//  Created by 권민재 on 5/21/26.
//

import Foundation

struct DailyFocusRecord: Codable {
    let day: Date
    var totalFocusTime: TimeInterval
    var sessions: [FocusSession]
}

@MainActor
final class FocusSessionStore {

    private let storageKey = "FigLog.FocusSessionStore.Records"

    func loadTodayRecord() -> DailyFocusRecord? {

        let records = loadAllRecords()
        let today = Calendar.current.startOfDay(for: Date())

        return records.first {
            Calendar.current.isDate($0.day, inSameDayAs: today)
        }
    }

    func saveTodayRecord(
        totalFocusTime: TimeInterval,
        sessions: [FocusSession]
    ) {

        let today = Calendar.current.startOfDay(for: Date())

        var records = loadAllRecords()

        let newRecord = DailyFocusRecord(
            day: today,
            totalFocusTime: totalFocusTime,
            sessions: sessions
        )

        records.removeAll {
            Calendar.current.isDate($0.day, inSameDayAs: today)
        }

        records.append(newRecord)

        records.sort {
            $0.day < $1.day
        }

        guard let data = try? JSONEncoder().encode(records) else {
            print("❌ Failed to encode focus records")
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)

        print("💾 Saved focus record for \(today)")
    }

    func loadAllRecords() -> [DailyFocusRecord] {

        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let records = try? JSONDecoder().decode([DailyFocusRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    func loadRecordsForLast(days: Int) -> [DailyFocusRecord] {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let startDate = calendar.date(
            byAdding: .day,
            value: -(days - 1),
            to: today
        ) else {
            return []
        }

        return loadAllRecords().filter {
            $0.day >= startDate
        }
    }

    func totalFocusTimeForLast(days: Int) -> TimeInterval {

        loadRecordsForLast(days: days)
            .reduce(0) { partialResult, record in
                partialResult + record.totalFocusTime
            }
    }
}

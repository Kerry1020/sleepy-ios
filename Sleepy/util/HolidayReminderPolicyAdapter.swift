// HolidayReminderPolicyAdapter.swift — ← util/HolidayReminderPolicyAdapter.kt (GPL-3.0)
// 纯策略(HolidayReminderPolicy)的平台边界: 从 HolidayManager/AppPrefs 取数并喂入。

import Foundation

enum HolidayReminderPolicyAdapter {
    static func decide(date: Date, tableId: Int64) async -> HolidayReminderPolicy.Result {
        let year = date.year
        let yearEntries = await HolidayManager.getYearEntries(year)
        let holidays = Set(yearEntries.filter { $0.type == HolidayManager.TYPE_PUBLIC_HOLIDAY }.map(\.date))
        let workdays = Set(yearEntries.filter { $0.type == HolidayManager.TYPE_TRANSFER_WORKDAY }.map(\.date))
        let transfers = AppPrefs.shared.getHolidayTransfers(tableId)
        return HolidayReminderPolicy.decide(
            date: date,
            publicHolidays: holidays,
            transferWorkdays: workdays,
            transfers: transfers,
            rulesEnabled: AppPrefs.shared.isHolidayReminderRulesEnabled(),
            publicHolidayReminder: AppPrefs.shared.isHolidayReminderPublicHolidayEnabled(),
            transferHolidayReminder: AppPrefs.shared.isHolidayReminderTransferHolidayEnabled(),
            makeupWorkdayReminder: AppPrefs.shared.isHolidayReminderMakeupWorkdayEnabled(),
            ordinaryWeekendReminder: AppPrefs.shared.isHolidayReminderOrdinaryWeekendEnabled(),
            dataAvailable: !HolidayManager.isYearFetchFailed(year)
        )
    }
}

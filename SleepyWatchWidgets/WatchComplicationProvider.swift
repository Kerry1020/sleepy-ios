// WatchComplicationProvider.swift — 表盘复杂功能 Timeline (2026-10 watch 伴侣 App)
// ← plan 阶段四: Timeline 在课程边界刷新; 数据源 = 手表本地 GRDB。
// applySnapshot 后主 app 调 WidgetCenter.shared.reloadAllTimelines() 触发重算
// (本 PR 在 WatchStore.applySnapshot 末尾补 reload)。
//
// 策略 (省电 + 与课程边界对齐, 不每分钟刷):
//   entry[0] = now, 显示当前「下一节」
//   entry[1] = 下一节开课时刻 (date=startDate), 届时系统切到此 entry 并重算
//            (此时原下一节已开, getTimeline 重跑会指向再下一节)
//   无下一节 → entry[1] = 次日 00:05 兜底 (跨日可能有课)
// policy=.atEnd: 最后一条到期后系统再调 getTimeline 续期。

import WidgetKit
import SwiftUI

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let next: WatchNextClass?
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        WatchComplicationEntry(date: Date(), next: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        let (_, next) = WatchComplicationData.load()
        completion(WatchComplicationEntry(date: Date(), next: next))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let now = Date()
        let (_, next) = WatchComplicationData.load(now: now)
        let first = WatchComplicationEntry(date: now, next: next)

        let second: WatchComplicationEntry
        if let n = next {
            // 开课时刻重算: 加 1 分钟避免与「正在开课」同刻竞态, 落到开课后即重算
            second = WatchComplicationEntry(
                date: n.startDate.addingTimeInterval(60), next: nil)
        } else {
            let cal = Calendar(identifier: .gregorian)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
            let at = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
            second = WatchComplicationEntry(date: at, next: nil)
        }
        // second.next=nil 是占位: 到点系统重调 getTimeline, 那时 load 出真实下一节。
        // 这里不预填, 因为预填需要再 load 一次且仍会在边界处过期 — 交给 .atEnd 续期更准。

        completion(Timeline(entries: [first, second], policy: .atEnd))
    }
}

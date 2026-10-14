// ReminderRescheduler.swift — ← widget/notification/ReminderRescheduler.kt
// 提醒重排枢纽 (参照 shiguang SyncManager 防抖模式)。
//
// 问题: 编辑课表连续保存 / 提醒设置连点开关时, 旧链路每次都直接
// scheduleAll() (cancelAll + 重排 7 天闹钟), 高频全量重排既浪费又在
// cancel/重排间隙留下"无闹钟"窗口。
//
// 契约: request() 幂等触发; 静默 debounceMs 后才执行一次 action() —
// 窗口内任意次 request 合并为一次。实现为「取消旧延迟任务 + 重排」。
//
// action 由 init 注入 (生产 = NotificationScheduler.shared.scheduleAll);
// 冷启动路径继续直调 scheduleAll(), 不经过本枢纽。

import Foundation

final class ReminderRescheduler {
    static let shared = ReminderRescheduler()

    private let queue = DispatchQueue(label: "sleepy.reminder.rescheduler", qos: .utility)
    private var pending: DispatchWorkItem?
    private var action: (() async -> Void)?
    private var debounceMs: Int = 300

    /// 注册重排动作与防抖窗口; 重复调用覆盖。
    /// 替换 action 时取消 in-flight pending, 防止旧 action 在新 action 已替换后仍执行一次。
    /// 生产路径只调一次 (SleepyApp 启动), 此 guard 主要是测试场景的兜底。
    func init_(debounceMs: Int = 300, action: @escaping () async -> Void) {
        queue.sync {
            self.debounceMs = debounceMs
            self.action = action
            self.pending?.cancel()
            self.pending = nil
        }
    }

    /// 请求一次重排; 静默窗口内的后续请求并入同一批。init 前调用静默丢弃。
    func request() {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let a = self.action else { return }
            Task { await a() }
        }
        queue.sync {
            guard self.action != nil else { return }
            self.pending?.cancel()
            self.pending = work
            queue.asyncAfter(deadline: .now() + .milliseconds(self.debounceMs), execute: work)
        }
    }

    /// 测试钩子 — 取消在途任务并复位。
    func resetForTest() {
        queue.sync {
            self.pending?.cancel()
            self.pending = nil
            self.action = nil
        }
    }
}

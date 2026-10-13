# Sleepy iOS — v1.0.61 Replication Recon

## Status as of 2026-10-13 (master @ 86e0799, align content merged)

### features.csv (172 rows, 同源 basename 全量扫描改判后)

- **94 ported / 77 missing**（同名 Swift 已存在的 9 行: OfflineSchoolCityIndex / SchoolCityIndex / SchoolCityLocator / SchoolLocationPolicy / MigrationBackup / MigrationDatabaseCodec / MigrationExecutor / MigrationPackageCodec / MigrationPrefsCodec 改判 ported，auto-sweep 注）
- 77 missing = 真实缺口，按层归入 8 切片（plan.md 2-9）

### Branch: `rebuild/align-sleepy-1.0.60` in `~/Desktop/sleepy-ios-wt/align-1.0.60` → 已合入 master

### Commits delivered (9 since baseline 63ed008 / v1.0.55)

| hash | summary |
|------|---------|
| 1aefef9 | feat(strings): 补齐 v1.0.60 新增 305 个字符串键 ×5 语言 |
| 29f1c2b | feat(schools): schools.json 对齐 v1.0.60 — 185 → 348 所 (+163) |
| 998bbc4 | feat(data): 对齐 v1.0.60 数据层 — DB v6→v10 + 三张新表 + issue#40 节次表绑定状态机 |
| f0de650 | feat(util): 对齐 v1.0.60 util 层 — 10 个策略/解析文件 + 假期提醒门控 + 周显示解析 |
| 2dfc8e5 | feat(jw): 移植 v1.0.60 12 个教务协议解析器 |
| 95d328a | feat(jw): 移植 v1.0.60 9 个 fetch JS (NEU/NUIT/KUST/YETHAN/CHAOXING/WHUT/EAMS5/EAMS5_AHU/BJTU) + CfNew 协议 |
| 02c9b21 | feat(diag): 移植 v1.0.60 排查诊断层 — frame capture + JS 诊断集 + 会话记录 |
| 4c8bdb0 | feat(diag): 移植 v1.0.60 排查全量包 — JwCaptureDump zip dump + ZIPFoundation |

### Test gate

- xcodebuild build: **SUCCEEDED** (sleepy 1.0.60 baseline)
- SleepyTests: **532/0 (12.452s)** on iPhone 14 Pro simulator (iOS 16.4)

## File-level gap (Android v1.0.60 main sources → iOS current)

- **171** Android main-source files in v1.0.60 delta (v1.0.55..v1.0.60)
- **85** ported (basename match) — 49.7%
- **86** missing — 50.3%

Full breakdown: `replica/features.csv`

## Missing area distribution (top 15 by count)

| area | missing |
|------|---------|
| widget | 24 |
| notification | 13 |
| mine | 11 |
| jw | 7 |
| imports | 6 |
| component | 6 |
| migration | 5 |
| util | 4 |
| nav | 4 |
| theme | 1 |
| sleepy | 1 |
| schedule | 1 |
| repository | 1 |
| data | 1 |
| calendar | 1 |

## What's covered

- **strings**: full v1.0.60 key set × 5 languages (zh-Hans / zh-Hant / en / es / ja)
- **schools**: 348 supported schools, json sync with v1.0.60
- **data layer**: AppDatabase migrated v6→v10 with new tables (ImportDraft, CalendarImportRecord, PeriodTable, TimeTable)
- **util layer**: 10 strategy/parse files + holiday reminder gating + week display parse
- **jw parsers**: 12 protocol parsers (CF_NEW, CHAOXING, CLASSIC_EAMS, EAMS5, KUST, NEU, NEW_ZF, NUIT, WUKEEP_COMPAT, YETHAN + others)
- **jw fetch JS**: 9 fetch enums + CfNew deep-frame variant + 2 dispatch entries
- **diagnostic**: JwWebViewFrameCapture + JwDiagnosticJs + JwDiagnosticSession
- **capture dump**: JwCaptureDump with ZIPFoundation, 1:1 against Android
- **dep added**: ZIPFoundation 0.9.20 (gh.qdp mirror)

## What's NOT covered (priority-ordered backlog)

### 1. migration/ — 5 files
- MigrationBackup.kt
- MigrationDatabaseCodec.kt
- MigrationExecutor.kt
- MigrationPackageCodec.kt
- MigrationPrefsCodec.kt
**Why high value:** foundational for upgrade-in-place from v1.0.55 to v1.0.60 — without it, users can't carry their courses over.

### 2. jw/ — 7 files (parsers + import-draft)
- JwImportDraft.kt
- JwImportViewModel.kt
- JwParserRegistry.kt
- JwProtocol.kt (constant updates)
- OfflineSchoolCityIndex.kt
- SchoolCityIndex.kt
- SchoolCityLocator.kt
- SchoolLocationLookup.kt
- SchoolLocationPolicy.kt
- school_cities.json (asset)
**Why high value:** JwParserRegistry orchestrates all 12 parsers; SchoolCityIndex drives "nearby schools" feature.

### 3. data/calendar/ — 4 files
- CalendarImportRecordEntity.kt
- CalendarImportRecordDao.kt
- SystemCalendarManager.kt
- CalendarImportDialog.kt
**Why high value:** EventKit integration — students push courses into iOS Calendar.

### 4. data/notification/ — ~6 files
- ClassDndScheduler.kt
- CourseNotificationScheduler.kt
- ReminderRescheduler.kt
- BackgroundReliabilityProbe.kt
- BackgroundReliabilitySnapshot.kt
- BatteryOptimizationIntents.kt
**Why high value:** "上课自动勿扰" + "课程提醒" — feature-promised to students.

### 5. widget/ — 24 files (most under widget/ subpkg)
- Today widgets, schedule cells, compact windows, refresh logic
**Why high value:** widget is the entry point. iOS widget exists but lacks the v1.0.60 polish.

### 6. ui/screen/imports/ — 6 files
- CalendarImportDialog
- DiagDumpProgress
- ExitDraftState
- ImportDraftSheet
- ImportSheet
- (others)
**Why high value:** import flow UI is the primary user journey.

### 7. ui/screen/mine/ — 11 files
- Settings UI
**Why medium value:** settings screens, fewer consumers.

### 8. ui/component/ — 6 files
- CourseDetailSheet, PeriodTableShareSheet, ShareScheduleSheet, etc.
**Why medium value:** shared UI components.

### 9. ui/nav/ — 4 files
- SleepyMaterialTransition, SleepyNavHost, SleepyNavigator, SleepyRoutes
**Why medium value:** navigation graph.

## Constraints observed

- **No push** (release-sop §6 user-approval gate)
- **No Co-Authored-By: Claude** in commit trailers
- **No Fixes:/Closes:/Resolves: #N** in commit messages
- **No brew** anywhere
- **Always gh.qdp.qzz.io** for non-cached remote
- **Author = lingion@hrbeu.edu.cn** on every commit
- **iOS私有不入库,本地保留** — no specs pushed

## Next step

Resume with the highest-value remaining slice. The user's standing goal (`/goal 安装完之后用这个skill 把sleepy 1.0.60 严格复制到sleepy-iOS 已有仓库`) requires 1:1 port of v1.0.60. The pragmatic next slice is **migration/** (5 files, ~640 lines) because it gives users a real upgrade path; the iOS side is currently at v1.0.55 schema.

---

## v1.0.60 → v1.0.61 Delta（对齐目标升级, 2026-10-13）

用户指令：**100% 全部对齐 v1.0.61, 不多不少**。范围锁定 tag v1.0.61（源仓 HEAD 的 #158/#159 不进口）。

### v1.0.60..v1.0.61 全量 diff（47 文件, +3023/-270）

| 类别 | 文件 | 内容 | iOS 归属切片 |
|---|---|---|---|
| db | Migrations.kt, AppDatabase.kt, TimeTableEntity.kt, schemas 10/11.json | **DB v10→v11**: `time_tables.reminderEnabled INTEGER NOT NULL DEFAULT 1`（#143 每表独立提醒开关, 前后台课表单独控制） | slice-data-migrations |
| util | HolidayRange.kt | **`HolidayRangeOps.applyDaySwap`**（#145/#148: sourceDow 课挪到 targetDow + 屏蔽 targetDow 上 day∉sourceDays 的原课; 几何契约: 与 effectiveDayOfWeek 同形但不互相依赖） | slice-util |
| util | HolidayManager.kt | 自定义补班日（网络 补班日 + 用户 调休 targetDates）也豁免灰显（#139/b92efaf6） | slice-util |
| util | ConflictLayoutEngine.kt | 簇内原点偏移参数顺序修正（#146/#147: 1-2+2-4 重叠整体下移两节）; #142 非常规时间课并排分道 | slice-util |
| util | TimeTableUtils.kt | 小修 | slice-util |
| jw | **JwThuparser.kt (NEW, 351 行)** | 西南交大逐专平台导入修复 + 官方作息兜底（#134）; fixture `thu/zhkbcx-courses.sample.html` | slice-jw |
| jw | JwYethanParser.kt, JwParserRegistry.kt, JwProtocol.kt | HBSM 湖北商贸登记（#156: schools.json 348→349, #157: sortKeyFull 拼音 shangmau→shangmao + campusOverride） | slice-jw |
| jw | school_cities.json, schools.json | HBSM 城市映射 | slice-jw |
| ui | LicenseScreen.kt (+26), AboutLicenseAttributionTest | 致谢页贡献者列表更新（#138） | slice-screens |
| ui | ReminderScreen.kt (~267 diff) | #143 每表独立开关 UI + 流体云测试投放权限闸门（#151） | slice-reminder-live |
| ui | TimeSlotEditor.kt (~399), AddCourseScreen, ConflictCard, ExportScreen（无课表有作息表导出页误判空态 #152） | 编辑/导出 UI 修正 | slice-screens |
| ui | JwWebViewLoginScreen.kt | thu 逐专登录流程 | slice-jw |
| ui | EditTableScreen.kt | #144 编辑页跳转: header 偏移 + day 进分组 + 空 groupId 匹配; b77fc4d6 改用 CourseEntity.id; 2188a9e4 默认跳到点击时段卡 | slice-screens |
| notify | CourseNotificationScheduler.kt (~233 diff) | #143 按表 reminderEnabled 门控通知调度 | slice-reminder-live |
| notify | FluidCloudService.kt, VendorLiveNotificationAdapters.kt | 流体云测试按钮分裂态 + 停止入口（#116）; OPPO 官方设置入口 + 投放状态对账（#151） | slice-reminder-live |
| strings | 5 语言各 ~+35 键 | 本地化补 | 各切片引用时补 |

### 平台映射表（iOS 无厂商差异 → 统一原生 API）

| Android 机制 | iOS 等价 | 说明 |
|---|---|---|
| Widget（TodayWidget/TwoDay/WeekGrid/WeekList/CompactWindow） | WidgetKit extension target | WidgetWeekDataLoader 直读 DB → App Group container 同步; WidgetBitmapRenderers → UIGraphicsImageRenderer |
| 流体云 / Vendor LiveCard（CourseLiveCardState/FluidCloudService/VendorLiveCardRenderer/Support/VendorLiveNotificationAdapter(s)/Capability） | **ActivityKit Live Activities** 统一一套 | iOS 无厂商分叉; 一套 ActivityKit 覆盖 OPPO/流体云场景; 测试投放权限闸门 → 设置深链 |
| SystemCalendarManager / CalendarImportDialog | **EventKit** | 课表推入 iOS 日历 |
| BackgroundReliabilityProbe/Snapshot | BGTaskScheduler 热态探测 | BGAppRefreshTask 采样后台存活 |
| BatteryOptimizationIntents | 设置深链（ios-settings 无对应 API） | App Intents 暴露入口 |
| widget 编辑区（WidgetEdit*） | WidgetConfigurationIntent + App Intents | 配置 intent 替代 AppWidget 编辑 Activity |
| ClassDndScheduler / ReminderRescheduler | UNUserNotificationCenter + UNCalendarTrigger | 每表 reminderEnabled 门控调度 |
| WeekGridPreviewActivity / WidgetRenderActivity | Widget 生命周期等价（TimelineProvider） | 无 Activity 概念 |

### 工作纪律

- 本地 commit 免批准; **push/tag/gh release = 用户明确批准闸门**（release-sop §6）
- 每个 commit 作者 `lingion <lingion@hrbeu.edu.cn>`, 零 Co-Authored-By, 禁 `Fixes:/Closes:/Resolves:` 关帖词
- 构建门: xcodebuild 必须 `env -u GIT_CONFIG_*`（copilot git 2.53.0 的 safe.bareRepository=explicit 污染 SPM bare-repo fetch）
- xcodegen `/Users/lingion_k/bin/xcodegen generate`; 🚫手编 pbxproj

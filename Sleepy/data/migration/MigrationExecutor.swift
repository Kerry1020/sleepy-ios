// MigrationExecutor.swift — ← data/migration/MigrationExecutor.kt
// 全量迁移编排层: 把协议层 (ZIP) 与各模块 codec (prefs/database) 接起来。
//
// 约束 (设计文档 §导出/导入流程):
// - 导出选中 DATABASE 自动带上 PERSISTED_STATE 依赖闭包;
// - 导入先完整读包校验, 坏包在写任何本机数据前被拒绝;
// - 包内缺失的文件/模块不动本机 (设备自有设置优先于默认);
// - CREDENTIALS 枚举保留但当前两端均无内容, 暂不进包。

import Foundation
import GRDB

/// UserDefaults 文件访问抽象 — 便于纯单元测试注入。
/// 协议与 Android MigrationPrefsStore 1:1(open(fileName: String) → UserDefaults)。
protocol MigrationPrefsStoreProtocol {
    func open(fileName: String) -> UserDefaults
}

/// 全量迁移编排 — 与 Android MigrationExecutor.kt 1:1。
enum MigrationExecutor {

    enum ImportMode: String {
        case OVERWRITE
        case MERGE
    }

    struct ExportResult {
        let bytes: Data
        let modules: [MigrationModule]
        let manifest: MigrationBackup.Manifest
    }

    struct ImportCounts {
        var periodTables: Int = 0
        var timeTables: Int = 0
        var courses: Int = 0
        var importDrafts: Int = 0
        var prefFiles: Int = 0
        var prefKeys: Int = 0
    }

    struct ImportReport {
        let mode: ImportMode
        let appliedModules: [MigrationModule]
        let unknownModules: [String]
        let counts: ImportCounts
    }

    // MARK: - 导出

    /// 导出选中的模块为 .sleepybackup 字节。
    /// CREDENTIALS 当前无内容, 不进包(与 Android 一致)。
    /// iOS 同步 throws(GRDB DAO throws 而非 suspend)。
    static func export(
        selected: Set<MigrationModule>,
        prefsStore: MigrationPrefsStore,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> ExportResult {
        let resolved = MigrationModuleDeps.resolve(selected)
            .filter { $0 != .CREDENTIALS }
            .sorted()

        var payloads: [MigrationModule: String] = [:]
        for module in resolved {
            switch module {
            case .DATABASE:
                let snapshot = try MigrationDatabaseCodec.collect(
                    courseDao: courseDao, timeTableDao: timeTableDao,
                    periodTableDao: periodTableDao, importDraftDao: importDraftDao
                )
                payloads[module] = try MigrationDatabaseCodec.encode(snapshot)
            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE:
                payloads[module] = try MigrationPrefsCodec.encode(collectPrefs(prefsStore, module: module))
            case .CREDENTIALS:
                continue
            }
        }
        let manifest = MigrationBackup.Manifest(
            createdAt: createdAt,
            modules: payloads.keys.map { $0.entryName }
        )
        let bytes = try MigrationPackageCodec.write(payloads, createdAt: createdAt)
        return ExportResult(
            bytes: bytes,
            modules: Array(payloads.keys).sorted(),
            manifest: manifest
        )
        // dbQueue 参数保留以对齐 Android 出口签名;iOS 端 collect() 全 read,
        // 不需 dbQueue.write — 参数忽略即可。
    }

    private static func collectPrefs(_ store: MigrationPrefsStoreProtocol, module: MigrationModule) -> MigrationPrefsCodec.PrefsSnapshot {
        var files: [String: MigrationPrefsCodec.PrefsFileSnapshot] = [:]
        for fileName in MigrationPrefsFileMap.files(of: module) {
            // 空 prefs 文件不进包: 无信息量, 且让接收端保留自有设置 (设备设置优先于默认)
            let defaults = store.open(fileName)
            let snapshot = MigrationPrefsCodec.collect(defaults)
            if !snapshot.entries.isEmpty {
                files[fileName] = snapshot
            }
        }
        return MigrationPrefsCodec.PrefsSnapshot(files: files)
    }

    // MARK: - 导入

    /// 导入 .sleepybackup 字节。
    /// 先完整校验并解码, 任何坏包在触碰本机数据之前失败。
    static func `import`(
        bytes: Data,
        mode: ImportMode,
        prefsStore: MigrationPrefsStore,
        courseDao: CourseDao,
        timeTableDao: TimeTableDao,
        periodTableDao: PeriodTableDao,
        importDraftDao: ImportDraftDao,
        dbQueue: DatabaseQueue
    ) throws -> ImportReport {
        // 先完整校验并解码, 任何坏包都在触碰本机数据之前失败
        let content = try MigrationPackageCodec.read(bytes)
        var counts = ImportCounts()
        var applied: [MigrationModule] = []

        let sorted = content.modules.keys.sorted()
        for module in sorted {
            guard let payload = content.modules[module] else { continue }
            switch module {
            case .DATABASE:
                let snapshot = try MigrationDatabaseCodec.decode(payload)
                switch mode {
                case .OVERWRITE:
                    try MigrationDatabaseCodec.applyOverwrite(
                        snapshot, courseDao: courseDao, timeTableDao: timeTableDao,
                        periodTableDao: periodTableDao, importDraftDao: importDraftDao,
                        dbQueue: dbQueue
                    )
                case .MERGE:
                    try MigrationDatabaseCodec.applyMerge(
                        snapshot, courseDao: courseDao, timeTableDao: timeTableDao,
                        periodTableDao: periodTableDao, importDraftDao: importDraftDao,
                        dbQueue: dbQueue
                    )
                }
                counts = ImportCounts(
                    periodTables: snapshot.periodTables.count,
                    timeTables: snapshot.timeTables.count,
                    courses: snapshot.courses.count,
                    importDrafts: snapshot.importDrafts.count,
                    prefFiles: counts.prefFiles,
                    prefKeys: counts.prefKeys
                )
                applied.append(module)

            case .PREFERENCES, .WIDGETS, .PERSISTED_STATE:
                let snapshot = try MigrationPrefsCodec.decode(payload)
                // 包内缺失的 prefs 文件不动本机; 包内文件按 mode 决定整文件替换或同名覆盖
                for (fileName, fileSnapshot) in snapshot.files {
                    let defaults = prefsStore.open(fileName)
                    try MigrationPrefsCodec.apply(defaults, fileSnapshot,
                                                  merge: mode == .MERGE)
                }
                let newPrefFiles = counts.prefFiles + snapshot.files.count
                let newPrefKeys = counts.prefKeys + snapshot.files.values.reduce(0) { $0 + $1.entries.count }
                counts = ImportCounts(
                    periodTables: counts.periodTables,
                    timeTables: counts.timeTables,
                    courses: counts.courses,
                    importDrafts: counts.importDrafts,
                    prefFiles: newPrefFiles,
                    prefKeys: newPrefKeys
                )
                applied.append(module)

            case .CREDENTIALS:
                continue   // 未知历史内容, 忽略
            }
        }
        return ImportReport(
            mode: mode,
            appliedModules: applied.sorted(),
            unknownModules: content.unknownModules,
            counts: counts
        )
    }
}

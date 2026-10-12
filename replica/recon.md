# Sleepy Android v1.0.60 → sleepy-iOS · 城市定位切片 recon

## 分工与协调
- 源:`lingion/sleepy` Android **v1.0.60**(唯一真源,本地 `/Users/lingion_k/sleepy` 只读)
- 目标:sleepy-iOS,工作分支 **rebuild/city-locator**(rebase 在另一 agent align-1.0.60 的 f0de650 数据层基线之上)
- 零重叠:对方自底向上对齐 util/data 基线;本切片只新增城市定位功能文件,不改其文件
- subagent 并行:Phase B/C 原计划委派后台 agent,因运行时 400 模型错误失败(0 turns),改为主会话直跑,结论不受影响

## 核心回路
选校页点定位图标 → 运行时权限 → CoreLocation 单次前台 fix(12s 超时)→ 质量策略(usable/forCityLookup)→ SCB1 离线城市边界 ray-casting → 同城学校推荐卡

## 文件映射(Android → iOS)
| Android | iOS |
|---|---|
| `data/jw/SchoolLocationPolicy.kt` | `Sleepy/data/jw/SchoolLocationPolicy.swift` |
| `data/jw/SchoolCityIndex.kt` | `Sleepy/data/jw/SchoolCityIndex.swift` |
| `data/jw/OfflineSchoolCityIndex.kt` | `Sleepy/data/jw/OfflineSchoolCityIndex.swift` |
| `SchoolLocationLookup.kt` + `SchoolCityLocator.kt` | `Sleepy/data/jw/SchoolCityLocator.swift`(State/Lookup 纯逻辑 + CLLocationManager 桥合并) |
| 选校屏接线/同城推荐卡 | `Sleepy/ui/screen/imports/SchoolSelectScreen.swift` |
| `JwImportViewModel.kt` schoolLocation 状态机 | `Sleepy/data/jw/JwImportViewModel.swift`(@Published + Task) |
| assets `school_city_boundaries.bin.gz` + `school_cities.json` | `Sleepy/resources/SchoolCity/`(iOS AAPT 不解 gz → 自行 gunzip) |

## 关键实现事实
- `SchoolLocationState` 8 态 sealed class → Swift enum,语义逐一对照
- SCB1:1e4 缩放整数环 + 8 向不确定性采样 ray-casting,含洞环
- `JwSchoolInfo` 成员初始化顺序(严格):sortKey→name→url→type→status→aliases→sortKeyFull→enableFetch→cities
- harness 首轮抓出 2 类移植 bug 并修复:`0..<try count()` 语法违规(3 处 hoist)、`compression_stream` C 结构体无部分参 init(inflate 重写为成员逐一初始化)

## 平台偏差(2 条,刻意保留)
1. **无系统定位总开关页**:Android `ACTION_LOCATION_SOURCE_SETTINGS` 在 iOS 无公开 API 等价 → locationDisabled 分支与权限跳转都开 app 设置页(`openSettingsURLString`),配合 `resumeLocationAfterSettings` 回来续定位
2. **设置跳转同页**:Android「权限设置」开应用详情页、「定位服务」开系统页两处;iOS 合并为同一 app 设置页

## 验证(三相 harness,全部通过)
- **Phase A**(macOS 本地跑通,真资产):5 测试组 41/41 断言 —— 真资产三城点测/越界 nil、Policy 全分支、索引解析归一、schoolsInCity 去重排序、findCity 六场景(缓存命中/仅 passive/索引 nil/北京 requestFix/30km 精度拒绝/南海城外兜底)
- **Phase B**(iphonesimulator16.4 SDK,arm64-apple-ios15.6-simulator):5 个 jw 文件 `swiftc -typecheck` exit 0(仅 4 个已知 NSLock-async Swift 6 迁移 warning,Swift 5.8 合法,文件头有注释)
- **Phase C**:SchoolSelectScreen + JwImportViewModel `swiftc -parse` exit 0

## 明确不做
- 持续/后台定位(Android 原版即单次前台查找)
- 城市边界可视化/编辑(源不存在,不发明功能)

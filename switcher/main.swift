// DarkIconSwitcher：跟随系统外观，自动给没做深色图标的应用换上 / 恢复图标。
//
// 配置文件 config.json（与程序所在的 .app 放在同一目录）：
// {
//   "restartDock": true,
//   "apps": [
//     { "app": "/Applications/WeChat.app", "dark": "icons/wechat-dark.png" }
//   ]
// }
// dark 可以写绝对路径，也可以写相对配置文件目录的路径。
//
// 判断规则：
// - 图标样式（系统设置 → 外观 → 图标与小组件样式）为“深色”：换深色图标；
// - 为“自动”：跟随系统深浅色；
// - 为“浅色”“透明”“着色”：恢复原图标，交给系统处理。

import AppKit

struct AppEntry: Decodable { let app: String; let dark: String }
struct Config: Decodable { let restartDock: Bool?; let apps: [AppEntry] }

let baseDir = Bundle.main.bundleURL.deletingLastPathComponent()
let configURL = baseDir.appendingPathComponent("config.json")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/DarkIconSwitcher.log")

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

func globalPref(_ key: String) -> String? {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    return CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? String
}

/// 当前是否应该使用自定义深色图标
func wantDark() -> Bool {
    let theme = globalPref("AppleIconAppearanceTheme") ?? "RegularAutomatic"
    let interfaceDark = globalPref("AppleInterfaceStyle") == "Dark"
    if theme.hasPrefix("Regular") {
        if theme.hasSuffix("Dark") { return true }
        if theme.hasSuffix("Light") { return false }
        return interfaceDark                     // RegularAutomatic
    }
    return false                                 // 透明、着色：用原图标
}

/// 自定义图标由两部分组成：应用包根目录里名为 "Icon\r" 的图标文件，
/// 以及应用包 FinderInfo 里的“有自定义图标”标记。
/// 应用更新会整体替换应用包，两者都会消失，借此发现图标被重置。
/// 没有“App 管理”权限时，系统可能只删掉文件、留下标记，应用会显示成文件夹，所以两者要分开判断。
func iconFileExists(_ app: String) -> Bool {
    FileManager.default.fileExists(atPath: app + "/Icon\r")
}

func customIconFlag(_ app: String) -> Bool {
    var info = [UInt8](repeating: 0, count: 32)
    let n = getxattr(app, "com.apple.FinderInfo", &info, 32, 0, 0)
    return n >= 9 && info[8] & 0x04 != 0
}

func loadConfig() -> Config? {
    do { return try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL)) }
    catch { log("读取配置失败：\(error)"); return nil }
}

var lastDark: Bool?
var retryAt: Date?          // 有应用没换成功（多半是还没授权“App 管理”）时，到点再试

func sync(reason: String) {
    guard let config = loadConfig() else { return }
    let dark = wantDark()
    var changed = false
    var failed = false
    for entry in config.apps {
        guard FileManager.default.fileExists(atPath: entry.app) else { continue }
        let file = iconFileExists(entry.app), flag = customIconFlag(entry.app)
        if dark && !(file && flag) {
            let path = entry.dark.hasPrefix("/") ? entry.dark : baseDir.appendingPathComponent(entry.dark).path
            guard let image = NSImage(contentsOfFile: path) else { log("找不到深色图标：\(path)"); continue }
            let ok = NSWorkspace.shared.setIcon(image, forFile: entry.app, options: [])
            log("\(reason)：\(entry.app) 换成深色图标 \(ok ? "成功" : "失败（检查“App 管理”权限）")")
            changed = true; failed = failed || !ok
        } else if !dark && (file || flag) {
            let ok = NSWorkspace.shared.setIcon(nil, forFile: entry.app, options: [])
            log("\(reason)：\(entry.app) 恢复原图标 \(ok ? "成功" : "失败（检查“App 管理”权限）")")
            changed = true; failed = failed || !ok
        }
    }
    if changed && (config.restartDock ?? true) {
        // Dock 会缓存图标，重启 Dock 才能立刻看到变化（失败时也可能已改了一半，同样刷新）；
        // 等 1 秒让系统图标缓存先更新。Dock 重启时会沿用自己的图标缓存文件，不删掉它会显示上一次的图标。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let cacheDir = FileManager.default.temporaryDirectory.deletingLastPathComponent().appendingPathComponent("C")
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("com.apple.dock.iconcache"))
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["Dock"]
            try? p.run()
        }
    }
    lastDark = dark
    retryAt = failed ? Date().addingTimeInterval(30) : nil
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

// 外观变化：系统通知 + 每秒轮询一次设置（图标样式的变化没有公开通知）。
// 设置稳定 1.5 秒后才动手，连续快速切换时只处理最后一次，避免和 Dock 重启撞车。
var pending: DispatchWorkItem?
func scheduleSync(reason: String) {
    pending?.cancel()
    let work = DispatchWorkItem { sync(reason: reason) }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
}
var seenDark = wantDark()
DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
) { _ in seenDark = wantDark(); scheduleSync(reason: "外观变化") }
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    let now = wantDark()
    if now != seenDark { seenDark = now; scheduleSync(reason: "外观变化") }
    else if let t = retryAt, Date() >= t { retryAt = nil; sync(reason: "重试") }
}
// 应用更新后图标会被重置：应用启动时、以及每 10 分钟检查一次
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { _ in scheduleSync(reason: "应用启动") }
Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in sync(reason: "定期检查") }

log("启动，配置：\(configURL.path)")
sync(reason: "启动")
app.run()

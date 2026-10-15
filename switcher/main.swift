// DarkIconSwitcher：跟随系统外观，自动给没做深色图标的应用换上 / 恢复图标。由 launchd 按需唤起，处理完即退出。
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

/// 按当前外观把配置里的应用换成深色图标或恢复原图标；返回是否动过图标
@discardableResult
func sync(dark: Bool, config: Config) -> Bool {
    var changed = false
    for entry in config.apps {
        guard FileManager.default.fileExists(atPath: entry.app) else { continue }
        let file = iconFileExists(entry.app), flag = customIconFlag(entry.app)
        if dark && !(file && flag) {
            let path = entry.dark.hasPrefix("/") ? entry.dark : baseDir.appendingPathComponent(entry.dark).path
            autoreleasepool {
                guard let image = NSImage(contentsOfFile: path) else { log("找不到深色图标：\(path)"); return }
                let ok = NSWorkspace.shared.setIcon(image, forFile: entry.app, options: [])
                log("\(entry.app) 换成深色图标 \(ok ? "成功" : "失败（检查“App 管理”权限）")")
                changed = true
            }
        } else if !dark && (file || flag) {
            let ok = NSWorkspace.shared.setIcon(nil, forFile: entry.app, options: [])
            log("\(entry.app) 恢复原图标 \(ok ? "成功" : "失败（检查“App 管理”权限）")")
            changed = true
        }
    }
    return changed
}

/// Dock 会缓存图标，重启 Dock 才能立刻看到变化（失败时也可能已改了一半，同样刷新）。
/// 先等 1 秒让系统图标缓存更新；Dock 重启时会沿用自己的图标缓存文件，不删掉它会显示上一次的图标。
func refreshDock() {
    Thread.sleep(forTimeInterval: 1)
    let cacheDir = FileManager.default.temporaryDirectory.deletingLastPathComponent().appendingPathComponent("C")
    try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("com.apple.dock.iconcache"))
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); p.arguments = ["Dock"]
    try? p.run(); p.waitUntilExit()
}

// 程序不常驻：由 launchd 在系统设置变化、配置里的应用被改动（比如更新）、登录时和每 10 分钟唤起，
// 处理完就退出，平时不占内存。
// 唤起后先等设置稳定 1.5 秒再动手；处理期间设置又变了（连续快速切换）就再处理一轮，直到稳定。
guard let config = loadConfig() else { exit(1) }
var handled: Bool?
var changed = false
while true {
    let dark = wantDark()
    if dark == handled { break }
    Thread.sleep(forTimeInterval: 1.5)
    if wantDark() != dark { continue }          // 还在变，等它稳定
    changed = sync(dark: dark, config: config) || changed
    handled = dark
}
if changed && (config.restartDock ?? true) { refreshDock() }

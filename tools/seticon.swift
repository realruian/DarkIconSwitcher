import AppKit
// 用法：seticon <应用路径> <图标 PNG>   设置自定义图标
//      seticon <应用路径> --reset       恢复原图标
let app = CommandLine.arguments[1], arg = CommandLine.arguments[2]
let image = arg == "--reset" ? nil : NSImage(contentsOfFile: arg)
let ok = NSWorkspace.shared.setIcon(image, forFile: app, options: [])
print(ok ? "成功" : "失败")
exit(ok ? 0 : 1)

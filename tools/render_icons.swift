import AppKit
// 用法：render_icons <输出目录> <尺寸> <应用路径>...
// 按系统当前外观和图标样式，渲染每个应用在 Dock / 访达里实际显示的图标
let args = CommandLine.arguments
let outDir = args[1], size = Int(args[2])!
for path in args.dropFirst(3) {
    let icon = NSWorkspace.shared.icon(forFile: path)
    icon.size = NSSize(width: size, height: size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

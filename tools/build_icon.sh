#!/bin/zsh
# 把 Icon Composer 分层图标（.icon）交给系统渲染，得到带系统玻璃高光的 1024 PNG。
# 用法：tools/build_icon.sh <XXX.icon> <输出 PNG>
# 做法：编译进一个临时预览应用，登记后用系统接口取它的图标，再注销登记。
# 渲染结果跟随系统当前的外观和图标样式，生成深色图标时请在深色外观下运行。
set -e
ROOT=${0:A:h:h}
ICON=${1:A}; OUT=${2:A}
NAME=${ICON:t:r}
WORK="$ROOT/build/preview/$NAME"
APP="$WORK/${NAME}Preview.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$WORK"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 没有可执行文件的应用会被系统画上“禁止”标志，放一个空程序占位
echo 'int main(){return 0;}' > "$WORK/stub.c" && clang -o "$APP/Contents/MacOS/stub" "$WORK/stub.c"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.iconpreview.${NAME:l}</string>
<key>CFBundleName</key><string>${NAME}Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>stub</string>
<key>CFBundleIconName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>$NAME</string>
</dict></plist>
EOF
xcrun actool "$ICON" --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon "$NAME" --output-partial-info-plist "$WORK/partial.plist" >/dev/null
codesign -s - --force "$APP" 2>/dev/null

[[ -x "$ROOT/build/render_icons" ]] || swiftc -O -o "$ROOT/build/render_icons" "$ROOT/tools/render_icons.swift"
$LSREG -f "$APP"
"$ROOT/build/render_icons" "$WORK" 1024 "$APP"
$LSREG -u "$APP"          # 预览应用用完就从系统登记里移除，避免出现在“打开方式”等地方
cp "$WORK/${NAME}Preview.png" "$OUT"
echo "已生成：$OUT"

#!/bin/zsh
# 编译 DarkIconSwitcher 并安装为由系统按需唤起的后台程序（处理完即退出，平时不占内存）。
# 重复运行即可更新程序；已有的 config.json 和 icons/ 不会被覆盖。
set -e
SRC=${0:A:h}
DEST="$HOME/Library/Application Support/DarkIconSwitcher"
APP="$DEST/DarkIconSwitcher.app"
LABEL=local.darkiconswitcher
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$APP/Contents/MacOS" "$DEST/icons" "$HOME/Library/LaunchAgents"
swiftc -O -o "$APP/Contents/MacOS/DarkIconSwitcher" "$SRC/main.swift"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$LABEL</string>
<key>CFBundleName</key><string>DarkIconSwitcher</string>
<key>CFBundleExecutable</key><string>DarkIconSwitcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
# 用固定的签名证书签名：“App 管理”授权认的是签名身份，临时签名（-）每次编译都会变，授权随之失效。
# 可用 SIGN_IDENTITY 指定证书；默认取钥匙串里第一个可用的代码签名证书，没有则退回临时签名。
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk 'NR==1 && $2 ~ /^[0-9A-F]{40}$/ {print $2}')}
codesign -s "${IDENTITY:--}" --force "$APP"
[[ -z "$IDENTITY" ]] && echo "提示：没有找到签名证书，用的是临时签名，每次重新安装后都需要重新授权“App 管理”。"

# 首次安装：复制配置和深色图标
[[ -f "$DEST/config.json" ]] || cp "$SRC/config.json" "$DEST/config.json"
for f in "$SRC"/icons/*.png; do [[ -f "$DEST/icons/${f:t}" ]] || cp "$f" "$DEST/icons/"; done

# 按需唤起：系统设置文件变化（切换外观会写它）、配置里的应用被改动（比如更新冲掉图标）、登录时、每 10 分钟。
# 程序处理完就退出。改了 config.json 里的应用列表后，需要重新运行本脚本更新监视列表。
WATCH=$(/usr/bin/python3 -c 'import json,sys; [print("<string>%s</string>" % a["app"]) for a in json.load(open(sys.argv[1]))["apps"]]' "$DEST/config.json")
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$APP/Contents/MacOS/DarkIconSwitcher</string></array>
<key>WatchPaths</key><array>
<string>$HOME/Library/Preferences/.GlobalPreferences.plist</string>
$WATCH
</array>
<key>StartInterval</key><integer>600</integer>
<key>RunAtLoad</key><true/>
<key>ThrottleInterval</key><integer>2</integer>
<key>ProcessType</key><string>Background</string>
</dict></plist>
EOF
launchctl bootout gui/$UID/$LABEL 2>/dev/null && sleep 2 || true   # 等旧进程退出，否则重新加载会失败
launchctl bootstrap gui/$UID "$PLIST"
echo "已安装：$APP"
echo "配置：$DEST/config.json"
echo "日志：$HOME/Library/Logs/DarkIconSwitcher.log"

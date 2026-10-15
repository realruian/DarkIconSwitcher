#!/bin/zsh
# 停止并卸载 DarkIconSwitcher，并把配置里的应用恢复为原图标。
DEST="$HOME/Library/Application Support/DarkIconSwitcher"
LABEL=local.darkiconswitcher
launchctl bootout gui/$UID/$LABEL 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

# 恢复原图标
if [[ -f "$DEST/config.json" ]]; then
  /usr/bin/python3 -c 'import json,sys; [print(a["app"]) for a in json.load(open(sys.argv[1]))["apps"]]' "$DEST/config.json" |
  while read -r app; do
    /usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); function run(a){ return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(null, a[0], 0) }' "$app" >/dev/null && echo "已恢复：$app"
  done
  killall Dock
fi
rm -rf "$DEST"
echo "已卸载"

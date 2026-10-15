# DarkIconSwitcher

给没有做好深色图标的 macOS 应用换上自制的深色图标，并跟随系统深浅色自动切换。

目前处理的应用：微信、Antigravity。

## 工作方式

后台程序（`switcher/`）没有界面，也不常驻：由 launchd 在以下时机唤起，处理完就退出，平时不占内存（运行时约 15 MB，每次几秒）。

- 唤起时机：系统设置文件 `~/Library/Preferences/.GlobalPreferences.plist` 变化（切换外观会写它）、配置里的应用包被改动（比如更新）、登录时、每 10 分钟。
- 唤起后先等设置稳定 1.5 秒再动手；处理期间设置又变了（连续快速切换）就再处理一轮。
- 系统切到深色时，用 `NSWorkspace.setIcon` 给配置里的应用设置自定义深色图标；切回浅色时恢复原图标。
- 跟随的是“系统设置 → 外观 → 图标与小组件样式”：选“深色 · 自动”时跟随界面深浅色；选“深色 · 始终”时一直用深色图标；选“浅色”“透明”“着色”时用原图标。
- 应用更新会冲掉自定义图标，应用包一被改动程序就会被唤起并补回。
- 换完图标后会删掉 Dock 的图标缓存再重启 Dock，所以切换外观后 Dock 会闪一下。
- 日志：`~/Library/Logs/DarkIconSwitcher.log`

## 目录

| 位置 | 内容 |
|---|---|
| `switcher/` | 后台程序源码 `main.swift`、安装和卸载脚本、配置 `config.json`、定稿的深色图标 `icons/` |
| `icons/<应用>/` | 每个应用的分层图标源文件（`.icon`）、抠图层的脚本、原图标 |
| `tools/` | 通用工具，见下文 |
| `archive/` | 试验过程中的图和旧版本，只在本地，不进 git |
| `build/` | 编译产物和预览应用，可随时删除 |

## 安装、更新、卸载

```bash
switcher/install.sh      # 编译、签名、安装为开机自启；改了代码后重新运行即可更新
switcher/uninstall.sh    # 停止并卸载，同时恢复所有应用的原图标
```

安装位置：`~/Library/Application Support/DarkIconSwitcher/`（程序、`config.json`、`icons/`）。
重新安装不会覆盖那里已有的 `config.json` 和图标；改了 `switcher/icons/` 里的同名图标后，需要手动复制过去。

### 首次安装需要授权

程序要修改 `/Applications` 里的应用，必须在“系统设置 → 隐私与安全性 → App 管理”里添加 `DarkIconSwitcher.app` 并打开开关。没有授权时日志会写“失败（检查“App 管理”权限）”。

## 加一个新应用

1. 做深色图标（见下一节），得到 1024 PNG。
2. 把 PNG 放进 `~/Library/Application Support/DarkIconSwitcher/icons/`（同时放一份到 `switcher/icons/` 留底）。
3. 在那里的 `config.json` 的 `apps` 里加一项：`{ "app": "/Applications/XXX.app", "dark": "icons/xxx-dark.png" }`。

然后重新运行 `switcher/install.sh`，更新“应用被改动时唤起”的监视列表。

## 做深色图标

原则：按苹果的分层图标格式做（深色背景层 + 图形层），交给系统渲染，这样玻璃高光、阴影由系统自己画，和其他图标一致。不要自己画高光，也不要直接用平面图。

1. **取出图形层**
   - 新式分层图标（应用包里的 `Assets.car` 有 `IconImageStack`）：用 `tools/extract_car` 导出原始图层。图层是矢量格式时取不出来，改用下一种方法。
   - 旧式单张图标，或取不出图层时：从原图标里把图形从底色上抠出来，参考 `icons/wechat/make_layer.py`（白色图形在彩色底上）和 `icons/antigravity/make_layer.py`（彩色图形在白底上）。
   - 图层要按 Icon Composer 的 1024 画布摆放：原图标主体（约 100–924 像素）对应画布的 0–1024。
2. **写 `.icon`**：复制 `icons/wechat/WeChatDark.icon`，换掉 `Assets/` 里的图层并改 `icon.json` 里的文件名。现在用的参数：深灰渐变背景，图形层开 `glass`、不开半透明。
3. **系统渲染**：在深色外观下运行 `tools/build_icon.sh icons/xxx/XxxDark.icon 输出.png`。

Python 脚本用项目里的环境运行：`.venv/bin/python ...`（没有的话：`python3 -m venv .venv && .venv/bin/pip install numpy pillow`）。

## 工具

| 工具 | 用途 |
|---|---|
| `tools/build_icon.sh` | `.icon` → 系统渲染的 1024 PNG |
| `tools/extract_car.m` | 从 `Assets.car` 导出位图资源和图标图层（编译方法见文件开头） |
| `tools/render_icons.swift` | 按系统当前外观渲染应用图标，即 Dock / 访达实际显示的样子 |
| `tools/find_light_icons.py` | 配合上一个，找出深色外观下背景仍偏浅的应用并出对比图 |
| `tools/seticon.swift` | 手动设置 / 恢复某个应用的图标（`--reset`） |

扫描全部应用：

```bash
mkdir -p build/scan && swiftc -O -o build/render_icons tools/render_icons.swift
find /Applications -maxdepth 2 -name "*.app" -not -path "*/*.app/*" -print0 | xargs -0 build/render_icons build/scan 256
.venv/bin/python tools/find_light_icons.py build/scan build/深色下仍偏浅的图标
```

## 踩过的坑

- **签名要固定**：“App 管理”授权认的是签名身份。临时签名（`codesign -s -`）每次编译都会变，授权随之失效。`install.sh` 默认用钥匙串里第一个代码签名证书（可用环境变量 `SIGN_IDENTITY` 指定；没有证书时退回临时签名，每次重装都要重新授权）。如果换了签名，要先运行 `tccutil reset SystemPolicyAppBundles local.darkiconswitcher` 清掉旧记录，再重新添加授权；只在设置里删掉再加回来不一定能清干净。
- **没授权时会“改一半”**：系统可能删掉图标文件 `Icon\r`，却留下“有自定义图标”的标记，应用会显示成文件夹。程序会分别检查这两部分，拿到授权后会自动修正。
- **Dock 有自己的图标缓存**：`$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache`。只重启 Dock 会沿用旧缓存，表现为图标“反了”（显示上一次的状态）。
- **连续快速切换外观**：程序等设置稳定 1.5 秒后才动手，换完再等 1 秒刷新 Dock，避免和 Dock 重启撞车。
- **不常驻**：早期版本常驻后台，约占 15 MB 内存（其中约 8 MB 是解码图片留下的缓存）。现在改为 launchd 按需唤起（`WatchPaths` + `StartInterval`），换图标后程序自己改动了应用包会再被唤起一次，这一次检查到无事可做就直接退出。
- **有的应用运行时会自己设 Dock 图标**：比如 Aside。它的深色图标是完整的，但开着时会用白色版覆盖 Dock 图标，外部换图标对它无效。

# DarkIconSwitcher

<p><a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a></p>

Replaces icons for macOS apps that lack proper dark mode icons with custom-made dark icons, and switches them automatically along with the system appearance.

Currently supported apps: WeChat, Antigravity.

## How It Works

The background helper (`switcher/`) has no UI and does not stay resident in memory: `launchd` invokes it on demand at the triggers below, and it exits as soon as it finishes—using zero memory when idle (and ~15 MB for a few seconds while running).

- **Triggers**: Changes to the system preferences file `~/Library/Preferences/.GlobalPreferences.plist` (written when switching appearance), modifications to any configured app bundle (e.g., app updates), at login, and every 10 minutes.
- After being invoked, it waits 1.5 seconds for settings to settle before acting; if settings change again while it is working (rapid consecutive toggles), it runs another pass.
- When the system switches to Dark mode, it sets the custom dark icon on configured apps via `NSWorkspace.setIcon`; when switching back to Light mode, it restores the original icon.
- Follows **System Settings → Appearance → Icon & widget style**: when set to "Dark · Automatic", it follows the interface light/dark appearance; when set to "Dark · Always", it always uses the dark icon; when set to "Light", "Clear", or "Tinted", it uses the original icon.
- App updates overwrite custom icons; as soon as an app bundle is modified, the helper is triggered and reapplies the icon.
- After changing icons, it clears the Dock icon cache and restarts the Dock, so the Dock will briefly flash after an appearance switch.
- **Log**: `~/Library/Logs/DarkIconSwitcher.log`

## Directory Structure

| Path | Contents |
|---|---|
| `switcher/` | Background helper source `main.swift`, install and uninstall scripts, configuration `config.json`, finalized dark icons `icons/` |
| `icons/<app>/` | Per-app layered icon source (`.icon`), layer-extraction scripts, original icon |
| `tools/` | General-purpose utilities (see below) |
| `archive/` | Experimental images and older versions; kept locally only, not tracked in git |
| `build/` | Build artifacts and preview apps; safe to delete at any time |

## Install, Update, and Uninstall

```bash
switcher/install.sh      # Compile, sign, and install as a login item; re-run after code changes to update
switcher/uninstall.sh    # Stop and uninstall, and restore original icons for all configured apps
```

Install location: `~/Library/Application Support/DarkIconSwitcher/` (binary, `config.json`, `icons/`).
Reinstalling will not overwrite an existing `config.json` or icons in that directory; if you update an icon with the same name in `switcher/icons/`, copy it over manually.

### First-Time Authorization

Because the helper modifies apps inside `/Applications`, you must add `DarkIconSwitcher.app` and enable its toggle under **System Settings → Privacy & Security → App Management**. Without authorization, the log will report a failure prompting you to check "App Management" permission.

## Adding a New App

1. Create a dark icon (see the next section) to produce a 1024×1024 PNG.
2. Place the PNG into `~/Library/Application Support/DarkIconSwitcher/icons/` (and keep a backup copy in `switcher/icons/`).
3. Add an entry to `apps` in `config.json` there: `{ "app": "/Applications/XXX.app", "dark": "icons/xxx-dark.png" }`.

Then re-run `switcher/install.sh` to update the watched paths list for app bundle modifications.

## Creating a Dark Icon

Principle: Build icons using Apple's layered icon format (a dark background layer + foreground artwork layer) and let the system render them, so glass highlights and shadows are drawn natively by macOS to match other icons. Do not paint highlights by hand or use flat single-layer images directly.

1. **Extract the foreground artwork layer**
   - Modern layered icons (where the app bundle's `Assets.car` contains an `IconImageStack`): use `tools/extract_car` to export the raw image layers. If the layers are vector-based and cannot be extracted, fall back to the next method.
   - Legacy single-image icons, or when layers cannot be extracted: isolate the foreground graphic from its background color in the original icon. See `icons/wechat/make_layer.py` (white graphic on a colored background) and `icons/antigravity/make_layer.py` (colored graphic on a white background).
   - Position the layer on Icon Composer's 1024×1024 canvas: the main body of the original icon (roughly pixels 100–924) maps to 0–1024 on the canvas.
2. **Create the `.icon` bundle**: Copy `icons/wechat/WeChatDark.icon`, replace the layer asset inside `Assets/`, and update the filename in `icon.json`. Current parameters: dark gray gradient background, with `glass` enabled and translucency disabled on the foreground layer.
3. **Render via the system**: While in Dark appearance, run `tools/build_icon.sh icons/xxx/XxxDark.icon output.png`.

Run Python scripts using the project virtual environment: `.venv/bin/python ...` (if not set up yet: `python3 -m venv .venv && .venv/bin/pip install numpy pillow`).

## Tools

| Tool | Purpose |
|---|---|
| `tools/build_icon.sh` | `.icon` → system-rendered 1024×1024 PNG |
| `tools/extract_car.m` | Export bitmap assets and icon layers from `Assets.car` (see header comment for compilation instructions) |
| `tools/render_icons.swift` | Render app icons under the current system appearance, matching how Dock and Finder actually display them |
| `tools/find_light_icons.py` | Paired with `render_icons.swift`, find apps whose backgrounds remain light in Dark mode and generate a comparison sheet |
| `tools/seticon.swift` | Manually set or restore (`--reset`) an app's icon |

Scan all installed apps:

```bash
mkdir -p build/scan && swiftc -O -o build/render_icons tools/render_icons.swift
find /Applications -maxdepth 2 -name "*.app" -not -path "*/*.app/*" -print0 | xargs -0 build/render_icons build/scan 256
.venv/bin/python tools/find_light_icons.py build/scan build/深色下仍偏浅的图标
```

## Caveats & Lessons Learned

- **Keep code signing identity stable**: "App Management" TCC authorization is tied to the code signing identity. Ad-hoc signing (`codesign -s -`) changes on every build, invalidating permission. By default, `install.sh` uses the first code signing certificate found in your Keychain (override with the `SIGN_IDENTITY` environment variable; falls back to ad-hoc signing if no certificate is present, requiring re-authorization after each reinstall). If you change signing identities, run `tccutil reset SystemPolicyAppBundles local.darkiconswitcher` first to clear the old TCC record before re-authorizing; simply removing and re-adding the app in System Settings may not cleanly reset it.
- **Partial writes without authorization**: Without permission, macOS may delete the `Icon\r` file while leaving the "has custom icon" Finder flag set, causing the app to appear as a generic folder. The helper checks both parts independently and repairs broken states automatically once authorization is granted.
- **Dock maintains its own icon cache**: `$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache`. Restarting the Dock without deleting this cache reuses stale icons, making icons appear "inverted" (stuck showing the previous appearance state).
- **Rapid consecutive appearance switches**: The helper waits 1.5 seconds for preferences to settle before applying icons, and waits another 1 second after finishing before refreshing the Dock to avoid racing with Dock restarts.
- **On-demand execution instead of a resident daemon**: Early versions ran persistently in the background, taking ~15 MB of RAM (~8 MB from decoded image caches). It now uses `launchd` on-demand activation (`WatchPaths` + `StartInterval`). Modifying an app bundle when setting an icon triggers `launchd` one extra time; on that follow-up run, the helper sees everything is already in sync and exits immediately.
- **Apps that override their Dock icon at runtime**: For example, Aside. It ships a complete dark icon, but while running it overwrites its Dock tile with a white icon at runtime, so external bundle icon replacement has no effect while the app is open.

## License

Code is open-sourced under the [MIT License](LICENSE).

The application icons in this repository (`icons/*/original.png`), as well as the custom dark icons and layers derived from them, remain the property of their respective trademark and copyright holders (WeChat belongs to Tencent; Antigravity belongs to Google). They are not covered by the MIT License and are provided solely as personal appearance customization references. They will be removed promptly upon request by the rights holders.

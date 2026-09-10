# RillDemoiOS

An iOS Simulator app wrapping the shared `RillDemoKit` (in `../RillDemo`), which
renders a chunked Markdown stream on a phone: theme switcher, chunk-size and delay
sliders, the showcase document, and a live analytics HUD (parse ms, dirty-tail
bytes, blocks reused/rendered/skipped/committed).

The reusable demo UI and logic live in `../RillDemo/Sources/RillDemoKit`; this
target only adds an `@main` entry point and links the local `Rill` package.

## Run it

```bash
# 1. Generate the Xcode project (the .xcodeproj is gitignored)
brew install xcodegen        # if needed
cd Examples/RillDemoiOS
xcodegen generate

# 2. Build for a simulator
xcodebuild -project RillDemoiOS.xcodeproj -scheme RillDemoiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath .build-xc build

# 3. Install + launch
UDID=$(xcrun simctl list devices available | grep -m1 'iPhone 16 (' | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null; open -a Simulator
xcrun simctl install "$UDID" .build-xc/Build/Products/Debug-iphonesimulator/RillDemoiOS.app
xcrun simctl launch "$UDID" com.batuhansk.RillDemoiOS
```

Tap **Stream** to replay the showcase document. To auto-start streaming on launch
(handy for screenshots / UI tests), pass the env var:

```bash
SIMCTL_CHILD_RILL_DEMO_AUTOSTREAM=1 \
  xcrun simctl launch --terminate-running-process "$UDID" com.batuhansk.RillDemoiOS
```

Or just open `RillDemoiOS.xcodeproj` in Xcode and hit Run.

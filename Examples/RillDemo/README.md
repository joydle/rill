# RillDemo

A macOS SwiftUI app that streams a showcase Markdown document through
[Rill](../../) in configurable chunks, with a live analytics HUD.

It is also the shared source for [`../RillDemoiOS`](../RillDemoiOS), which wraps
the same `RillDemoKit` in an iOS Simulator target.

## What it shows

- **Chunked streaming.** `StreamingSimulator` feeds the showcase document to a
  `MarkdownSource` in slices, so you can watch committed blocks stay put while
  the live tail redraws.
- **Live analytics.** `HUDAnalyticsSink` conforms to `MarkdownAnalytics` and the
  HUD reports parse time in milliseconds, dirty-tail bytes, total bytes, and
  blocks reused / rendered / skipped / committed.
- **Theme switching.** Four themes from `ThemeCatalog`: Default, Sepia,
  Midnight, and High Contrast.
- **Streaming controls.** Sliders for chunk size (1–40 bytes) and inter-chunk
  delay (0–100 ms), plus Stream/Stop and Reset.

## Run it

```bash
cd Examples/RillDemo
swift run RillDemo
```

Or open `Package.swift` in Xcode and run the `RillDemo` scheme.

## Layout

- `Sources/RillDemoKit/` — the testable logic and views: `StreamingSimulator`,
  `HUDAnalyticsSink`, `HUDView`, `DemoRootView`, `ShowcaseDocument`,
  `ThemeCatalog`, and `QACatalog`.
- `Sources/RillDemo/` — the thin `@main` executable hosting the kit's root view.
- `Tests/RillDemoTests/` — headless tests over the kit.

Because the logic lives in `RillDemoKit` rather than the executable, it runs
under `swift test` with no simulator:

```bash
swift test
```

## Environment variables

- `RILL_DEMO_AUTOSTREAM=1` — begin streaming on launch, useful for screenshots.

`QACatalog` ships a set of single-construct Markdown cases for visual checks. It
is part of the kit, but only the iOS target selects a case at launch (via
`RILL_QA_CASE`); this macOS app always renders the showcase document.

The app depends on the Rill package by relative path (`../../`), so it always
builds against the working copy rather than a published version.

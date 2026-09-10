# Contributing to Rill

Thanks for your interest in improving Rill. This document explains how to get
set up and the conventions the project follows.

## Development setup

Rill is a pure Swift Package with no external dependencies. To build and test:

```bash
swift build
swift test
```

Both must pass cleanly before any change is merged.

## Project layout

Rill is one SPM package with four layered library products:

- `RillCore` — Foundation-only AST and the incremental streaming parser.
- `RillMath` — Foundation-only LaTeX tokenizer and TeX-style box layout.
- `RillAnalytics` — Foundation-only metrics, the analytics protocol, and sinks.
- `RillUI` — the SwiftUI renderer; the only module allowed to import SwiftUI/UIKit.

`RillCore`, `RillMath`, and `RillAnalytics` must **never** import SwiftUI or
UIKit. This boundary is enforced by `LayeringGuardTests`, which fails the build
if a forbidden import appears.

## Conventions

- `swift-tools-version:6.0`, Swift language mode v6 (strict concurrency).
- Every public model type is a `Sendable` value type with triple-slash doc
  comments on public symbols.
- Test-driven development: write the failing test first, then the implementation.
- Tests run headlessly under `swift test` — no simulator, no pixel snapshots.
- Conventional commit messages. Keep changes scoped and reversible.

## Pull requests

1. Branch off `main`.
2. Add or update tests for your change.
3. Ensure `swift build` and `swift test` are green.
4. Open a PR describing the change and the reasoning behind it.

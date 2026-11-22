# Raker

Clear the clutter. Keep what matters.

Raker is a native macOS app that shows what uses your storage, explains every item, and removes only what you approve, with a receipt you can undo. It's open source and every feature is free.

> **Status:** early development (milestone M0, foundations). The scanning engine, safety policy, a command-line harness and the first SwiftUI screens work; nothing removes files yet.

## Documents

- [docs/features.md](docs/features.md): research into Mac cleaner capabilities and the release scope
- [docs/architecture.md](docs/architecture.md): how Raker is built, its safety model, UI/UX design and roadmap

## Repository layout

```text
docs/                  research and architecture
Packages/RakerKit/     all app code, as a Swift package of focused modules
Scripts/               test and development helpers
.github/workflows/     continuous integration
```

The Xcode project for the signed app, privileged helper and CLI bundle arrives once the toolchain below is in place.

## Requirements

- macOS 15 or later
- Swift 6 (Xcode 26 or later; Xcode 27 recommended)

The Command Line Tools alone can build and test the package. Two caveats apply until full Xcode is installed:

- SwiftUI's `@State`, `@Entry` and `#Preview` are macros whose plugin ships only with Xcode, so UI code keeps view state in `@Observable` feature models (which the architecture prefers anyway).
- `Scripts/test.sh` passes the Swift Testing macro plugin path explicitly, working around a SwiftPM quirk.

## Build and run

```sh
# Tests
Scripts/test.sh

# Command-line harness (reads metadata only; never removes anything)
cd Packages/RakerKit
swift run raker du ~/Downloads --depth 2
swift run raker largest /Applications --count 10
swift run raker volume
swift run raker check ~/Library/Caches/com.example ~/Documents/file.pdf

# SwiftUI shell, wrapped in an app bundle and opened
Scripts/run-dev-app.sh
```

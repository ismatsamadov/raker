# Raker

Clear the clutter. Keep what matters.

Raker is a native macOS app that shows what uses your storage, explains every item, and removes only what you approve, with a receipt you can undo. It's open source and every feature is free.

> **Status:** early development (milestone M0, foundations). The scanning engine, the safety policy, the rule engine with a baseline pack (caches, temporary files, logs and developer caches, each explained), the cleanup engine (items that rebuild automatically are deleted, everything else goes to the Trash, with receipts, history and restore), Downloads & Installers and Large & Old (with where files came from and when they were last opened), exact duplicates (one copy of each always stays), exclusions and locked originals (shared by the app and the CLI), the Tray (what you choose in any section, kept across relaunches, reviewed and cleaned in one go), an inspector for the item in focus with keyboard review (Space previews, Delete stages, E excludes, L locks), "what is this?" for anything in Largest Items, which can also go in the Tray, a first-run welcome, an Access Center that shows which protected areas Raker can read and how to allow the rest, a command-line harness and the first SwiftUI screens work.

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

# Command-line harness. Only `clean --execute` removes anything.
cd Packages/RakerKit
swift run raker du ~/Downloads --depth 2
swift run raker largest /Applications --count 10
swift run raker downloads                   # where each download came from; installers of installed apps
swift run raker large ~ --not-opened-days 365
swift run raker dupes ~/Pictures            # identical files; ★ marks the copy that stays
swift run raker junk                        # caches, temporary files and logs, explained
swift run raker explain ~/Library/Caches    # what is this, who owns it, is it safe?
swift run raker clean                       # shows the plan; add --execute to clean
swift run raker history                     # past cleanups and their receipts
swift run raker restore <id>                # put back what a cleanup moved to the Trash
swift run raker exclude ~/Projects          # never suggest anything there (--lock: locked original)
swift run raker exclusions                  # list them; --remove <path> to drop one
swift run raker volume
swift run raker check ~/Library/Caches/com.example ~/Documents/file.pdf

# SwiftUI shell, wrapped in an app bundle and opened. Run setup-dev-signing.sh once
# first, or macOS asks for folder access again after every rebuild.
Scripts/setup-dev-signing.sh
Scripts/run-dev-app.sh
```

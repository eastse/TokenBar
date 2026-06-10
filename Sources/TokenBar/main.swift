import AppKit

// Entry point. `--smoke` keeps the Phase 1 CLI bridge check available for CI;
// anything else boots the menu-bar app (no storyboard, no .app bundle yet).

if CommandLine.arguments.contains("--smoke") {
    exit(Smoke.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

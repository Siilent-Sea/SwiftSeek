import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// N4 hotfix (post-PROJECT COMPLETE): default to .accessory at the
// earliest possible point so a user with a fresh DB never sees Dock
// flash during startup. AppDelegate.applicationDidFinishLaunching
// re-asserts .accessory and (only when dock_icon_visible=1) lifts to
// .regular after DB open. Without this, the previous `.regular` here
// briefly enabled Dock + LaunchServices "Recent Applications" before
// the AppDelegate flip ran — a real regression Codex caught while
// triaging a "Dock still residing" user report.
app.setActivationPolicy(.accessory)
app.run()

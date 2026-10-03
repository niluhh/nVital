import AppKit

// The interface is built in code (no storyboards or XIBs).
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()

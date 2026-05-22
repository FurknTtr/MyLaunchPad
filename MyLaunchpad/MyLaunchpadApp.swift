import SwiftUI
import AppKit

@main
struct MyLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var iconCache: [String: NSImage] = [:]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Arka planda ikonları önceden yükle
        DispatchQueue.global(qos: .background).async {
            self.preloadIcons()
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Pencere kapansa bile arka planda yaşa
    }
    
    private func preloadIcons() {
        let dirs = ["/Applications", "/System/Applications"]
        let fm = FileManager.default
        for dir in dirs {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in urls where url.pathExtension == "app" {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 80, height: 80)
                iconCache[url.path] = icon
            }
        }
    }
    
    func cachedIcon(for path: String) -> NSImage? {
        return iconCache[path]
    }
}

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

        // 4/5 parmak pinch: içeri = aç, dışarı = kapat
        let monitor = GestureMonitor.shared
        monitor.onPinchIn = { [weak self] in self?.showLaunchpad() }
        monitor.onPinchOut = { [weak self] in self?.hideLaunchpad() }
        monitor.start()

        // Uykudan uyanınca trackpad dinlemeyi yeniden başlat
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            GestureMonitor.shared.restart()
        }
    }

    func showLaunchpad() {
        NSApp.unhide(nil)
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        // Arka plandaki (accessory) bir uygulamanın öne gelmesi için zorla etkinleştir;
        // yeni NSApp.activate() başka uygulama öndeyken etkinleştirmeyi reddedebiliyor.
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLaunchpad() {
        // Uygulamanın "aktif" sayılmasına bakmadan, pencere ekrandaysa gizle
        guard !NSApp.isHidden,
              let window = NSApplication.shared.windows.first,
              window.isVisible else { return }
        NSApp.hide(nil)
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

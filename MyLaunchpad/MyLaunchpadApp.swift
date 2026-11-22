import SwiftUI
import AppKit

@main
struct MyLaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Asıl tam ekran pencereyi AppDelegate kendisi oluşturuyor
        // (klavye alabilen özel pencere). Burada boş bir sahne yeterli.
        Settings { EmptyView() }
    }
}

/// Kenarlıksız pencereler varsayılan olarak klavye odağı alamaz;
/// bu alt sınıf Esc, ok tuşları ve arama kutusunun çalışmasını sağlar.
final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var iconCache: [String: NSImage] = [:]
    private var window: LaunchpadWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        showLaunchpad()

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

    private func createWindow() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = LaunchpadWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .mainMenu + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        // Hangi masaüstündeysen orada açılsın, tam ekran uygulamaların üstünde de görünsün
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.sizingOptions = [] // SwiftUI pencereyi küçültmesin, tam ekran kalsın
        window.contentView = hostingView

        self.window = window
    }

    func showLaunchpad() {
        guard let window else { return }
        if let screen = NSScreen.main, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        // Arka plandaki (accessory) bir uygulamanın öne gelmesi için zorla etkinleştir;
        // yeni NSApp.activate() başka uygulama öndeyken etkinleştirmeyi reddedebiliyor.
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLaunchpad() {
        // Uygulamanın "aktif" sayılmasına bakmadan, pencere ekrandaysa gizle
        guard !NSApp.isHidden, let window, window.isVisible else { return }
        NSApp.hide(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLaunchpad()
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

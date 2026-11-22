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
        LaunchpadPresenter.shared.show()

        // Arka planda ikonları önceden yükle
        DispatchQueue.global(qos: .background).async {
            self.preloadIcons()
        }

        // 4/5 parmak pinch: parmakla birlikte açılır/kapanır
        let monitor = GestureMonitor.shared
        monitor.onPinchChanged = { ratio in
            LaunchpadPresenter.shared.pinchChanged(ratio: ratio)
        }
        monitor.onPinchEnded = { ratio, velocity in
            LaunchpadPresenter.shared.pinchEnded(ratio: ratio, velocity: velocity)
        }
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

        let hostingView = NSHostingView(rootView: LaunchpadRoot(presenter: .shared))
        hostingView.sizingOptions = [] // SwiftUI pencereyi küçültmesin, tam ekran kalsın
        window.contentView = hostingView

        self.window = window
        LaunchpadPresenter.shared.window = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LaunchpadPresenter.shared.show()
        return true
    }

    // Cmd+Tab ya da başka bir uygulamaya tıklayınca Launchpad kapansın (eski Launchpad'deki gibi)
    func applicationDidResignActive(_ notification: Notification) {
        LaunchpadPresenter.shared.hide()
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

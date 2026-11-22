//
//  LaunchpadViewModel.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI
import AppKit
import Combine

class LaunchpadViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var currentPage: Int = 0 {
        didSet { UserDefaults.standard.set(currentPage, forKey: "LastLaunchpadPage") }
    }
    @Published var isEditing = false
    @Published var searchText = ""
    @Published var dragOffset: CGFloat = 0
    
    /// Sayfa genişliği (ContentView ekran boyutuna göre günceller)
    var pageWidth: CGFloat = 1440

    /// Klavye ve sayfa noktaları için standart sayfa geçişi (zıplamasız yay)
    static let pageAnimation = Animation.spring(duration: 0.4, bounce: 0)

    private var scrollMonitor: Any?
    private var snapWorkItem: DispatchWorkItem?

    // Sürükleme durumu
    private var isDragging = false
    private var velocity: CGFloat = 0          // nokta/saniye
    private var lastEventTime: TimeInterval = 0

    // Sayfa değiştirme eşikleri
    private let distanceThreshold: CGFloat = 0.3   // sayfa genişliğinin %30'u kadar sürükleyince
    private let flickVelocity: CGFloat = 400       // ya da bu hızdan hızlı fırlatınca (nokta/sn)
    private let edgeResistance: CGFloat = 0.3      // ilk/son sayfada lastik efekti

    private var pageCount: Int { max(1, apps.chunked(into: 35).count) }

    init() {
        self.currentPage = UserDefaults.standard.integer(forKey: "LastLaunchpadPage")
    }

    func setupMonitor() {
        if scrollMonitor != nil { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        // Parmak kalktıktan sonra macOS'un gönderdiği "momentum" olaylarını yok say:
        // sayfa zaten parmağın kalktığı anda yerine oturmaya başladı.
        if !event.momentumPhase.isEmpty { return }

        // Trackpad hareketinin bittiği an: hemen yerine oturt (bekleme yok)
        if event.phase == .ended || event.phase == .cancelled {
            if isDragging { endDrag() }
            return
        }

        let dx = event.scrollingDeltaX
        let isHorizontal = abs(dx) > abs(event.scrollingDeltaY)
        guard isDragging || isHorizontal, dx != 0 else { return }

        // Parmak hızını ölç (yumuşatılmış)
        let now = event.timestamp
        let dt = now - lastEventTime
        if !isDragging || dt <= 0 || dt > 0.1 {
            velocity = 0
        } else {
            velocity = velocity * 0.6 + (dx / CGFloat(dt)) * 0.4
        }
        lastEventTime = now
        isDragging = true

        // İlk/son sayfanın kenarında lastik gibi direnç
        let atLeftEdge = currentPage == 0 && dragOffset + dx > 0
        let atRightEdge = currentPage == pageCount - 1 && dragOffset + dx < 0
        dragOffset += (atLeftEdge || atRightEdge) ? dx * edgeResistance : dx

        // Fare tekerleği gibi "phase" göndermeyen cihazlar için yedek: kısa bekleme sonrası oturt
        if event.phase.isEmpty {
            snapWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in self?.endDrag() }
            snapWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
    }

    private func endDrag() {
        snapWorkItem?.cancel()
        isDragging = false
        let width = max(pageWidth, 1)

        // Hızlı fırlatma varsa yönü hız belirler, yoksa sürüklenen mesafe
        var target = currentPage
        if abs(velocity) > flickVelocity {
            target += velocity < 0 ? 1 : -1
        } else if dragOffset < -width * distanceThreshold {
            target += 1
        } else if dragOffset > width * distanceThreshold {
            target -= 1
        }
        target = max(0, min(target, pageCount - 1))

        // Animasyon parmağın bıraktığı hızla başlasın, sonra yumuşakça yavaşlasın
        let fromX = -CGFloat(currentPage) * width + dragOffset
        let toX = -CGFloat(target) * width
        let distance = toX - fromX
        var relativeVelocity: Double = 0
        if abs(distance) > 1 {
            relativeVelocity = min(max(Double(velocity / distance), 0), 10)
        }
        velocity = 0

        withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: relativeVelocity)) {
            currentPage = target
            dragOffset = 0
        }
    }

    func turnPage(direction: Int) {
        let target = max(0, min(currentPage + direction, pageCount - 1))
        withAnimation(Self.pageAnimation) {
            currentPage = target
            dragOffset = 0
        }
    }

    func goToPage(_ page: Int) {
        let target = max(0, min(page, pageCount - 1))
        withAnimation(Self.pageAnimation) {
            currentPage = target
            dragOffset = 0
        }
    }
    
    func cleanup() {
        if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor); scrollMonitor = nil }
        folderWatchers.forEach { $0.cancel() }
        folderWatchers.removeAll()
    }

    // MARK: - Yeni/silinen uygulamaları otomatik algılama

    private var folderWatchers: [DispatchSourceFileSystemObject] = []
    private var reloadWorkItem: DispatchWorkItem?

    /// Uygulamalar klasörlerini izler; bir uygulama eklenince, silinince
    /// ya da güncellenince listeyi kendiliğinden yeniler.
    func startWatchingAppFolders() {
        guard folderWatchers.isEmpty else { return }
        // Sistem klasörleri (/System/Applications) salt okunur, izlemeye gerek yok
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            folderWatchers.append(source)
        }
    }

    private func scheduleReload() {
        // Bir kurulum art arda çok sayıda değişiklik yapar; hepsi bitince tek sefer yenile
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.loadApps()
            // Büyük uygulamaların kopyalanması sürebilir; simgesi tam gelsin diye bir kez daha yenile
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.loadApps() }
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
    
    func loadApps() {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "\(NSHomeDirectory())/Applications"]
        var loaded: [AppItem] = [], added: Set<String> = []
        for dir in dirs {
            let url = URL(fileURLWithPath: dir)
            if let urls = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for u in urls where u.pathExtension == "app" {
                    let name = u.deletingPathExtension().lastPathComponent
                    if !added.contains(name) {
                        let attrs = try? fm.attributesOfItem(atPath: u.path)
                        loaded.append(AppItem(name: name, path: u.path, icon: NSWorkspace.shared.icon(forFile: u.path), creationDate: attrs?[.creationDate] as? Date ?? Date.distantPast, isSystemApp: u.path.hasPrefix("/System")))
                        added.insert(name)
                    }
                }
            }
        }
        self.apps = loaded.sorted { $0.isSystemApp != $1.isSystemApp ? $0.isSystemApp : ($0.isSystemApp ? $0.name < $1.name : $0.creationDate < $1.creationDate) }
    }
    
    /// Silmeden önce eski Launchpad'deki gibi onay sorar
    func confirmDelete(_ app: AppItem) {
        let alert = NSAlert()
        alert.messageText = "“\(app.name)” Çöp Sepeti'ne taşınsın mı?"
        alert.informativeText = "Fikrini değiştirirsen uygulamayı Çöp Sepeti'nden geri alabilirsin."
        alert.icon = app.icon
        alert.addButton(withTitle: "Çöp Sepeti'ne Taşı")
        alert.addButton(withTitle: "Vazgeç")
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[1].keyEquivalent = "\u{1b}" // Esc = Vazgeç

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn { self?.deleteApp(app) }
        }
        // Tam ekran pencerenin üstünde görünmesi için ona bağlı açılır
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    func deleteApp(_ app: AppItem) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: app.path)]) { _, _ in
            DispatchQueue.main.async { self.apps.removeAll { $0.id == app.id } }
        }
    }
}

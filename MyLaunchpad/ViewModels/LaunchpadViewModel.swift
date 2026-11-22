//
//  LaunchpadViewModel.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI
import AppKit
import Combine

/// Sürüklenen simgenin ekrandaki konumu. Ayrı tutuluyor ki fare her kıpırdadığında
/// bütün simge ızgarası değil, sadece sürüklenen simge yeniden çizilsin.
final class DragOverlayState: ObservableObject {
    @Published var position: CGPoint = .zero
}

class LaunchpadViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var currentPage: Int = 0 {
        didSet {
            UserDefaults.standard.set(currentPage, forKey: "LastLaunchpadPage")
            moveSelectionToCurrentPage()
        }
    }
    @Published var isEditing = false
    /// "Diğer" klasörünün içindekiler (Yardımcı Programlar) ve paneli açık mı
    @Published var utilityApps: [AppItem] = []
    @Published var isFolderOpen = false
    @Published var isSettingsOpen = false
    /// Klasör ya da ayarlar paneli açıkken ızgarada gezinme/sürükleme/kaydırma durur
    var isPanelOpen: Bool { isFolderOpen || isSettingsOpen }
    static let utilitiesFolderName = "Diğer"
    static let utilitiesFolderPath = "folder://utilities"
    private static let utilitiesDirectory = "/System/Applications/Utilities/"
    @Published var searchText = ""
    @Published var dragOffset: CGFloat = 0
    
    /// Sayfa genişliği (ContentView ekran boyutuna göre günceller)
    var pageWidth: CGFloat = 1440

    /// Klavye ve sayfa noktaları için standart sayfa geçişi (zıplamasız yay)
    static let pageAnimation = Animation.spring(duration: 0.5, bounce: 0)
    /// Bırakınca devralınan hızın üst sınırı (yükseldikçe sayfa "fırlar")
    private let maxSnapVelocity: Double = 3

    private var scrollMonitor: Any?
    private var snapWorkItem: DispatchWorkItem?

    // Sürükleme durumu
    private var isDragging = false
    private var velocity: CGFloat = 0          // nokta/saniye
    private var lastEventTime: TimeInterval = 0

    // Sayfa değiştirme eşikleri
    private let distanceThreshold: CGFloat = 0.3   // sayfa genişliğinin %30'u kadar sürükleyince
    /// Hızlı fırlatma eşiği; kaydırma hassasiyetiyle birlikte ölçeklenir
    private var flickVelocity: CGFloat { 1000 * CGFloat(settings.scrollSensitivity) / 2.4 }
    private var settings: SettingsStore { .shared }
    /// Bir sayfadaki uygulama sayısı (ayarlardaki sütun × satır)
    var appsPerPage: Int { settings.appsPerPage }
    private let edgeResistance: CGFloat = 0.3      // ilk/son sayfada lastik efekti
    // Kaydırma hassasiyeti ve yerine oturma süresi ayarlardan gelir (SettingsStore)

    private var pageCount: Int { max(1, apps.chunked(into: appsPerPage).count) }

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
        if isPanelOpen { return }
        // Parmak kalktıktan sonra macOS'un gönderdiği "momentum" olaylarını yok say:
        // sayfa zaten parmağın kalktığı anda yerine oturmaya başladı.
        if !event.momentumPhase.isEmpty { return }

        // Trackpad hareketinin bittiği an: hemen yerine oturt (bekleme yok)
        if event.phase == .ended || event.phase == .cancelled {
            if isDragging { endDrag() }
            return
        }

        let rawDX = event.scrollingDeltaX
        let isHorizontal = abs(rawDX) > abs(event.scrollingDeltaY)
        // Fare tekerleği (phase yok) zaten büyük adımlarla gelir, onu büyütme
        let dx = event.phase.isEmpty ? rawDX : rawDX * CGFloat(settings.scrollSensitivity)
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
            relativeVelocity = min(max(Double(velocity / distance), 0), maxSnapVelocity)
        }
        velocity = 0

        withAnimation(.interpolatingSpring(duration: settings.snapDuration, bounce: 0, initialVelocity: relativeVelocity)) {
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
        if let monitor = optionMonitor { NSEvent.removeMonitor(monitor); optionMonitor = nil }
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
            let fd = Darwin.open(dir, O_EVTONLY)
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
        // Sürükleme sırasında liste değişmesin; bırakınca zaten kaydedilecek
        if draggingPath != nil { scheduleReload(); return }
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
        // Yardımcı Programlar ayrı tutulur, ızgarada tek bir "Diğer" klasörü olarak görünür
        let utilities = loaded.filter { $0.path.hasPrefix(Self.utilitiesDirectory) }
        let mainApps = loaded.filter { !$0.path.hasPrefix(Self.utilitiesDirectory) }
        self.utilityApps = utilities.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var defaultOrder = mainApps.sorted { $0.isSystemApp != $1.isSystemApp ? $0.isSystemApp : ($0.isSystemApp ? $0.name < $1.name : $0.creationDate < $1.creationDate) }
        if !utilities.isEmpty {
            let folder = AppItem(name: Self.utilitiesFolderName, path: Self.utilitiesFolderPath,
                                 icon: NSImage(), creationDate: .distantPast, isSystemApp: true, isFolder: true)
            // Varsayılan yeri: sistem uygulamalarının hemen arkası
            let index = defaultOrder.firstIndex(where: { !$0.isSystemApp }) ?? defaultOrder.count
            defaultOrder.insert(folder, at: index)
        }

        // Kullanıcının kaydettiği sıra varsa onu kullan; yeni uygulamalar sona eklenir
        let saved = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        if saved.isEmpty {
            self.apps = defaultOrder
        } else {
            let byPath = Dictionary(defaultOrder.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            let known = Set(saved)
            self.apps = saved.compactMap { byPath[$0] } + defaultOrder.filter { !known.contains($0.path) }
        }
    }

    // MARK: - Klavye: ok tuşlarıyla gezinme, Return ile açma

    /// Klavyeyle seçili uygulama (nil = seçim yok)
    @Published var selectedPath: String?

    /// Sayfa değişince (Cmd+Ok, kaydırma, noktalar) klavye seçimi de yeni sayfada
    /// aynı konuma geçer; o konum boşsa sayfanın son uygulamasına
    private func moveSelectionToCurrentPage() {
        guard let path = selectedPath,
              let index = apps.firstIndex(where: { $0.path == path }),
              index / appsPerPage != currentPage else { return }
        let slot = index % appsPerPage
        let newIndex = min(currentPage * appsPerPage + slot, apps.count - 1)
        selectedPath = apps[newIndex].path
    }

    func isMatch(_ app: AppItem) -> Bool {
        if searchText.isEmpty { return true }
        if app.isFolder { return utilityApps.contains { $0.name.localizedStandardContains(searchText) } }
        return app.name.localizedStandardContains(searchText)
    }

    // MARK: - "Diğer" klasörü

    func openFolder() {
        guard !utilityApps.isEmpty else { return }
        isEditing = false
        withAnimation(.easeOut(duration: 0.2)) { isFolderOpen = true }
    }

    func closeFolder() {
        withAnimation(.easeOut(duration: 0.2)) { isFolderOpen = false }
    }

    // MARK: - Ayarlar paneli

    func openSettings() {
        isEditing = false
        isFolderOpen = false
        withAnimation(.easeOut(duration: 0.2)) { isSettingsOpen = true }
    }

    func closeSettings() {
        withAnimation(.easeOut(duration: 0.2)) { isSettingsOpen = false }
    }

    /// Kaydedilmiş simge sırasını siler, varsayılan sıraya döner
    func resetOrder() {
        UserDefaults.standard.removeObject(forKey: Self.orderKey)
        loadApps()
    }

    /// Launchpad gizlenince klasör ve titreme modu kapansın (eski Launchpad'deki gibi)
    private var hideObserver: NSObjectProtocol?
    func setupHideObserver() {
        guard hideObserver == nil else { return }
        hideObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isFolderOpen = false
                self?.isSettingsOpen = false
                self?.isEditing = false
            }
        }
    }

    /// dx: sağ/sol (±1), dy: aşağı/yukarı (±1)
    func moveSelection(dx: Int, dy: Int) {
        guard !apps.isEmpty, !isEditing, !isPanelOpen else { return }
        let perPage = appsPerPage
        let columns = settings.columns

        // İlk basışta bulunduğun sayfanın ilk uygulamasını seç
        guard let path = selectedPath,
              let index = apps.firstIndex(where: { $0.path == path }) else {
            selectedPath = apps[min(currentPage * perPage, apps.count - 1)].path
            return
        }

        var newIndex = index + dx
        if dy != 0 {
            let row = (index % perPage) / columns
            let newRow = row + dy
            // Sayfanın içinde kal; sayfa değiştirmek için sağ/sol ya da Cmd+Ok
            if newRow >= 0, newRow < perPage / columns { newIndex = index + dy * columns }
        }
        newIndex = min(max(newIndex, 0), apps.count - 1)
        selectedPath = apps[newIndex].path

        // Seçim başka sayfaya geçtiyse o sayfayı göster
        let page = newIndex / perPage
        if page != currentPage { goToPage(page) }
    }

    /// Return: seçili uygulamayı aç; arama yapılıyorsa seçili eşleşmiyorsa ilk eşleşeni aç
    func openSelected() {
        guard !isEditing, !isPanelOpen else { return }
        let selected = apps.first(where: { $0.path == selectedPath })
        if let selected, isMatch(selected) {
            open(selected)
        } else if !searchText.isEmpty {
            // Aramada ilk eşleşen gerçek uygulama (klasörün içindekiler dahil)
            let candidates = apps.filter { !$0.isFolder } + utilityApps
            if let first = candidates.first(where: { $0.name.localizedStandardContains(searchText) }) {
                open(first)
            }
        }
    }

    func open(_ app: AppItem) {
        if app.isFolder { openFolder(); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        LaunchpadPresenter.shared.hide()
    }

    // MARK: - Option tuşu: basılı tutarken titreme modu

    private var optionMonitor: Any?
    private var optionStartedEditing = false

    func setupOptionKeyMonitor() {
        guard optionMonitor == nil else { return }
        optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifiers(event.modifierFlags)
            return event
        }
    }

    private func handleModifiers(_ flags: NSEvent.ModifierFlags) {
        let optionDown = flags.contains(.option)
        if optionDown, !isEditing, searchText.isEmpty {
            optionStartedEditing = true
            isEditing = true
        } else if !optionDown, optionStartedEditing {
            // Option ile başladıysa bırakınca biter; o sırada sürükleme varsa titreme sürer
            optionStartedEditing = false
            if draggingPath == nil { isEditing = false }
        }
    }

    // MARK: - Sürükleyerek yer değiştirme

    private static let orderKey = "AppOrder"

    /// Şu an sürüklenen uygulamanın yolu (nil = sürükleme yok)
    @Published var draggingPath: String?
    let dragOverlay = DragOverlayState()
    /// Her simgenin ekrandaki yeri (yayınlanmaz, sadece hedef bulmak için)
    var iconFrames: [String: CGRect] = [:]

    private var grabOffset: CGSize = .zero
    private var edgeWorkItem: DispatchWorkItem?
    private var edgeDirection = 0
    private let edgeZone: CGFloat = 60              // ekran kenarına bu kadar yaklaşınca
    private let edgeDelay: TimeInterval = 0.6       // bu kadar bekleyince sayfa değişir
    private let reorderAnimation = Animation.spring(duration: 0.3, bounce: 0)

    func dragChanged(_ app: AppItem, start: CGPoint, location: CGPoint) {
        guard searchText.isEmpty, !isPanelOpen else { return }
        if draggingPath == nil {
            guard let frame = iconFrames[app.path] else { return }
            isEditing = true
            grabOffset = CGSize(width: start.x - frame.midX, height: start.y - frame.midY)
            dragOverlay.position = CGPoint(x: frame.midX, y: frame.midY)
            draggingPath = app.path
        }
        dragOverlay.position = CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height)
        reorderIfNeeded(at: location)
        handleEdge(at: location)
    }

    func dragEnded() {
        edgeWorkItem?.cancel()
        edgeDirection = 0
        guard let path = draggingPath else { return }
        saveOrder()

        // Simge bırakıldığı yerden yuvasına süzülsün, sonra gerçek simge görünsün
        if let frame = iconFrames[path] {
            withAnimation(reorderAnimation) {
                dragOverlay.position = CGPoint(x: frame.midX, y: frame.midY)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.draggingPath == path else { return }
                self.draggingPath = nil
            }
        } else {
            draggingPath = nil
        }
    }

    private func reorderIfNeeded(at location: CGPoint) {
        guard let dragging = draggingPath,
              let from = apps.firstIndex(where: { $0.path == dragging }) else { return }

        // İmlecin altındaki simge (kenar paylarında değiştirme, titreşmesin)
        guard let targetPath = iconFrames.first(where: { entry in
                  entry.key != dragging &&
                  entry.value.insetBy(dx: entry.value.width * 0.2, dy: entry.value.height * 0.2).contains(location)
              })?.key,
              let to = apps.firstIndex(where: { $0.path == targetPath }),
              to / appsPerPage == currentPage else { return }

        withAnimation(reorderAnimation) {
            let item = apps.remove(at: from)
            apps.insert(item, at: to)
        }
    }

    private func handleEdge(at location: CGPoint) {
        let direction = location.x < edgeZone ? -1 : (location.x > pageWidth - edgeZone ? 1 : 0)
        guard direction != edgeDirection else { return }
        edgeDirection = direction
        edgeWorkItem?.cancel()
        if direction != 0 { scheduleEdgeTurn() }
    }

    private func scheduleEdgeTurn() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.draggingPath != nil, self.edgeDirection != 0 else { return }
            let direction = self.edgeDirection
            let before = self.currentPage
            self.turnPage(direction: direction)
            if self.currentPage != before {
                // Simgeyi yeni sayfaya taşı: ileri giderken başına, geri giderken sonuna
                self.moveDragged(toPage: self.currentPage, atStart: direction > 0)
            }
            // Kenarda beklemeye devam ederse bir sonraki sayfaya da geç
            self.scheduleEdgeTurn()
        }
        edgeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + edgeDelay, execute: item)
    }

    private func moveDragged(toPage page: Int, atStart: Bool) {
        guard let dragging = draggingPath,
              let from = apps.firstIndex(where: { $0.path == dragging }),
              from / appsPerPage != page else { return }
        var items = apps
        let item = items.remove(at: from)
        let wanted = atStart ? page * appsPerPage : page * appsPerPage + appsPerPage - 1
        items.insert(item, at: min(max(wanted, 0), items.count))
        withAnimation(reorderAnimation) { apps = items }
    }

    private func saveOrder() {
        UserDefaults.standard.set(apps.map(\.path), forKey: Self.orderKey)
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

//
//  ContentView.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = LaunchpadViewModel()
    @ObservedObject private var settings = SettingsStore.shared
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea()
            
            Rectangle().fill(Color.white.opacity(0.01)).contentShape(Rectangle()).ignoresSafeArea().onTapGesture {
                if vm.isEditing { vm.isEditing = false }
                else if !vm.searchText.isEmpty { vm.searchText = "" }
                else { LaunchpadPresenter.shared.hide() }
            }

            // Sağ altta ayarlar düğmesi
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { vm.openSettings() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Ayarlar (Cmd+,)")
                }
            }
            .padding(32)
            
            GeometryReader { geo in
                let pages = vm.apps.chunked(into: settings.appsPerPage)
                let safePage = min(max(0, vm.currentPage), max(0, pages.count - 1))
                let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: settings.columns)
                // Satır aralığı ekran yüksekliğine göre: satır sayısı ya da simge boyutu artınca ekrana sığsın
                let cellHeight = settings.iconSize + 12 + 36
                let available = geo.size.height - 180
                let rowCount = CGFloat(settings.rows)
                let rowSpacing = max(12, min(60, (available - rowCount * cellHeight) / max(rowCount - 1, 1)))
                
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageApps in
                        LazyVGrid(columns: columns, spacing: rowSpacing) {
                            ForEach(pageApps) { app in
                                let match = vm.isMatch(app)
                                AppIconView(app: app, match: match, vm: vm, iconSize: settings.iconSize)
                            }
                        }
                        .padding(.top, 90).padding(.horizontal, 80).frame(width: geo.size.width, height: geo.size.height, alignment: .top).id(idx)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .offset(x: -CGFloat(safePage) * geo.size.width + vm.dragOffset)
                .onAppear { vm.pageWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, newWidth in vm.pageWidth = newWidth }
            }
            
            VStack {
                HStack { Image(systemName: "magnifyingglass"); TextField("Ara", text: $vm.searchText).textFieldStyle(.plain) }.padding(10).background(Color.black.opacity(0.2)).cornerRadius(12).frame(width: 320).padding(.top, 40)
                Spacer()
                let pageCount = max(1, vm.apps.chunked(into: settings.appsPerPage).count)
                HStack { ForEach(0..<pageCount, id: \.self) { i in Circle().fill(vm.currentPage == i ? .white : .white.opacity(0.3)).frame(width: 8, height: 8).onTapGesture { vm.goToPage(i) } } }.padding(.bottom, 40)
            }
            
            Group {
                Button(action: {
                    if vm.isEditing { vm.isEditing = false }
                    else if vm.isSettingsOpen { vm.closeSettings() }
                    else if vm.isFolderOpen { vm.closeFolder() }
                    else if !vm.searchText.isEmpty { vm.searchText = "" }
                    else { LaunchpadPresenter.shared.hide() }
                }) { EmptyView() }.keyboardShortcut(.escape, modifiers: [])
                
                // Ok tuşları: uygulamalar arasında gezin
                Button(action: { vm.moveSelection(dx: 1, dy: 0) }) { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button(action: { vm.moveSelection(dx: -1, dy: 0) }) { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(action: { vm.moveSelection(dx: 0, dy: 1) }) { EmptyView() }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button(action: { vm.moveSelection(dx: 0, dy: -1) }) { EmptyView() }
                    .keyboardShortcut(.upArrow, modifiers: [])

                // Return: seçili (ya da aramada ilk eşleşen) uygulamayı aç
                Button(action: { vm.openSelected() }) { EmptyView() }
                    .keyboardShortcut(.return, modifiers: [])

                // Cmd+Sol/Sağ Ok: sayfa değiştir
                Button(action: { vm.turnPage(direction: 1) }) { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(action: { vm.turnPage(direction: -1) }) { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)

                // Cmd+,: ayarlar
                Button(action: { vm.openSettings() }) { EmptyView() }
                    .keyboardShortcut(",", modifiers: .command)

                // Cmd+Q: uygulamayı tamamen kapat (güncelleme yaparken lazım)
                Button(action: { NSApp.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("q", modifiers: .command)
            }.opacity(0)
        }
        .overlay {
            if vm.isFolderOpen {
                FolderPanelView(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            if vm.isSettingsOpen {
                SettingsPanelView(vm: vm)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .overlay { DraggedIconOverlay(vm: vm, overlay: vm.dragOverlay) }
        .coordinateSpace(.named("launchpad"))
        .onAppear {
            vm.loadApps()
            vm.setupMonitor()
            vm.startWatchingAppFolders()
            vm.setupOptionKeyMonitor()
            vm.setupHideObserver()
        }
        .onDisappear { vm.cleanup() }
        // Sütun/satır değişince sayfa sayısı değişir; bulunduğun sayfa geçerli kalsın
        .onChange(of: settings.appsPerPage) { _, _ in vm.goToPage(vm.currentPage) }
    }
}

/// Sürüklenen simgenin imleci takip eden kopyası
struct DraggedIconOverlay: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var overlay: DragOverlayState

    var body: some View {
        if let path = vm.draggingPath, let app = vm.apps.first(where: { $0.path == path }) {
            let size = SettingsStore.shared.iconSize
            VStack(spacing: 12) {
                Group {
                    if app.isFolder {
                        FolderIconView(apps: Array(vm.utilityApps.prefix(9)), size: size)
                    } else {
                        Image(nsImage: app.icon).resizable().scaledToFit()
                    }
                }
                .frame(width: size, height: size)
                Text(app.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: size + 20)
            .scaleEffect(1.1)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .position(overlay.position)
            .allowsHitTesting(false)
        }
    }
}

/// "Diğer" klasörü açılınca ortada beliren panel
struct FolderPanelView: View {
    @ObservedObject var vm: LaunchpadViewModel
    private let columns = Array(repeating: GridItem(.fixed(110), spacing: 20), count: 6)

    var body: some View {
        ZStack {
            // Panelin dışına tıklayınca kapanır
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { vm.closeFolder() }

            VStack(spacing: 24) {
                Text(LaunchpadViewModel.utilitiesFolderName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(vm.utilityApps) { app in
                            VStack(spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                Text(app.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 110)
                            .opacity(vm.searchText.isEmpty || app.name.localizedStandardContains(vm.searchText) ? 1 : 0.25)
                            .contentShape(Rectangle())
                            .onTapGesture { vm.open(app) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 520)
            }
            .padding(36)
            .frame(width: 820)
            .background(RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial))
        }
    }
}

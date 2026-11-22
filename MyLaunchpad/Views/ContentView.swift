//
//  ContentView.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = LaunchpadViewModel()
    // static: görünümün içinde saklanan bir değer olmasın ki dışarıdaki
    // animasyon (ölçek) değişirken SwiftUI bu ekranı "değişti" sanıp baştan çizmesin
    static let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 7)
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea()
            
            Rectangle().fill(Color.white.opacity(0.01)).contentShape(Rectangle()).ignoresSafeArea().onTapGesture {
                if vm.isEditing { vm.isEditing = false }
                else if !vm.searchText.isEmpty { vm.searchText = "" }
                else { LaunchpadPresenter.shared.hide() }
            }
            
            GeometryReader { geo in
                let pages = vm.apps.chunked(into: 35)
                let safePage = min(max(0, vm.currentPage), max(0, pages.count - 1))
                
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageApps in
                        LazyVGrid(columns: Self.columns, spacing: 40) {
                            ForEach(pageApps) { app in
                                let match = vm.searchText.isEmpty || app.name.localizedStandardContains(vm.searchText)
                                AppIconView(app: app, match: match, vm: vm)
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
                let pageCount = max(1, vm.apps.chunked(into: 35).count)
                HStack { ForEach(0..<pageCount, id: \.self) { i in Circle().fill(vm.currentPage == i ? .white : .white.opacity(0.3)).frame(width: 8, height: 8).onTapGesture { vm.goToPage(i) } } }.padding(.bottom, 40)
            }
            
            Group {
                Button(action: {
                    if vm.isEditing { vm.isEditing = false }
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

                // Cmd+Q: uygulamayı tamamen kapat (güncelleme yaparken lazım)
                Button(action: { NSApp.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("q", modifiers: .command)
            }.opacity(0)
        }
        .overlay { DraggedIconOverlay(vm: vm, overlay: vm.dragOverlay) }
        .coordinateSpace(.named("launchpad"))
        .onAppear {
            vm.loadApps()
            vm.setupMonitor()
            vm.startWatchingAppFolders()
            vm.setupOptionKeyMonitor()
        }
        .onDisappear { vm.cleanup() }
    }
}

/// Sürüklenen simgenin imleci takip eden kopyası
struct DraggedIconOverlay: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var overlay: DragOverlayState

    var body: some View {
        if let path = vm.draggingPath, let app = vm.apps.first(where: { $0.path == path }) {
            VStack(spacing: 12) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                Text(app.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 100)
            .scaleEffect(1.1)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .position(overlay.position)
            .allowsHitTesting(false)
        }
    }
}

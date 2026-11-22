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
                
                Button(action: { vm.turnPage(direction: 1) }) { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                Button(action: { vm.turnPage(direction: -1) }) { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                // Cmd+Q: uygulamayı tamamen kapat (güncelleme yaparken lazım)
                Button(action: { NSApp.terminate(nil) }) { EmptyView() }
                    .keyboardShortcut("q", modifiers: .command)
            }.opacity(0)
        }
        .onAppear {
            vm.loadApps()
            vm.setupMonitor()
            vm.startWatchingAppFolders()
        }
        .onDisappear { vm.cleanup() }
    }
}

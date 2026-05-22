//
//  ContentView.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = LaunchpadViewModel()
    let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 7)
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea()
            
            Rectangle().fill(Color.white.opacity(0.01)).contentShape(Rectangle()).ignoresSafeArea().onTapGesture {
                if vm.isEditing { vm.isEditing = false }
                else if !vm.searchText.isEmpty { vm.searchText = "" }
                else { NSApp.hide(nil) }
            }
            
            GeometryReader { geo in
                let pages = vm.apps.chunked(into: 35)
                let safePage = min(max(0, vm.currentPage), max(0, pages.count - 1))
                
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { idx, pageApps in
                        LazyVGrid(columns: columns, spacing: 40) {
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
                .animation(.easeInOut(duration: 0.3), value: safePage)
            }
            
            VStack {
                HStack { Image(systemName: "magnifyingglass"); TextField("Ara", text: $vm.searchText).textFieldStyle(.plain) }.padding(10).background(Color.black.opacity(0.2)).cornerRadius(12).frame(width: 320).padding(.top, 40)
                Spacer()
                let pageCount = max(1, vm.apps.chunked(into: 35).count)
                HStack { ForEach(0..<pageCount, id: \.self) { i in Circle().fill(vm.currentPage == i ? .white : .white.opacity(0.3)).frame(width: 8, height: 8).onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { vm.currentPage = i } } } }.padding(.bottom, 40)
            }
            
            Group {
                Button(action: {
                    if vm.isEditing { vm.isEditing = false }
                    else if !vm.searchText.isEmpty { vm.searchText = "" }
                    else { NSApp.hide(nil) }
                }) { EmptyView() }.keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    let pageCount = vm.apps.chunked(into: 35).count
                    if vm.currentPage < pageCount - 1 { vm.currentPage += 1 }
                }) { EmptyView() }.keyboardShortcut(.rightArrow, modifiers: [])
                
                Button(action: {
                    if vm.currentPage > 0 { vm.currentPage -= 1 }
                }) { EmptyView() }.keyboardShortcut(.leftArrow, modifiers: [])
            }.opacity(0)
        }
        .onAppear {
            setupFullScreenWindow()
            vm.loadApps()
            vm.setupMonitor()
        }
        .onDisappear { vm.cleanup() }
    }
    
    func setupFullScreenWindow() {
        NSApp.setActivationPolicy(.accessory)
        if let window = NSApplication.shared.windows.first {
            window.styleMask = [.borderless]
            window.level = .mainMenu + 1
            if let screen = NSScreen.main { window.setFrame(screen.frame, display: true) }
            window.backgroundColor = .clear
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

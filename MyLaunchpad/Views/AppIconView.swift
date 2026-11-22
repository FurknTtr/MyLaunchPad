//
//  AppIconView.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppItem
    let match: Bool
    @ObservedObject var vm: LaunchpadViewModel
    var iconSize: Double = SettingsStore.Default.iconSize
    @State private var isHoveringX = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 12) {
                iconContent
                    .frame(width: iconSize, height: iconSize)
                    // Klavyeyle seçiliyse simgenin arkasında hafif bir vurgu (yerleşimi değiştirmez)
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(vm.selectedPath == app.path ? 0.25 : 0))
                            .padding(-8)
                    }
                    .rotationEffect(.degrees(vm.isEditing && match ? 2.5 : 0))
                    .animation(vm.isEditing && match ? .linear(duration: 0.12).repeatForever(autoreverses: true) : .default, value: vm.isEditing)
                
                Text(app.name)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: iconSize + 20)
            .opacity(match ? 1 : 0.2)
            .grayscale(match ? 0 : 1)
            .contentShape(Rectangle())
            // Sürükleyerek yer değiştirme (tıklayıp sürükleyince titreme modu da açılır)
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("launchpad"))
                    .onChanged { value in
                        if match { vm.dragChanged(app, start: value.startLocation, location: value.location) }
                    }
                    .onEnded { _ in vm.dragEnded() }
            )
            
            .onLongPressGesture(minimumDuration: 0.5) {
                if match {
                    let haptic = NSHapticFeedbackManager.defaultPerformer
                    haptic.perform(.generic, performanceTime: .now)
                    vm.isEditing = true
                }
            }
            .onTapGesture {
                if !vm.isEditing && match {
                    vm.open(app) // klasörse paneli açar
                }
            }
            
            if vm.isEditing && !app.isSystemApp && match {
                Button(action: { vm.confirmDelete(app) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isHoveringX ? .red : .white.opacity(0.85))
                        .background(Color.black.clipShape(Circle()))
                }
                .buttonStyle(.plain)
                .offset(x: -2, y: -6)
                .onHover { hovering in
                    isHoveringX = hovering
                    if hovering { NSCursor.pointingHand.push() }
                    else { NSCursor.pop() }
                }
            }
        }
        .opacity(vm.draggingPath == app.path ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("launchpad"))
        } action: { frame in
            vm.iconFrames[app.path] = frame
        }
    }

    @ViewBuilder private var iconContent: some View {
        if app.isFolder {
            FolderIconView(apps: Array(vm.utilityApps.prefix(9)), size: iconSize)
        } else {
            Image(nsImage: app.icon)
                .resizable()
                .scaledToFit()
        }
    }
}

/// Klasör simgesi: içindeki ilk 9 uygulamanın mini ızgarası
struct FolderIconView: View {
    let apps: [AppItem]
    var size: Double = 80

    var body: some View {
        // Simge boyutuna göre ölçeklenen 3×3 mini ızgara
        let mini = size * 0.225
        let gap = size * 0.05
        RoundedRectangle(cornerRadius: size * 0.225)
            .fill(Color.white.opacity(0.2))
            .overlay {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: gap), count: 3), spacing: gap) {
                    ForEach(apps) { app in
                        Image(nsImage: app.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: mini, height: mini)
                    }
                }
            }
    }
}


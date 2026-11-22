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
    @State private var isHoveringX = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 12) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
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
            .frame(width: 100)
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
                    vm.open(app)
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
}

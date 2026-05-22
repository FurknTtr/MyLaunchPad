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
    
    private var scrollMonitor: Any?
    private var snapWorkItem: DispatchWorkItem?
    
    init() {
        self.currentPage = UserDefaults.standard.integer(forKey: "LastLaunchpadPage")
    }
    
    func setupMonitor() {
        if scrollMonitor != nil { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            if !event.momentumPhase.isEmpty {
                if self.dragOffset != 0 { DispatchQueue.main.async { self.snapPage() } }
                return event
            }
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                self.snapWorkItem?.cancel()
                DispatchQueue.main.async {
                    let pageCount = max(1, self.apps.chunked(into: 35).count)
                    let isAtLeftEdge = self.currentPage == 0 && event.scrollingDeltaX > 0
                    let isAtRightEdge = self.currentPage == pageCount - 1 && event.scrollingDeltaX < 0
                    if isAtLeftEdge || isAtRightEdge { self.dragOffset += event.scrollingDeltaX * 0.3 }
                    else { self.dragOffset += event.scrollingDeltaX }
                }
                let workItem = DispatchWorkItem { [weak self] in self?.snapPage() }
                self.snapWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            }
            return event
        }
    }
    
    func snapPage() {
        let threshold: CGFloat = 80
        if self.dragOffset < -threshold { turnPage(direction: 1) }
        else if self.dragOffset > threshold { turnPage(direction: -1) }
        else {
            withAnimation(.easeInOut(duration: 0.25)) { self.dragOffset = 0 }
        }
    }
    
    func turnPage(direction: Int) {
        let pageCount = max(1, self.apps.chunked(into: 35).count)
        currentPage = max(0, min(currentPage + direction, pageCount - 1))
        withAnimation(.easeInOut(duration: 0.25)) { self.dragOffset = 0 }
    }
    
    func cleanup() { if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor); scrollMonitor = nil } }
    
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
    
    func deleteApp(_ app: AppItem) {
        NSWorkspace.shared.recycle([URL(fileURLWithPath: app.path)]) { _, _ in
            DispatchQueue.main.async { self.apps.removeAll { $0.id == app.id } }
        }
    }
}

//
//  AppItem.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//


import Foundation
import AppKit

struct AppItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: NSImage
    let creationDate: Date
    let isSystemApp: Bool
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

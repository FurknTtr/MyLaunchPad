//
//  VisualEffectView.swift
//  MyLaunchpad
//
//  Created by Furkan Tatar on 23.05.2026.
//

import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

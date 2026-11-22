//
//  LaunchpadPresenter.swift
//  MyLaunchpad
//
//  Launchpad penceresinin açılıp kapanmasını yönetir. Pinch sırasında
//  pencere parmakla birlikte belirir/kaybolur; bırakınca yumuşakça tamamlanır.
//

import SwiftUI
import AppKit
import Combine

final class LaunchpadPresenter: ObservableObject {
    static let shared = LaunchpadPresenter()

    /// 0 = gizli, 1 = tamamen açık. Pencere saydamlığı ve simge ölçeği buna bağlı.
    @Published private(set) var progress: CGFloat = 0

    weak var window: NSWindow?

    /// Kapalıyken simgeler bu kadar büyük başlar (eski Launchpad'deki yaklaşma efekti)
    static let hiddenScaleBoost: CGFloat = 0.08

    // Parmak hareketinin ne kadarı tam açma/kapama sayılır
    private let openDistance: Float = 0.35    // açıklık %35 azalınca tamamen açık
    private let closeDistance: Float = 0.5    // açıklık %50 artınca tamamen kapalı
    // Bırakınca tamamlama kararı
    private let commitProgress: CGFloat = 0.4 // en az bu kadar ilerlediyse tamamla
    private let flickVelocity: Float = 1.0    // ya da bu hızda hızlı bir hareketse
    private var animationDuration: TimeInterval { SettingsStore.shared.openCloseDuration }

    private var isShown = false
    private var gestureActive = false
    private var gestureOpensLaunchpad = true
    private var animationGeneration = 0

    private init() {}

    /// Pencere gerçekten ekranda ve açık durumda mı?
    private var isActuallyShown: Bool {
        guard let window else { return false }
        return isShown && !NSApp.isHidden && window.isVisible
    }

    // MARK: - Pinch ile (parmağa bağlı)

    func pinchChanged(ratio: Float) {
        if !gestureActive {
            gestureActive = true
            gestureOpensLaunchpad = !isActuallyShown
        }

        let p: CGFloat
        if gestureOpensLaunchpad {
            // Kıstırdıkça açılır; açmaya çalışmak bir şey yapmaz
            p = CGFloat(min(max((1 - ratio) / openDistance, 0), 1))
        } else {
            // Açtıkça kapanır; kıstırmak bir şey yapmaz
            p = 1 - CGFloat(min(max((ratio - 1) / closeDistance, 0), 1))
        }
        setInteractive(progress: p)
    }

    func pinchEnded(ratio: Float, velocity: Float) {
        guard gestureActive else { return }
        gestureActive = false

        if gestureOpensLaunchpad {
            let open = progress > commitProgress || velocity < -flickVelocity
            open ? show() : hide()
        } else {
            let close = progress < 1 - commitProgress || velocity > flickVelocity
            close ? hide() : show()
        }
    }

    // MARK: - Doğrudan aç / kapat (Dock, Esc, boş alana tıklama, uygulama açma)

    func show(animated: Bool = true) {
        guard let window else { return }
        if NSApp.isHidden || !window.isVisible {
            prepareForShowing(window)
        }
        isShown = true
        window.makeKeyAndOrderFront(nil)
        // Arka plandaki (accessory) bir uygulamanın öne gelmesi için zorla etkinleştir
        NSApp.activate(ignoringOtherApps: true)
        animate(to: 1, animated: animated, hideWhenDone: false)
    }

    func hide(animated: Bool = true) {
        guard let window else { return }
        isShown = false
        guard !NSApp.isHidden, window.isVisible else {
            progress = 0
            return
        }
        animate(to: 0, animated: animated, hideWhenDone: true)
    }

    // MARK: - Yardımcılar

    private func prepareForShowing(_ window: NSWindow) {
        if let screen = NSScreen.main, window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        setAlpha(0, on: window)
        progress = 0
        NSApp.unhide(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Parmağı takip ederken: süren animasyonu iptal edip değeri anında uygula
    private func setInteractive(progress p: CGFloat) {
        guard let window else { return }
        animationGeneration += 1
        if p > 0, NSApp.isHidden || !window.isVisible {
            prepareForShowing(window)
        }
        setAlpha(p, on: window)
        progress = p
    }

    private func animate(to target: CGFloat, animated: Bool, hideWhenDone: Bool) {
        guard let window else { return }
        animationGeneration += 1
        let generation = animationGeneration

        guard animated else {
            setAlpha(target, on: window)
            progress = target
            if hideWhenDone { NSApp.hide(nil) }
            return
        }

        // Pencere saydamlığı (AppKit) ve simge ölçeği (SwiftUI) aynı eğri ve sürede
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = target
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Bu arada yeni bir hareket başladıysa gizleme
                guard let self, generation == self.animationGeneration else { return }
                if hideWhenDone { NSApp.hide(nil) }
            }
        })
        withAnimation(.easeOut(duration: animationDuration)) {
            progress = target
        }
    }

    /// Süren bir saydamlık animasyonunu da durdurarak anında ayarlar
    private func setAlpha(_ value: CGFloat, on window: NSWindow) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        window.animator().alphaValue = value
        NSAnimationContext.endGrouping()
    }
}

/// Ekranın tamamını saran kök görünüm: animasyon sırasında sadece ölçeği değiştirir.
/// ContentView'un dışarıdan aldığı bir değer olmadığı için SwiftUI onu baştan çizmez.
struct LaunchpadRoot: View {
    @ObservedObject var presenter: LaunchpadPresenter

    var body: some View {
        ContentView()
            .scaleEffect(1 + (1 - presenter.progress) * LaunchpadPresenter.hiddenScaleBoost)
    }
}

//
//  GestureMonitor.swift
//  MyLaunchpad
//
//  Trackpad'deki ham dokunuşları Apple'ın gizli MultitouchSupport
//  framework'ü üzerinden okur ve 4/5 parmak pinch hareketini algılar.
//  Not: Gizli API kullandığı için App Sandbox kapalı olmalı ve
//  uygulama App Store'a gönderilemez (kişisel kullanım için sorun yok).
//

import Foundation
import AppKit

nonisolated final class GestureMonitor: @unchecked Sendable {
    static let shared = GestureMonitor()

    /// Parmaklar birbirine yaklaşınca (Launchpad'i açma hareketi)
    var onPinchIn: (@MainActor @Sendable () -> Void)?
    /// Parmaklar açılınca (Launchpad'i kapatma hareketi)
    var onPinchOut: (@MainActor @Sendable () -> Void)?

    // MARK: - MultitouchSupport fonksiyon imzaları

    private typealias MTDeviceRef = UnsafeMutableRawPointer
    private typealias ContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    private typealias StartFn = @convention(c) (MTDeviceRef, Int32) -> Void
    private typealias StopFn = @convention(c) (MTDeviceRef) -> Void

    private var createList: CreateListFn?
    private var registerCallback: RegisterFn?
    private var unregisterCallback: RegisterFn?
    private var startDevice: StartFn?
    private var stopDevice: StopFn?

    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []

    // Dokunuş verisinin yapısı (tersine mühendislikle bilinen düzen):
    // her dokunuş 96 bayt, normalize x/y koordinatları 32. ve 36. baytta.
    private static let touchStride = 96
    private static let xOffset = 32
    private static let yOffset = 36

    // Hareket eşikleri
    private static let minFingers = 4
    private static let pinchInRatio: Float = 0.65   // parmaklar başlangıca göre %35 yaklaşınca
    private static let pinchOutRatio: Float = 1.4   // parmaklar başlangıca göre %40 açılınca
    private static let minStartSpread: Float = 0.02

    // Hareket durumu (yalnızca MultitouchSupport'un callback thread'inden kullanılır)
    private var tracking = false
    private var fired = false
    private var startSpread: Float = 0
    private var startCount = 0

    private static let callback: ContactCallback = { _, touches, count, _, _ in
        GestureMonitor.shared.handle(touches: touches, count: Int(count))
        return 0
    }

    private init() {}

    // MARK: - Başlat / durdur

    func start() {
        guard loadFramework(), devices.isEmpty,
              let list = createList?()?.takeRetainedValue() else { return }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            registerCallback?(device, GestureMonitor.callback)
            startDevice?(device, 0)
            devices.append(device)
        }
    }

    func stop() {
        for device in devices {
            unregisterCallback?(device, GestureMonitor.callback)
            stopDevice?(device)
        }
        devices.removeAll()
        deviceList = nil
        tracking = false
        fired = false
    }

    /// Uyku sonrası trackpad bağlantısı kopabildiği için yeniden başlatılır.
    func restart() {
        stop()
        start()
    }

    private func loadFramework() -> Bool {
        if createList != nil { return true }
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let createSym = dlsym(handle, "MTDeviceCreateList"),
              let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregisterSym = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart"),
              let stopSym = dlsym(handle, "MTDeviceStop") else {
            NSLog("MyLaunchpad: MultitouchSupport yüklenemedi")
            return false
        }
        createList = unsafeBitCast(createSym, to: CreateListFn.self)
        registerCallback = unsafeBitCast(registerSym, to: RegisterFn.self)
        unregisterCallback = unsafeBitCast(unregisterSym, to: RegisterFn.self)
        startDevice = unsafeBitCast(startSym, to: StartFn.self)
        stopDevice = unsafeBitCast(stopSym, to: StopFn.self)
        return true
    }

    // MARK: - Pinch algılama

    private func handle(touches: UnsafeMutableRawPointer?, count: Int) {
        guard let touches, count >= GestureMonitor.minFingers else {
            // Parmaklar kalkınca bir sonraki harekete hazırlan
            tracking = false
            fired = false
            return
        }

        // Parmakların ortalama merkezden uzaklığı = "açıklık"
        var xs = [Float](repeating: 0, count: count)
        var ys = [Float](repeating: 0, count: count)
        var cx: Float = 0, cy: Float = 0
        for i in 0..<count {
            let base = touches + i * GestureMonitor.touchStride
            xs[i] = base.loadUnaligned(fromByteOffset: GestureMonitor.xOffset, as: Float.self)
            ys[i] = base.loadUnaligned(fromByteOffset: GestureMonitor.yOffset, as: Float.self)
            cx += xs[i]
            cy += ys[i]
        }
        cx /= Float(count)
        cy /= Float(count)

        var spread: Float = 0
        for i in 0..<count {
            let dx = xs[i] - cx
            let dy = ys[i] - cy
            spread += (dx * dx + dy * dy).squareRoot()
        }
        spread /= Float(count)

        // Yeni hareket ya da parmak sayısı değişti: başlangıç noktasını kaydet
        if !tracking || count != startCount {
            tracking = true
            startCount = count
            startSpread = spread
            return
        }

        guard !fired, startSpread > GestureMonitor.minStartSpread else { return }

        let ratio = spread / startSpread
        if ratio < GestureMonitor.pinchInRatio {
            fired = true
            fire(onPinchIn)
        } else if ratio > GestureMonitor.pinchOutRatio {
            fired = true
            fire(onPinchOut)
        }
    }

    private func fire(_ handler: (@MainActor @Sendable () -> Void)?) {
        guard let handler else { return }
        Task { @MainActor in handler() }
    }
}

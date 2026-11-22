//
//  GestureMonitor.swift
//  MyLaunchpad
//
//  Trackpad'deki ham dokunuşları Apple'ın gizli MultitouchSupport
//  framework'ü üzerinden okur ve 4/5 parmak pinch hareketini
//  parmakla birlikte, anlık ilerleme olarak bildirir.
//  Not: Gizli API kullandığı için App Sandbox kapalı olmalı ve
//  uygulama App Store'a gönderilemez (kişisel kullanım için sorun yok).
//

import Foundation
import AppKit

nonisolated final class GestureMonitor: @unchecked Sendable {
    static let shared = GestureMonitor()

    /// Hareket sürerken her karede: parmak açıklığının başlangıca oranı
    /// (1 = başlangıç, <1 = kıstırılıyor, >1 = açılıyor)
    var onPinchChanged: (@MainActor @Sendable (_ ratio: Float) -> Void)?
    /// Parmaklar kalkınca: son oran ve oranın değişim hızı (saniyede)
    var onPinchEnded: (@MainActor @Sendable (_ ratio: Float, _ velocity: Float) -> Void)?

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

    // Hareket ayarları
    private static let minFingers = 4
    private static let minStartSpread: Float = 0.02
    /// Bu kadar değişmeden (±%6) ekranda hiçbir şey olmaz; titreme ve yanlış tetiklemeyi önler
    private static let deadZone: Float = 0.06
    /// Parmakların merkezi bu kadar kayıp açıklık az değiştiyse bu bir kaydırmadır (masaüstü geçişi vb.)
    private static let swipeShift: Float = 0.1

    // Hareket durumu (yalnızca MultitouchSupport'un callback thread'inden kullanılır)
    private var tracking = false
    private var active = false
    private var swipeLocked = false
    private var startSpread: Float = 0
    private var startCount = 0
    private var startCenter = (x: Float(0), y: Float(0))
    private var lastRatio: Float = 1
    private var lastTime: Double = 0
    private var ratioVelocity: Float = 0

    // Ana thread'e giden güncellemeleri birleştirmek için (kare başına en fazla bir iş)
    private let lock = NSLock()
    private var pendingRatio: Float?

    private static let callback: ContactCallback = { _, touches, count, timestamp, _ in
        GestureMonitor.shared.handle(touches: touches, count: Int(count), timestamp: timestamp)
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
        active = false
        swipeLocked = false
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

    // MARK: - Pinch takibi

    private func handle(touches: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        guard let touches, count >= GestureMonitor.minFingers else {
            // Parmaklar kalktı: hareket sürüyorsa bitişini bildir
            if active { publishEnd(ratio: lastRatio, velocity: ratioVelocity) }
            tracking = false
            active = false
            swipeLocked = false
            ratioVelocity = 0
            return
        }

        // Parmakların merkezi ve ortalama uzaklığı (= açıklık)
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

        // Yeni hareket: başlangıç noktasını kaydet
        if !tracking {
            tracking = true
            startCount = count
            startSpread = spread
            startCenter = (cx, cy)
            lastRatio = 1
            lastTime = timestamp
            return
        }

        // Parmak sayısı değişti (5. parmak değdi vb.): kaldığı oran korunarak devam et
        if count != startCount {
            startCount = count
            if lastRatio > 0 { startSpread = spread / lastRatio }
            lastTime = timestamp
            return
        }

        guard startSpread > GestureMonitor.minStartSpread, !swipeLocked else { return }

        let ratio = spread / startSpread
        let dt = Float(timestamp - lastTime)
        if dt > 0, dt < 0.1 {
            ratioVelocity = ratioVelocity * 0.6 + ((ratio - lastRatio) / dt) * 0.4
        }
        lastRatio = ratio
        lastTime = timestamp

        if !active {
            let shiftX = cx - startCenter.x
            let shiftY = cy - startCenter.y
            let centerShift = (shiftX * shiftX + shiftY * shiftY).squareRoot()
            let spreadChange = abs(spread - startSpread)

            // Parmaklar birlikte kayıyorsa bu pinch değil kaydırmadır: bu dokunuşu yok say
            if centerShift > GestureMonitor.swipeShift && spreadChange < centerShift * 0.5 {
                swipeLocked = true
                return
            }
            guard abs(ratio - 1) > GestureMonitor.deadZone, spreadChange > centerShift * 0.5 else { return }
            active = true
        }

        publishChange(ratio: ratio)
    }

    // MARK: - Ana thread'e bildirim

    private func publishChange(ratio: Float) {
        lock.lock()
        let needsSchedule = pendingRatio == nil
        pendingRatio = ratio
        lock.unlock()

        guard needsSchedule, let handler = onPinchChanged else { return }
        DispatchQueue.main.async {
            guard let value = GestureMonitor.shared.takePendingRatio() else { return }
            MainActor.assumeIsolated { handler(value) }
        }
    }

    private func publishEnd(ratio: Float, velocity: Float) {
        guard let handler = onPinchEnded else { return }
        // Sıralı kuyruk: bekleyen son güncellemeden sonra çalışır
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(ratio, velocity) }
        }
    }

    private func takePendingRatio() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        let value = pendingRatio
        pendingRatio = nil
        return value
    }
}

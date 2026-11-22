//
//  Settings.swift
//  MyLaunchpad
//
//  Kullanıcı ayarları (UserDefaults'ta saklanır) ve Launchpad içinde açılan ayarlar paneli.
//

import SwiftUI
import AppKit
import Combine
import ServiceManagement

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    enum Default {
        static let columns = 7
        static let rows = 5
        static let iconSize: Double = 80
        static let openCloseDuration: Double = 0.35
        static let snapDuration: Double = 0.6
        static let scrollSensitivity: Double = 2.4
    }

    private let defaults = UserDefaults.standard

    @Published var columns: Int { didSet { defaults.set(columns, forKey: "settings.columns") } }
    @Published var rows: Int { didSet { defaults.set(rows, forKey: "settings.rows") } }
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: "settings.iconSize") } }
    @Published var openCloseDuration: Double { didSet { defaults.set(openCloseDuration, forKey: "settings.openCloseDuration") } }
    @Published var snapDuration: Double { didSet { defaults.set(snapDuration, forKey: "settings.snapDuration") } }
    @Published var scrollSensitivity: Double { didSet { defaults.set(scrollSensitivity, forKey: "settings.scrollSensitivity") } }

    var appsPerPage: Int { columns * rows }

    private init() {
        columns = defaults.object(forKey: "settings.columns") as? Int ?? Default.columns
        rows = defaults.object(forKey: "settings.rows") as? Int ?? Default.rows
        iconSize = defaults.object(forKey: "settings.iconSize") as? Double ?? Default.iconSize
        openCloseDuration = defaults.object(forKey: "settings.openCloseDuration") as? Double ?? Default.openCloseDuration
        snapDuration = defaults.object(forKey: "settings.snapDuration") as? Double ?? Default.snapDuration
        scrollSensitivity = defaults.object(forKey: "settings.scrollSensitivity") as? Double ?? Default.scrollSensitivity
    }

    func resetToDefaults() {
        columns = Default.columns
        rows = Default.rows
        iconSize = Default.iconSize
        openCloseDuration = Default.openCloseDuration
        snapDuration = Default.snapDuration
        scrollSensitivity = Default.scrollSensitivity
    }

    // MARK: - Mac açılınca başlat

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Hata olursa kullanıcıya gösterilecek mesajı döndürür
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "Ayarlanamadı: \(error.localizedDescription)"
        }
    }
}

/// Launchpad'in içinde açılan ayarlar paneli (Cmd+, ya da sağ alttaki dişli)
struct SettingsPanelView: View {
    @ObservedObject var vm: LaunchpadViewModel
    @ObservedObject var settings = SettingsStore.shared
    @State private var launchAtLogin = SettingsStore.shared.launchAtLoginEnabled
    @State private var loginMessage: String?

    var body: some View {
        ZStack {
            // Panelin dışına tıklayınca kapanır
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { vm.closeSettings() }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Ayarlar").font(.system(size: 26, weight: .semibold))
                    Spacer()
                    Button("Bitti") { vm.closeSettings() }
                }

                section("Genel")
                Toggle("Mac açılınca başlat", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        loginMessage = settings.setLaunchAtLogin(newValue)
                        launchAtLogin = settings.launchAtLoginEnabled
                        if settings.launchAtLoginNeedsApproval {
                            loginMessage = "macOS onay istiyor: Sistem Ayarları → Genel → Giriş Öğeleri'nden MyLaunchpad'e izin ver."
                        }
                    }
                ))
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                }
                if settings.launchAtLoginNeedsApproval {
                    Button("Giriş Öğeleri'ni aç") { SMAppService.openSystemSettingsLoginItems() }
                }

                section("Izgara")
                Stepper("Sütun sayısı: \(settings.columns)", value: $settings.columns, in: 4...10)
                Stepper("Satır sayısı: \(settings.rows)", value: $settings.rows, in: 3...7)
                sliderRow("Simge boyutu", value: $settings.iconSize, in: 56...120, step: 4,
                          display: "\(Int(settings.iconSize))")

                section("Hareket ve animasyon")
                sliderRow("Açılış / kapanış süresi", value: $settings.openCloseDuration, in: 0.15...0.7, step: 0.05,
                          display: String(format: "%.2f sn", settings.openCloseDuration))
                sliderRow("Sayfanın yerine oturma süresi", value: $settings.snapDuration, in: 0.3...1.0, step: 0.05,
                          display: String(format: "%.2f sn", settings.snapDuration))
                sliderRow("Kaydırma hassasiyeti", value: $settings.scrollSensitivity, in: 1.0...4.0, step: 0.1,
                          display: String(format: "x%.1f", settings.scrollSensitivity))

                Divider().padding(.vertical, 4)
                HStack {
                    Button("Varsayılanlara dön") { settings.resetToDefaults() }
                    Spacer()
                    Button("Simge sırasını sıfırla") { vm.resetOrder() }
                }
                Text("Cmd+, ile açılır, Esc ile kapanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
            .environment(\.colorScheme, .dark)
        }
        .onAppear { launchAtLogin = settings.launchAtLoginEnabled }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                           step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

//
//  UpdateChecker.swift
//  LayoutSwitcher
//
//  Проверка новых версий через публичный API GitHub Releases: при запуске и
//  раз в сутки запрашивается последний релиз репозитория, его тег сравнивается
//  с версией бандла. Ничего не скачивается и не устанавливается автоматически —
//  пользователю только показывается ссылка на DMG.
//

import AppKit
import Combine
import os.log

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    /// Репозиторий, в котором публикуются релизы.
    static let repository = "VitalyZnachenok/LayoutSwitcher"
    /// Как часто повторять проверку, пока приложение запущено.
    static let interval: TimeInterval = 24 * 60 * 60
    /// Задержка первой проверки после запуска: не мешаем старту и запросу разрешений.
    static let launchDelay: TimeInterval = 5
    
    struct Release: Equatable, Sendable {
        /// Версия без префикса "v", например "3.2".
        let version: String
        /// Страница релиза на GitHub.
        let pageURL: URL
        /// Прямая ссылка на DMG, если он приложен к релизу.
        let downloadURL: URL?
        
        /// Куда вести пользователя по кнопке «Скачать».
        var bestURL: URL { downloadURL ?? pageURL }
    }
    
    enum Status: Equatable {
        case never
        case checking
        case upToDate(Date)
        case available(Release)
        case failed(Date)
    }
    
    @Published private(set) var status: Status = .never
    /// Найденная новая версия (дублирует `.available`, но переживает повторную проверку со сбоем).
    @Published private(set) var available: Release?
    
    /// Автоматическая проверка включена (хранится отдельно от конфигурации хоткеев).
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            defaults.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }
    
    let currentVersion: String
    private let defaults: UserDefaults
    private let session: URLSession
    private var timer: Timer?
    private var started = false
    
    private static let enabledKey = "update_check_enabled"
    
    init(currentVersion: String? = nil, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
        self.defaults = defaults
        self.session = session
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }
    
    // MARK: Scheduling
    
    /// Запускает первую отложенную проверку и суточный таймер. Повторный вызов безопасен.
    func start() {
        guard isEnabled, !started, !Runtime.skipsPermissionPrompt else { return }
        started = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.launchDelay * 1_000_000_000))
            await self?.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        started = false
    }
    
    // MARK: Checking
    
    /// Один запрос к GitHub. Сетевые ошибки не показываются пользователю,
    /// только фиксируются в статусе.
    func check() async {
        if case .checking = status { return }
        status = .checking
        do {
            let release = try await fetchLatestRelease()
            if Self.isNewer(release.version, than: currentVersion) {
                if available != release {
                    Logger.ui.info("Update available: \(release.version) (current \(self.currentVersion))")
                }
                available = release
                status = .available(release)
            } else {
                available = nil
                status = .upToDate(Date())
                Logger.ui.debug("Up to date: latest \(release.version), current \(self.currentVersion)")
            }
        } catch {
            Logger.ui.warning("Update check failed: \(error.localizedDescription)")
            status = .failed(Date())
        }
    }
    
    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LayoutSwitcher/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.parseRelease(from: data)
    }
    
    // MARK: Parsing & comparison (чистые функции, покрыты тестами)
    
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }
    
    nonisolated static func parseRelease(from data: Data) throws -> Release {
        let gh = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let dmg = gh.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }
        return Release(version: normalizedVersion(gh.tag_name), pageURL: gh.html_url, downloadURL: dmg?.browser_download_url)
    }
    
    /// "v3.2" / "V3.2" / "3.2" → "3.2".
    nonisolated static func normalizedVersion(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" { s.removeFirst() }
        return s
    }
    
    /// Числовое сравнение по компонентам: "3.10" новее "3.9", "3.1" равна "3.1.0".
    /// Нечисловые компоненты считаются нулём.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = components(normalizedVersion(remote))
        let l = components(normalizedVersion(local))
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }
    
    nonisolated private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}

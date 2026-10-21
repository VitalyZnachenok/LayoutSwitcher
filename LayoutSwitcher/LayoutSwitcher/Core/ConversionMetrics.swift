//
//  ConversionMetrics.swift
//  LayoutSwitcher
//
//  Статистика конвертаций. Хранится в UserDefaults и переживает перезапуск.
//

import Foundation
import os.log

@MainActor
final class ConversionMetrics: ObservableObject {
    @Published private(set) var totalConversions: Int = 0
    @Published private(set) var successfulConversions: Int = 0
    @Published private(set) var failedConversions: Int = 0
    @Published private(set) var accessibilityConversions: Int = 0
    @Published private(set) var averageConversionTime: TimeInterval = 0
    
    private var conversionTimes: [TimeInterval] = []
    private let maxStoredTimes = 100
    private let storageKey = "conversion_metrics"
    private let defaults: UserDefaults
    
    private struct Stored: Codable {
        var total = 0
        var successful = 0
        var failed = 0
        var accessibility = 0
        var times: [TimeInterval] = []
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }
    
    /// - Parameter viaAccessibility: замена прошла через AX API (без буфера обмена).
    func recordSuccess(duration: TimeInterval, viaAccessibility: Bool = false) {
        totalConversions += 1
        successfulConversions += 1
        if viaAccessibility { accessibilityConversions += 1 }
        
        conversionTimes.append(duration)
        if conversionTimes.count > maxStoredTimes {
            conversionTimes.removeFirst()
        }
        
        averageConversionTime = conversionTimes.reduce(0, +) / Double(conversionTimes.count)
        Logger.conversion.info("✅ Conversion successful in \(String(format: "%.0f", duration * 1000))ms (\(viaAccessibility ? "AX" : "clipboard"))")
        save()
    }
    
    func recordFailure() {
        totalConversions += 1
        failedConversions += 1
        Logger.conversion.warning("❌ Conversion failed")
        save()
    }
    
    var successRate: Double {
        guard totalConversions > 0 else { return 0 }
        return Double(successfulConversions) / Double(totalConversions)
    }
    
    func reset() {
        totalConversions = 0
        successfulConversions = 0
        failedConversions = 0
        accessibilityConversions = 0
        averageConversionTime = 0
        conversionTimes.removeAll()
        save()
        Logger.conversion.info("Metrics reset")
    }
    
    var summary: String {
        """
        \(L(.statsHeader))
        • \(L(.statsTotal)): \(totalConversions)
        • \(L(.statsSuccess)): \(successfulConversions)
        • \(L(.statsFailed)): \(failedConversions)
        • \(L(.statsRate)): \(String(format: "%.1f%%", successRate * 100))
        • \(L(.statsAxShare)): \(accessibilityConversions)
        • \(L(.statsAvgTime)): \(String(format: "%.0f", averageConversionTime * 1000))\(L(.statsMsSuffix))
        """
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        totalConversions = stored.total
        successfulConversions = stored.successful
        failedConversions = stored.failed
        accessibilityConversions = stored.accessibility
        conversionTimes = Array(stored.times.suffix(maxStoredTimes))
        if !conversionTimes.isEmpty {
            averageConversionTime = conversionTimes.reduce(0, +) / Double(conversionTimes.count)
        }
    }
    
    private func save() {
        let stored = Stored(
            total: totalConversions, successful: successfulConversions,
            failed: failedConversions, accessibility: accessibilityConversions,
            times: conversionTimes
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }
}

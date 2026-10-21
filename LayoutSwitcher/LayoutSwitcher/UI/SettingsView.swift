//
//  SettingsView.swift
//  LayoutSwitcher
//
//  SwiftUI-содержимое окна настроек.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon.HIToolbox
import os.log

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isVisible = false
    @State private var isRecordingHotkey = false
    @State private var hotkeyRecorderMonitor: Any?
    
    /// Список раскладок и имена исключённых приложений кэшируются: `body`
    /// перерисовывается при каждом движении ползунка, а TIS и NSWorkspace
    /// на каждую перерисовку — это десятки системных вызовов в секунду.
    @State private var installedLayoutOptions: [LayoutOption] = []
    @State private var appDisplayNames: [String: String] = [:]
    
    private struct LayoutOption: Identifiable, Equatable {
        let id: String
        let name: String
    }
    
    private let layoutsChanged = DistributedNotificationCenter.default()
        .publisher(for: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : -20)
            
            ScrollView {
                LazyVStack(spacing: 20) {
                    languageSection
                    hotKeySection
                    autoSwitchSection
                    layoutPairSection
                    replacementSection
                    soundSection
                    
                    if !settings.configurationErrors.isEmpty {
                        validationErrorsView
                    }
                }
                .padding(20)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
            }
            
            footerView
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reloadLayouts()
            reloadAppNames()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
        .onReceive(layoutsChanged) { _ in reloadLayouts() }
        .onChange(of: settings.configuration.excludedAppBundleIDs) { _ in reloadAppNames() }
    }
    
    private func reloadLayouts() {
        installedLayoutOptions = LayoutManager.installedLayouts().map {
            LayoutOption(id: LayoutManager.sourceID($0), name: LayoutManager.sourceName($0))
        }
    }
    
    private func reloadAppNames() {
        var names: [String: String] = [:]
        for bundleID in settings.configuration.excludedAppBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                names[bundleID] = "\(FileManager.default.displayName(atPath: url.path))  ·  \(bundleID)"
            } else {
                names[bundleID] = bundleID
            }
        }
        appDisplayNames = names
    }
    
    // MARK: - Header / footer
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Layout Switcher")
                    .font(.system(size: 26, weight: .bold))
            }
            Text(L(.headerSubtitle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.isConfigurationValid ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(settings.isConfigurationValid ? L(.statusValid) : L(.statusInvalid))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L(.btnDone)) { closeWindow() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!settings.isConfigurationValid)
            }
            .padding(20)
        }
        .background(.regularMaterial)
    }
    
    private func closeWindow() {
        NSApplication.shared.windows
            .first { $0.identifier?.rawValue == SettingsWindow.windowIdentifier }?
            .close()
    }
    
    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Language
    
    private var languageSection: some View {
        sectionCard {
            Label(L(.secLanguage), systemImage: "globe.badge.chevron.backward")
                .font(.headline)
            Picker(L(.secLanguage), selection: $loc.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .labelsHidden()
        }
    }
    
    // MARK: - Hotkey
    
    private var hotKeySection: some View {
        sectionCard {
            Label(L(.secHotkey), systemImage: "command.square")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(L(.lblActivationMode))
                    .font(.subheadline.weight(.medium))
                Picker(L(.modeLabel), selection: $settings.configuration.hotKeyMode) {
                    ForEach(HotKeyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            Divider()
            
            switch settings.configuration.hotKeyMode {
            case .doubleShift:
                doubleTapSettings(hint: L(.dsHint))
            case .doubleAlt:
                doubleTapSettings(hint: L(.doubleAltHint))
            case .singleAlt:
                modeDescription(icon: "option", title: L(.hkSingleAlt), text: L(.singleAltDesc), note: L(.singleAltNote))
            case .ctrlShift:
                modeDescription(icon: "command.square", title: L(.hkCtrlShift), text: L(.ctrlShiftDesc), note: nil)
            case .fnShift:
                modeDescription(icon: "keyboard", title: L(.hkFnShift), text: L(.fnShiftDesc), note: L(.fnShiftNote))
            case .customHotkey:
                customHotkeySettings
            }
        }
    }
    
    private func doubleTapSettings(hint: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            intervalSlider(title: L(.lblMinInterval), value: $settings.configuration.minDoubleShiftInterval, range: 0.01...0.5)
            intervalSlider(title: L(.lblMaxInterval), value: $settings.configuration.maxDoubleShiftInterval, range: 0.1...2.0)
        }
        .padding(.leading, 16)
    }
    
    private func modeDescription(icon: String, title: String, text: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 16)
    }
    
    private func intervalSlider(title: String, value: Binding<TimeInterval>, range: ClosedRange<TimeInterval>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: L(.fmtMs), value.wrappedValue * 1000))
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            Slider(value: value, in: range) {
                Text(title)
            } minimumValueLabel: {
                Text(String(format: "%.0f", range.lowerBound * 1000)).font(.caption2).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text(String(format: "%.0f", range.upperBound * 1000)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
    
    private var customHotkeySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L(.lblCurrentCombo))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    isRecordingHotkey ? stopRecordingHotkey() : startRecordingHotkey()
                } label: {
                    Text(isRecordingHotkey ? L(.hotkeyRecording) : settings.configuration.displayString)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background((isRecordingHotkey ? Color.red : Color.accentColor).opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(isRecordingHotkey ? Color.red : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(L(.helpRecordHotkey))
            }
            Text(isRecordingHotkey ? L(.hotkeyRecordingHint) : L(.lblDefaultCombo))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear { stopRecordingHotkey() }
    }

    /// Начинает запись новой комбинации: следующее keyDown-событие в окне настроек
    /// становится новым custom-хоткеем. Esc без модификаторов отменяет запись.
    private func startRecordingHotkey() {
        stopRecordingHotkey()
        isRecordingHotkey = true
        hotkeyRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == KeyCode.escape && event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
                stopRecordingHotkey()
                return nil
            }
            applyRecordedHotkey(event)
            stopRecordingHotkey()
            return nil
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        if let monitor = hotkeyRecorderMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyRecorderMonitor = nil
        }
    }

    private func applyRecordedHotkey(_ event: NSEvent) {
        let character = (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !character.isEmpty else { return }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        settings.configuration.keyCode = event.keyCode
        settings.configuration.keyCharacter = character
        settings.configuration.modifierFlags = modifiers.rawValue
        Logger.ui.info("Custom hotkey recorded: \(settings.configuration.displayString)")
    }
    
    // MARK: - Auto-switch
    
    private var autoSwitchSection: some View {
        sectionCard {
            Label(L(.secAutoSwitch), systemImage: "character.cursor.ibeam")
                .font(.headline)
            Text(L(.autoSwitchDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker(L(.modeLabel), selection: $settings.configuration.autoSwitchMode) {
                ForEach(AutoSwitchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            if settings.configuration.autoSwitchMode != .off {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L(.lblDetectionEngine))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Picker(L(.lblDetectionEngine), selection: $settings.configuration.detectionEngine) {
                            ForEach(DetectionEngine.allCases, id: \.self) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(settings.configuration.detectionEngine == .ngram ? L(.engineNgramDesc) : L(.engineDictDesc))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Stepper(value: $settings.configuration.minWordLength, in: 2...20) {
                        HStack {
                            Text(L(.lblMinWordLength))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(settings.configuration.minWordLength)")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                    }
                    
                    soundPicker(title: L(.lblWarnSound), selection: $settings.configuration.wrongLayoutSoundName)
                    excludedAppsView
                }
                .padding(.leading, 16)
            }
        }
    }
    
    private var excludedAppsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(.lblExcludedApps))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { addExcludedApp() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(L(.helpAddApp))
            }
            
            if settings.configuration.excludedAppBundleIDs.isEmpty {
                Text(L(.excludedEmpty))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.configuration.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.secondary)
                            Text(appDisplayNames[bundleID] ?? bundleID)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.configuration.excludedAppBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help(L(.helpRemoveFromList))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
    
    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = L(.openPanelTitle)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        
        if !settings.configuration.excludedAppBundleIDs.contains(bundleID) {
            settings.configuration.excludedAppBundleIDs.append(bundleID)
            Logger.ui.info("Added excluded app: \(bundleID)")
        }
    }
    
    // MARK: - Layout pair
    
    private var layoutPairSection: some View {
        sectionCard {
            Label(L(.secLayoutPair), systemImage: "globe")
                .font(.headline)
            Text(L(.layoutPairDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            layoutPicker(title: L(.lblLayout1), selection: $settings.configuration.layout1ID)
            layoutPicker(title: L(.lblLayout2), selection: $settings.configuration.layout2ID)
        }
    }
    
    private func layoutPicker(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selection) {
                Text(L(.layoutAuto)).tag("")
                ForEach(installedLayoutOptions) { layout in
                    Text(layout.name).tag(layout.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }
    
    // MARK: - Replacement
    
    private var replacementSection: some View {
        sectionCard {
            Label(L(.secReplacement), systemImage: "text.cursor")
                .font(.headline)
            Toggle(L(.lblUseAX), isOn: $settings.configuration.useAccessibilityReplacement)
                .toggleStyle(.switch)
            Text(L(.axDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Sound
    
    private var soundSection: some View {
        sectionCard {
            Label(L(.secSound), systemImage: "speaker.wave.2")
                .font(.headline)
            Toggle(L(.menuPlaySounds), isOn: $settings.configuration.soundEnabled)
                .toggleStyle(.switch)
            
            if settings.configuration.soundEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L(.lblVolume))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(settings.configuration.soundVolume * 100))%")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                        Slider(value: $settings.configuration.soundVolume, in: 0.0...1.0) {
                            Text(L(.lblVolumePlain))
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.tertiary)
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    soundPicker(title: L(.lblSuccessSound), selection: $settings.configuration.successSoundName)
                    soundPicker(title: L(.lblErrorSound), selection: $settings.configuration.errorSoundName)
                }
                .padding(.leading, 16)
            }
        }
    }
    
    private func soundPicker(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Picker(title, selection: selection) {
                    ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                        Text(SoundConfiguration.localizedName(for: soundName)).tag(soundName)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                
                Button("▶️") {
                    SoundManager.shared.testSound(selection.wrappedValue, volume: settings.configuration.soundVolume)
                }
                .buttonStyle(.borderless)
                .help(L(.helpPlaySound))
            }
        }
    }
    
    // MARK: - Validation
    
    private var validationErrorsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L(.secConfigErrors), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(settings.configurationErrors, id: \.self) { error in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .padding(20)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

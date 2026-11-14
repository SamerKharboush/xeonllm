// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Charts

// MARK: - Settings

enum SettingsDestination: Hashable {
    case general, models, inference, speech, advanced, extensions
}

struct SettingsView: View {
    @EnvironmentObject var server: ServerController
    @EnvironmentObject var manager: ServerManager
    @EnvironmentObject var loc: Localizer
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var control: ControlPanelState
    @EnvironmentObject var models: ModelStore

    @AppStorage(SettingsKeys.engineKind) private var engineKind = ServerSettings.engineKind
    @AppStorage(SettingsKeys.serverBinary) private var serverBinary = ""
    @AppStorage(SettingsKeys.faAmd) private var faAmd = ServerSettings.defaultFaAmd
    @AppStorage(SettingsKeys.prefetchExperts) private var prefetchExperts = true
    @AppStorage(SettingsKeys.ubatch) private var ubatch = 0
    @AppStorage(SettingsKeys.routerMode) private var routerMode = false
    @AppStorage(SettingsKeys.persistCache) private var persistCache = false
    @AppStorage(SettingsKeys.port) private var port = 8080
    @AppStorage(SettingsKeys.ngl) private var ngl = 99
    @AppStorage(SettingsKeys.ncmoe) private var ncmoe = 0
    @AppStorage(SettingsKeys.ctx) private var ctx = 16384
    @AppStorage(SettingsKeys.threads) private var threads = 0 // 0 = physical cores, resolved at launch
    @AppStorage(SettingsKeys.flashAttn) private var flashAttn = "auto"
    @AppStorage(SettingsKeys.noMmap) private var noMmap = true
    @AppStorage(SettingsKeys.jinja) private var jinja = true
    @AppStorage(SettingsKeys.vramReserve) private var vramReserve = 0
    @AppStorage(SettingsKeys.gpuIndex) private var gpuIndex = -1
    @AppStorage(SettingsKeys.multiGPU) private var multiGPU = ServerSettings.defaultMultiGPU
    @AppStorage(SettingsKeys.multiGPUCount) private var multiGPUCount = 0
    @AppStorage(SettingsKeys.splitMode) private var splitMode = "layer"
    @AppStorage(SettingsKeys.splitGroupSize) private var splitGroupSize = 0
    @AppStorage(SettingsKeys.mgpuEvents) private var mgpuEvents = true
    @AppStorage(SettingsKeys.mgpuPeer) private var mgpuPeer = true
    @AppStorage(SettingsKeys.gpuList) private var gpuListCSV = ""
    @AppStorage(SettingsKeys.embeddings) private var embeddings = false
    @AppStorage(SettingsKeys.forcePrivateBuffers) private var forcePrivateBuffers = false
    @AppStorage(SettingsKeys.cacheReuse) private var cacheReuse = true
    @AppStorage(SettingsKeys.extraArgs) private var extraArgs = ""
    @AppStorage(SettingsKeys.cacheTypeK) private var cacheTypeK = "f16"
    @AppStorage(SettingsKeys.cacheTypeV) private var cacheTypeV = "f16"
    @AppStorage(SettingsKeys.mlock) private var mlock = false
    @AppStorage(SettingsKeys.cacheRAM) private var cacheRAM = 2048
    @AppStorage(SettingsKeys.imageMaxTokens) private var imageMaxTokens = 0
    @AppStorage(SettingsKeys.parallelSlots) private var parallelSlots = 1
    @AppStorage(SettingsKeys.separateKV) private var separateKV = false
    @AppStorage(SettingsKeys.reasoningInline) private var reasoningInline = false
    @AppStorage(SettingsKeys.serverDefaultReasoning) private var serverDefaultReasoning = "model"
    @AppStorage(SettingsKeys.serverDefaultMaxTokens) private var serverDefaultMaxTokens = -1
    @AppStorage(SettingsKeys.modelPath) private var modelPath = ""
    @AppStorage(SettingsKeys.dynamicMoeEnabled) private var dynamicMoeEnabled = false
    @AppStorage(SettingsKeys.executionMode) private var executionMode = "auto"
    @AppStorage(SettingsKeys.autoKVMode) private var autoKVMode = "auto"
    @AppStorage(SettingsKeys.dynamicMoeLeanRAM) private var dynamicMoeLeanRAM = false
    @AppStorage(SettingsKeys.modelsDir) private var modelsDir = ""
    @AppStorage(SettingsKeys.menuBarIcon) private var menuBarIcon = true
    @AppStorage(SettingsKeys.updateAutoCheck) private var updateAutoCheck = true
    @AppStorage(SettingsKeys.appAccent) private var appAccentRaw = AppTheme.defaultKey
    @AppStorage(SettingsKeys.menuBarGPU) private var menuBarGPU = "panel"
    @AppStorage(SettingsKeys.autoStart) private var autoStart = false
    @AppStorage(SettingsKeys.apiKeyEnabled) private var apiKeyEnabled = false
    @AppStorage(SettingsKeys.localNetworkDiscovery) private var localNetworkDiscovery = false
    @State private var showResetConfirm = false
    @State private var settingsTransferMessage: String?
    @State private var settingsDestination: SettingsDestination = .general

    private var availableKVTypes: [String] {
        ServerSettings.kvTypeChoices(modelPath: modelPath, selected: [cacheTypeK, cacheTypeV])
    }
    /// Why the chosen Turbo combination cannot run, so the warning names the actual cause
    /// instead of listing every reason Turbo might be unavailable.
    private var turboKVIncompatibleReason: String? {
        guard turboKVSelected else { return nil }
        if ServerSettings.isAppleSilicon {
            return "TurboQuant KV is only available on cards without unified memory."
        }
        if !ServerSettings.modelSupportsTurboKV(at: modelPath) {
            return "This model does not support TurboQuant KV: its attention heads do not pad to a multiple of 128."
        }
        if cacheTypeV.hasPrefix("turbo") && !cacheTypeK.hasPrefix("turbo") &&
            ServerSettings.modelUsesMLA(at: modelPath) {
            return "This model keeps keys and values in a single cache, so both must use the same type."
        }
        return nil
    }
    private var turboKVIncompatible: Bool { turboKVIncompatibleReason != nil }
    private var turboKVSelected: Bool {
        cacheTypeK.hasPrefix("turbo") || cacheTypeV.hasPrefix("turbo")
    }
    /// Quantizing the keys is what costs quality; values tolerate 4 bits. Measured
    /// within 0.5% of f16 on 4B, 8B and 35B, at 25% less cache than q8_0/q8_0.
    private var kvSuggestion: (k: String, v: String)? {
        guard !ServerSettings.isAppleSilicon, !modelPath.isEmpty,
              ServerSettings.modelSupportsTurboKV(at: modelPath),
              !ServerSettings.modelUsesMLA(at: modelPath) else { return nil }
        return ("q8_0", "turbo4")
    }
    private var serverIsStopped: Bool {
        if case .stopped = server.state { return true }
        if case .failed = server.state { return true }
        return false
    }
    // Networking is a launch flag, so restart the running server to apply it now.
    private func setDiscoverable(_ on: Bool) {
        localNetworkDiscovery = on
        if !serverIsStopped { server.restart(.fromDefaults()) }
    }
    private var currentModelIsVision: Bool {
        ModelTraitsCache.cached(for: modelPath)?.hasVision == true
    }
    private var splitSelection: [Int] { ServerSettings.gpuList(fromCSV: gpuListCSV) }
    private var peerGroupShortcuts: [(label: String, indices: [Int])] {
        GPUPeerTopology.groups(of: hardware.gpus)
    }
    /// GPUs the split will actually use, which is what decides whether a tensor split
    /// still holds its generation speed.
    private var splitTargetCount: Int {
        if splitSelection.count >= 2 { return splitSelection.count }
        return multiGPUCount > 0 ? min(multiGPUCount, hardware.gpus.count) : hardware.gpus.count
    }
    /// Widths that divide the split evenly and leave more than one row; two GPUs
    /// have none.
    private var splitGroupOptions: [Int] {
        let n = splitTargetCount
        guard n > 2 else { return [] }
        return (2..<n).filter { n % $0 == 0 }
    }
    /// macOS exposes the bridge nowhere else: linked GPUs share a Metal peer group.
    private var hasPeerLink: Bool { !hardware.peerGroups.isEmpty }
    private func toggleSplitGPU(_ i: Int) {
        var sel = Set(splitSelection)
        if sel.contains(i) { sel.remove(i) } else { sel.insert(i) }
        gpuListCSV = sel.sorted().map(String.init).joined(separator: ",")
    }
    private var kvNeedsFlashAttention: Bool { cacheTypeK != "f16" || cacheTypeV != "f16" }
    private var amdFlashActive: Bool { faAmd }
    private var engineSelection: Binding<String> {
        Binding(
            get: { engineKind },
            set: { kind in
                engineKind = kind
                if kind == "bundled" {
                    serverBinary = ""
                    faAmd = ServerSettings.defaultFaAmd
                } else {
                    faAmd = false
                }
            })
    }

    private func chooseModelsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppInfo.branded("Choose")
        panel.directoryURL = models.directory
        if panel.runModal() == .OK, let url = panel.url {
            modelsDir = url.path
            models.refresh()
        }
    }

    var body: some View {

        VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        settingsNavigation
                        Spacer(minLength: 16)
                        settingsActions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ScrollView(.horizontal) { settingsNavigation }
                            .scrollIndicators(.hidden)
                        HStack { Spacer(minLength: 0); settingsActions }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if manager.servers.count > 1 {
                    Label(AppInfo.branded("Added servers inherit these settings except what you change in their configuration."),
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 24).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

            settingsContent
        }
        .confirmationDialog(
            AppInfo.branded("Reset all options to their defaults?"),
            isPresented: $showResetConfirm, titleVisibility: .visible
        ) {
            Button(AppInfo.branded("Reset"), role: .destructive) {
                SettingsKeys.resetOptionsToDefaults()
            }
            Button(AppInfo.branded("Cancel"), role: .cancel) {}
        } message: {
            Text(AppInfo.branded("Your downloaded models and models folder are kept."))
        }
        .alert(AppInfo.branded("Settings"),
               isPresented: Binding(get: { settingsTransferMessage != nil },
                                    set: { if !$0 { settingsTransferMessage = nil } })) {
            Button("OK") { settingsTransferMessage = nil }
        } message: {
            Text(settingsTransferMessage ?? "")
        }
    }

    private var settingsNavigation: some View {
        GlassSegmentedControl(selection: $settingsDestination, segments: [
            .init(value: .general, title: AppInfo.branded("General"), systemImage: "gearshape"),
            .init(value: .models, title: AppInfo.branded("Models"), systemImage: "shippingbox"),
            .init(value: .inference, title: AppInfo.branded("Inference"), systemImage: "point.3.connected.trianglepath.dotted"),
            .init(value: .speech, title: AppInfo.branded("Speech & Audio"), systemImage: "waveform"),
            .init(value: .advanced, title: AppInfo.branded("Advanced"), systemImage: "slider.horizontal.3"),
            .init(value: .extensions, title: AppInfo.branded("Extensions"), systemImage: "puzzlepiece.extension")
        ])
    }

    private var settingsActions: some View {
        GlassActionGroup {
            Button(AppInfo.branded("Import"), systemImage: "square.and.arrow.down") {
                importSettings()
            }
            .glassButton()
            Button(AppInfo.branded("Export"), systemImage: "square.and.arrow.up") {
                exportSettings()
            }
            .glassButton()
            Button(role: .destructive) { showResetConfirm = true } label: {
                Label(AppInfo.branded("Reset to defaults"),
                      systemImage: "arrow.counterclockwise")
            }
            .glassButton()
            .tint(.red)
            .help(AppInfo.branded("Returns every option (engine, GPU, inference, chat) to its default value. It does not delete models or change the models folder."))
        }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            settingsPanelHeader
            Divider().opacity(0.65)
            // ViewThatFits would build the whole form once per candidate, doubling
            // every control and leaving hover state on the copy that is not shown.
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 0) {
                    settingsForm
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if proxy.size.width >= 930 {
                        Divider().opacity(0.65)
                        settingsCategoryGuide
                            .frame(width: 340)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .background(WorkspaceStyle.surface.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(WorkspaceStyle.border)
            .allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var settingsPanelHeader: some View {
        let content = categoryPanelContent
        return HStack(spacing: 12) {
            SectionGlyph(systemName: content.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).font(.headline)
                Text(content.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var settingsCategoryGuide: some View {
        SettingsCategoryGuide(content: settingsDestination.guideContent(loc))
    }

    private var categoryPanelContent: (icon: String, title: String, subtitle: String) {
        switch settingsDestination {
        case .general:
            return ("desktopcomputer",
                    AppInfo.branded("Application"),
                    AppInfo.branded("General application settings and behavior."))
        case .models:
            return ("memorychip",
                    AppInfo.branded("Models, GPU & memory"),
                    AppInfo.branded("Profiles and options for loading models on your hardware."))
        case .inference:
            return ("square.stack.3d.up",
                    AppInfo.branded("Inference & context"),
                    AppInfo.branded("Context, cache, and generation behavior."))
        case .speech:
            return ("waveform",
                    AppInfo.branded("Speech & transcription"),
                    AppInfo.branded("Local audio input and transcription."))
        case .advanced:
            return ("slider.horizontal.3",
                    AppInfo.branded("Services & engine"),
                    AppInfo.branded("Engine, network, embeddings, and additional options."))
        case .extensions:
            return ("puzzlepiece.extension",
                    AppInfo.branded("Extensions"),
                    AppInfo.branded("Tools and agents added to the engine from a folder."))
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(AppInfo.name) Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsArchive.exportData().write(to: url, options: .atomic)
            settingsTransferMessage = AppInfo.branded("Settings exported successfully.")
        } catch {
            settingsTransferMessage = error.localizedDescription
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try SettingsArchive.importData(Data(contentsOf: url))
            settingsTransferMessage = AppInfo.branded("Imported \(count) settings. Restart the server to apply engine changes.")
        } catch {
            settingsTransferMessage = error.localizedDescription
        }
    }

    @ViewBuilder private var settingsForm: some View {
        switch settingsDestination {
        case .general: generalSettings
        case .advanced: advancedSettings
        case .extensions: ExtensionsSettingsView()
        default: otherSettingsForm
        }
    }

    private var advancedSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                SettingsRowGroup {
                    SettingsRow(icon: "number", title: AppInfo.branded("Port"),
                                help: AppInfo.branded("Local server port (OpenAI-compatible API and web chat).")) {
                        DeferredSettingsIntegerField(value: $port, in: 1...65_535, width: 120)
                    }
                    SettingsRow(icon: "engine.combustion",
                                title: AppInfo.branded("Inference engine"),
                                help: AppInfo.branded("Bundled: official llama.cpp with the Metal kernels for AMD, recommended. External: any llama-server of yours.")) {
                        XeonDropdown(selection: engineSelection, options: [
                            .init(value: "bundled", title: AppInfo.branded("Bundled (official)")),
                            .init(value: "custom", title: AppInfo.branded("External…"))
                        ], width: 200)
                    }
                    if engineSelection.wrappedValue != "custom" {
                        SettingsRow(icon: "externaldrive",
                                    title: AppInfo.branded("Remember conversations (disk cache)"),
                                    help: AppInfo.branded("Saves each conversation's KV cache to disk, so reopening a chat or restarting the app skips re-processing the prompt (saves several seconds per turn on long prompts). Requires the AMD Flash Attention kernel; with quantized KV (q8_0/q4_0) the file is smaller and restore is faster. Files live in Application Support and are removed when you delete the conversation.")) {
                            SettingsToggle(isOn: $persistCache)
                                .disabled(!amdFlashActive)
                        }
                    }
                    if engineSelection.wrappedValue == "custom" {
                        SettingsRow(icon: "terminal",
                                    title: AppInfo.branded("External llama-server path"),
                                    help: AppInfo.branded("Path to an alternative llama-server to test other builds.")) {
                            DeferredSettingsTextField("", text: $serverBinary,
                                                      width: 240, monospaced: true)
                        }
                    }
                    SettingsRow(icon: "point.3.connected.trianglepath.dotted",
                                title: AppInfo.branded("Embeddings server (--embeddings)"),
                                help: AppInfo.branded("Serves /v1/embeddings for RAG clients (e.g. Obsidian Copilot), which otherwise get a 501 error. Note: llama-server dedicates the process to embeddings, so enable it with an embedding model; to keep chatting, add a second server on Home with this option.")) {
                        SettingsToggle(isOn: $embeddings)
                    }
                    SettingsRow(icon: "terminal",
                                title: AppInfo.branded("Extra arguments"),
                                help: AppInfo.branded("Additional llama-server arguments, space-separated. A KEY=VALUE token is applied as an environment variable. On GCN/Vega cards with corrupted text, GGML_METAL_WAVE64_SAFEMODE=1 forces the safe path.")) {
                        DeferredSettingsTextField("", text: $extraArgs,
                                                  width: 240, monospaced: true)
                    }
                }

                if engineSelection.wrappedValue != "custom" {
                    if currentModelIsVision {
                        Label(AppInfo.branded("Silently skipped while vision is on (the eye): llama.cpp cannot save/restore slots with mmproj loaded. With the eye off it works normally."),
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !amdFlashActive {
                        Label(AppInfo.branded("Requires enabling the AMD Flash Attention kernel (above)."),
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(AppInfo.branded("Changes take effect when the server restarts."))
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppInfo.branded("Server log"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Button { control.section = .logs } label: {
                        Label(AppInfo.branded("Open full log"),
                              systemImage: "list.bullet.rectangle")
                    }
                    .glassButton()
                    .infoTip(AppInfo.branded("The server log — with search, filters and export — lives in the Logs tab."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// General is laid out by hand: the platform form cannot give rows a glyph or
    /// the workspace field surfaces the rest of the window uses.
    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsRowGroup {
                    SettingsRow(icon: "paintpalette",
                                title: AppInfo.branded("App color"),
                                help: AppInfo.branded("Brand color for buttons, icons and controls across the app. Independent from the system accent color.")) {
                        XeonDropdown(selection: $appAccentRaw, options: AppTheme.palette.map {
                            .init(value: $0.key, title: AppTheme.label($0.key, loc),
                                  swatch: AppTheme.swatchImage($0.color))
                        })
                    }
                    SettingsRow(icon: "menubar.rectangle",
                                title: AppInfo.branded("Menu bar icon"),
                                help: AppInfo.branded("Shows a menu bar icon with server status and quick controls, even with the window closed.")) {
                        SettingsToggle(isOn: $menuBarIcon)
                    }
                    SettingsRow(icon: "memorychip",
                                title: AppInfo.branded("GPU VRAM in the menu bar"),
                                help: AppInfo.branded("Where to show VRAM usage: next to the icon (aggregate percentage) or as per-GPU bars when the panel opens.")) {
                        XeonDropdown(selection: $menuBarGPU, options: [
                            .init(value: "off", title: AppInfo.branded("Hidden")),
                            .init(value: "icon", title: AppInfo.branded("In the icon")),
                            .init(value: "panel", title: AppInfo.branded("In the panel"))
                        ])
                        .disabled(!menuBarIcon)
                    }
                    SettingsRow(icon: "play.circle",
                                title: AppInfo.branded("Start server on app launch"),
                                help: AppInfo.branded("Automatically starts the last configured model when XeonLLM opens.")) {
                        SettingsToggle(isOn: $autoStart)
                    }
                    if AppInfo.updatesEnabled {
                        SettingsRow(icon: "arrow.triangle.2.circlepath",
                                    title: AppInfo.branded("Check for updates hourly"),
                                    help: AppInfo.branded("Besides the launch check, silently re-checks every hour while the app is open and lights the update badge when a new version exists. Never downloads or installs on its own.")) {
                            SettingsToggle(isOn: $updateAutoCheck)
                        }
                    }
                    SettingsRow(icon: "key",
                                title: AppInfo.branded("Protect the API with a key"),
                                help: AppInfo.branded("Generates a key (stored in the Keychain) required on every request. The in-app chat uses it automatically; useful on shared Macs.")) {
                        SettingsToggle(isOn: $apiKeyEnabled)
                    }
                    SettingsRow(icon: "network",
                                title: AppInfo.branded("Discoverable on local network"),
                                help: AppInfo.branded("Makes the server listen on the local network and advertises it with Bonjour as 'XeonLLM API'. Enable only on trusted networks; restarts the server if it's running.")) {
                        SettingsToggle(isOn: Binding(get: { localNetworkDiscovery },
                                                     set: setDiscoverable))
                    }
                    SettingsRow(icon: "folder",
                                title: AppInfo.branded("Models folder"),
                                subtitle: models.directory.path,
                                help: AppInfo.branded("Folder where .gguf models are downloaded, scanned and deleted. Defaults to ~/models. When you change it, models already in the old folder are not moved; move them yourself if you want them in the new one.")) {
                        HStack(spacing: 8) {
                            if !modelsDir.isEmpty {
                                Button(AppInfo.branded("Reset")) {
                                    modelsDir = ""
                                    models.refresh()
                                }
                                .glassButton()
                            }
                            Button(AppInfo.branded("Change…")) { chooseModelsFolder() }
                                .glassButton()
                        }
                    }
                }

                if localNetworkDiscovery && !apiKeyEnabled {
                    Label(AppInfo.branded("Recommended: enable 'Protect the API with a key' before exposing the server on the local network."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if apiKeyEnabled {
                    HStack {
                        Text(AppInfo.branded("Key")).foregroundStyle(.secondary)
                        Text(Keychain.apiKey())
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Keychain.apiKey(), forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(AppInfo.branded("Copy the key"))
                            .infoTip(AppInfo.branded("Copy to use from other clients (Authorization: Bearer …)."))
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var otherSettingsForm: some View {
        Form {

            if settingsDestination == .speech {
            SpeechModelsSettingsSection()
            }

            if settingsDestination == .models {
            Section(AppInfo.branded("Profiles")) {
                ProfileNameField()
                ForEach(profileStore.profiles) { p in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(WorkspaceStyle.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(WorkspaceStyle.border))
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).fontWeight(.medium)
                            Text(URL(fileURLWithPath: p.modelPath).lastPathComponent)
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Button(AppInfo.branded("Apply")) { profileStore.apply(p) }
                            .glassButton()
                            .fixedSize()
                            .infoTip(AppInfo.branded("Loads this configuration. Restart the server to use it."))
                        Button(role: .destructive) { profileStore.delete(p) } label: {
                            Label(AppInfo.branded("Delete"), systemImage: "trash")
                        }
                            .labelStyle(.iconOnly)
                            .glassButton()
                            .tint(.red)
                            .accessibilityLabel(AppInfo.branded("Delete the profile"))
                    }
                }
            }

            Section(AppInfo.branded("Performance & Memory")) {
                Toggle(AppInfo.branded("Dynamic MoE (experimental)"), isOn: $dynamicMoeEnabled)
                    .settingsGlyph("wand.and.stars")
                    .infoTip(AppInfo.branded("Off: MoE models use the standard expert offload with your settings below. On: the engine uses the GPU, RAM and the model file itself to fit the model; it keeps the most used experts in VRAM and in RAM what the machine can give right now, picks the KV and batch size, and when nothing fits safely it does not load the model and says why."))
                if dynamicMoeEnabled {
                    LabeledContent(AppInfo.branded("Execution")) {
                        XeonDropdown(selection: $executionMode, options: [
                            .init(value: "auto", title: AppInfo.branded("Auto")),
                            .init(value: "full", title: AppInfo.branded("Full GPU (manual)")),
                            .init(value: "dmoe", title: "Dynamic MoE"),
                            .init(value: "legacy", title: AppInfo.branded("Legacy offload"))
                        ], width: 200)
                    }
                    .settingsGlyph("cpu")
                    .infoTip(AppInfo.branded("Auto decides on its own. Full GPU loads everything on the GPU even with little headroom (for testing). Dynamic MoE forces it on MoE models. Legacy offload uses the manual ncmoe setting below."))
                    LabeledContent(AppInfo.branded("KV cache")) {
                        XeonDropdown(selection: $autoKVMode, options: [
                            .init(value: "auto", title: AppInfo.branded("Auto")),
                            .init(value: "f16", title: "F16"),
                            .init(value: "q8_0", title: "Q8"),
                            .init(value: "turbo4", title: AppInfo.branded("Turbo4 (memory saver)"))
                        ], width: 200)
                    }
                    .settingsGlyph("key")
                    .infoTip(AppInfo.branded("Auto uses F16 and moves to Q8 only when that frees memory that really matters (Q8 has no measurable quality cost). Turbo4 saves more memory at some quality cost: Auto picks it, when the model supports it, only if neither F16 nor Q8 keeps the experts on the GPU, and then it can be much faster. Pick F16 or Q8 to never use it."))
                    Toggle(AppInfo.branded("Save RAM"), isOn: $dynamicMoeLeanRAM)
                        .settingsGlyph("memorychip")
                        .infoTip(AppInfo.branded("Off: when they fit, every expert stays in RAM, also the ones already in VRAM. On: RAM keeps only the ones that are not in VRAM and leaves the rest free for other apps; generation is slower (11 to 17% on a 35B model) and the first prompt after loading takes longer."))
                }
            }

            Section(AppInfo.branded("GPU & memory")) {
                LabeledContent(AppInfo.branded("GPU (Metal)")) {
                    XeonDropdown(selection: $gpuIndex, options: [.init(value: -1, title: AppInfo.branded("Default"))]
                        + hardware.gpus.map {
                            .init(value: $0.index, title: "\($0.index): \($0.name) · \($0.vramGB) GB")
                        }, width: 220)
                }
                .settingsGlyph("cpu")
                .infoTip(AppInfo.branded("Which GPU the server uses if you have several. 'Default' lets Metal choose."))
                .disabled(multiGPU)
                if hardware.gpus.count > 1 {
                    Toggle(AppInfo.branded("Split model across all GPUs (experimental)"), isOn: $multiGPU)
                        .onChange(of: multiGPU) { _, on in
                            if !on { gpuListCSV = "" }
                        }
                        .settingsGlyph("square.split.2x1")
                        .infoTip(AppInfo.branded("Splits the model across all detected GPUs (--split-mode) instead of using one, e.g. to load a model that doesn't fit on a single card. Overrides the picker above."))
                    if multiGPU && hardware.gpus.count > 2 && splitSelection.count < 2 {
                        LabeledContent(AppInfo.branded("GPUs to use")) {
                            XeonDropdown(selection: $multiGPUCount, options: [.init(value: 0, title: AppInfo.branded("All (\(hardware.gpus.count))"))]
                                + (2...hardware.gpus.count).map { .init(value: $0, title: "\($0)") }, width: 130)
                        }
                        .settingsGlyph("number")
                        .infoTip(AppInfo.branded("How many GPUs to split across. More GPUs = faster prompt; fewer GPUs = faster generation (less cross-card sync)."))
                    }
                    if multiGPU {
                        LabeledContent(AppInfo.branded("Split GPUs")) {
                            GPUMultiPicker(
                                label: splitSelection.count >= 2
                                    ? AppInfo.branded("\(splitSelection.count) selected")
                                    : AppInfo.branded("All"),
                                selection: Set(splitSelection),
                                defaultTitle: AppInfo.branded("All"),
                                onDefault: { gpuListCSV = "" },
                                onSelect: { gpuListCSV = $0.sorted().map(String.init).joined(separator: ",") },
                                onToggle: toggleSplitGPU)
                        }
                        .settingsGlyph("rectangle.split.3x1")
                        .infoTip(AppInfo.branded("Which specific GPUs take part in the split (e.g. 0 and 6, skipping the rest). With 'All', the first N from the picker above are used, and each 'Fabric' shortcut picks every card behind one bridge at once."))
                        if splitSelection.count == 1 {
                            Label(AppInfo.branded("Pick at least 2 GPUs for the split; with only one, all are used."),
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Label(AppInfo.branded("⚠️ Experimental and unvalidated on AMD/Metal: cross-GPU splitting is a different path that could produce wrong output or hang the engine. Check that generation is coherent and watch stability. Needs more testing."),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                        LabeledContent(AppInfo.branded("How to split it")) {
                            XeonDropdown(selection: $splitMode, options: [
                                .init(value: "layer", title: AppInfo.branded("By layers")),
                                .init(value: "tensor", title: AppInfo.branded("By tensors"))
                            ])
                        }
                        .settingsGlyph("square.split.2x2")
                        .infoTip(AppInfo.branded("By layers: each GPU keeps whole layers and they take turns. Fastest at generating, and the best tested. By tensors: both GPUs work at once inside every layer, so they read the prompt much faster, but they sync up on every layer and that wait costs the same on each generated token: on a small model it eats the gain, on a big one (tens of GB) it wins at both."))
                        if splitMode == "tensor" && !splitGroupOptions.isEmpty {
                            LabeledContent(AppInfo.branded("TensorMesh: mesh width")) {
                                XeonDropdown(selection: $splitGroupSize, options: [.init(value: 0, title: AppInfo.branded("No mesh"))]
                                    + splitGroupOptions.map { .init(value: $0, title: "\($0)") }, width: 130)
                            }
                            .settingsGlyph("grid")
                            .infoTip(AppInfo.branded("Arranges the GPUs as a mesh: inside a row the model is cut by tensors, between rows by layers. Each card then waits only for the others in its row instead of all of them, which is what sinks generation when going from two cards to four. Measured on four Radeon Pro W6800X with an 8B: rows of two generate 57 against 30 with all four together. What it buys is four cards at the speed of two, not more speed than two: a row of two matches a plain tensor split on two cards (1624 against 1667 reading, 57 against 58 generating). Use it to get the VRAM of four without their slowdown."))
                        }
                        Toggle(AppInfo.branded("Fast hand-off between GPUs"), isOn: $mgpuEvents)
                            .settingsGlyph("bolt.horizontal")
                            .infoTip(AppInfo.branded("Hands data from one GPU to the other without draining both queues on every copy. It changes nothing when splitting by layers; when splitting by tensors it is most of the generation speed (measured +59% on two GPUs). Turn it off only to diagnose."))
                        Toggle(AppInfo.branded("Infinity Fabric Link between GPUs"), isOn: $mgpuPeer)
                            .disabled(!hasPeerLink)
                            .settingsGlyph("link")
                            .infoTip(AppInfo.branded("If two GPUs in the split share an Infinity Fabric bridge (the two halves of a W6800X Duo or Vega II Duo, or two cards joined by the external bridge), copies activations directly between them instead of through system RAM. When splitting by tensors it reads the prompt 16% faster at no cost to generation, measured on four Radeon Pro Vega II. It needs the fast hand-off on: on its own it halves generation. If the machine doesn't support it, the copy falls back to the safe path on its own."))
                        if !hasPeerLink {
                            Label(AppInfo.branded("No bridge is detected between these GPUs, so there is nothing to turn on. Metal would put them in the same peer group if there were one."),
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if splitMode == "tensor" && splitTargetCount > 2 {
                            Label(AppInfo.branded("With more than two GPUs a tensor split reads the prompt almost twice as fast but generates slower: every layer makes the GPUs wait for each other, and that wait grows with each GPU you add. Measured on four Vega II: 207 against 109 reading, 13.2 against 16.2 generating. With two GPUs it loses nothing."),
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if mgpuPeer && splitMode != "tensor" {
                            Label(AppInfo.branded("With a layer split it does nothing: the bridge speeds up the reduction that only exists when splitting by tensors."),
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                // Covers the case the picker cannot: macOS choosing the eGPU on its own.
                if ServerController.hasExternalGPU() {
                    Toggle(AppInfo.branded("VRAM-resident weights (recommended for eGPU)"), isOn: $forcePrivateBuffers)
                        .settingsGlyph("internaldrive")
                        .infoTip(AppInfo.branded("The Metal backend uses shared (system) memory on external GPUs, which streams weights over Thunderbolt every op and tanks speed (~0.8 t/s). This forces private VRAM buffers. If you pin an eGPU in the picker above it's automatic; use this when you leave 'Default' and macOS picks the eGPU."))
                }
                Stepper(ngl < 0 ? AppInfo.branded("GPU layers (-ngl): Auto")
                                : AppInfo.branded("GPU layers (-ngl): \(ngl)"),
                        value: $ngl, in: -1...99)
                    .settingsGlyph("square.3.layers.3d")
                    .infoTip(AppInfo.branded("How many model layers go to the GPU. 99 = all (recommended if they fit in VRAM). Auto, below 0, loads as many as fit in free VRAM and keeps the VRAM reserve; with Dynamic MoE or experts on the CPU it loads them all."))
                let modelIsMoE = modelPath.isEmpty || ServerSettings.modelIsMoE(at: modelPath)
                Stepper(modelIsMoE
                            ? AppInfo.branded("MoE experts on CPU: \(ncmoe)")
                            : AppInfo.branded("MoE experts on CPU: N/A (dense model)"),
                        value: Binding(get: { ncmoe }, set: { v in
                            ncmoe = v
                            ServerSettings.rememberNcmoe(v, forModel: modelPath)
                        }), in: 0...99)
                    .settingsGlyph("cpu")
                    .infoTip(AppInfo.branded("MoE models only: layers whose 'experts' live in RAM and run on the CPU. Auto-set when picking a model; raise if VRAM saturates, lower if you have headroom. (Disabled on dense models, where the engine ignores it.)"))
                    .disabled(!modelIsMoE || (dynamicMoeEnabled && executionMode != "legacy"))
                Stepper(vramReserve == 0
                            ? AppInfo.branded("VRAM reserve: automatic")
                            : AppInfo.branded("VRAM reserve: \(vramReserve) MB"),
                        value: $vramReserve, in: 0...4096, step: 256)
                    .settingsGlyph("gauge.with.needle")
                    .infoTip(AppInfo.branded("VRAM left free for the system and UI. The Dynamic MoE plan, router mode, DFlash in Auto and GPU layers in Auto keep it. Automatic leaves 8% of the card, between 768 and 1536 MB."))
                Toggle(AppInfo.branded("Copy weights to VRAM (--no-mmap, recommended)"), isOn: $noMmap)
                    .settingsGlyph("arrow.down.to.line")
                    .infoTip(AppInfo.branded("Copies weights into VRAM instead of reading them over PCIe per token. On a discrete GPU this multiplies speed (~6×). Disable only for debugging."))
                Toggle(AppInfo.branded("Lock model in RAM (--mlock)"), isOn: $mlock)
                    .settingsGlyph("lock")
                    .infoTip(AppInfo.branded("Prevents macOS from swapping or compressing the model: consistent speed. Useful with large MoE models; requires enough free RAM."))
                LabeledContent(AppInfo.branded("Prompt cache in RAM")) {
                    XeonDropdown(selection: $cacheRAM, options: [
                        .init(value: 0, title: AppInfo.branded("Disabled")),
                        .init(value: 1024, title: "1 GB"), .init(value: 2048, title: "2 GB"),
                        .init(value: 4096, title: "4 GB"), .init(value: 8192, title: "8 GB")
                    ])
                }
                .settingsGlyph("memorychip")
                .infoTip(AppInfo.branded("Extra RAM where the engine remembers recent conversations to avoid reprocessing them when switching chats or clients. Unlimited, the engine uses up to 8 GB: next to a large model that pushes the machine into swap and speed degrades over time. 2 GB is a good balance."))

                LabeledContent(AppInfo.branded("Image token cap")) {
                    XeonDropdown(selection: $imageMaxTokens, options: [
                        .init(value: 0, title: AppInfo.branded("Model's")),
                        .init(value: 4096, title: "4096"), .init(value: 2048, title: "2048"),
                        .init(value: 1024, title: "1024")
                    ])
                }
                .settingsGlyph("photo")
                .infoTip(AppInfo.branded("How many tokens one image may take on vision models. The model decides by default. The vision encoder's memory grows with the square of this number, so lowering it cuts memory a lot at the cost of detail: it is what makes a vision model load on cards where that buffer does not fit."))
            }
            }

            if settingsDestination == .inference {
            Section {
                LabeledContent(AppInfo.branded("Context")) {
                    XeonDropdown(selection: $ctx, options: ServerSettings.contextChoices(modelPath: modelPath).map {
                        .init(value: $0, title: "\(ServerSettings.contextLabel($0)) tokens")
                    })
                }
                .settingsGlyph("text.alignleft")
                .infoTip(AppInfo.branded("Maximum conversation size in tokens. More context = more KV cache memory (see the types below to compensate)."))
                if ctx >= 131072 {
                    Label(AppInfo.branded("Very large context (for testing). The KV cache may not fit in VRAM/RAM; on AMD GPUs without Flash Attention generation slows with depth. Quantize keys (q8_0) to compensate; 16–32k is fine for normal use."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent(AppInfo.branded("KV cache: keys (-ctk)")) {
                    XeonDropdown(selection: $cacheTypeK, options: availableKVTypes.map { .init(value: $0, title: $0) }, width: 120)
                }
                .settingsGlyph("key")
                .infoTip(amdFlashActive
                    ? AppInfo.branded("Quantization for KV cache keys. With the AMD Flash Attention kernel, any standard combination (f16/q8_0/q4_0 for keys and values) runs on the GPU at full speed, including the fast long-prompt route. For maximum memory savings: q8_0/q8_0 (half, recommended) or q4_0/q4_0 (a quarter); to compress only the keys while keeping values at full precision: q8_0/f16 or q4_0/f16.")
                    : AppInfo.branded("Quantization for KV cache keys. On AMD GPUs (without the AMD Flash Attention kernel): q8_0 halves key memory at almost no speed cost (recommended), keeping values at f16; q4_0 quarters it."))
                LabeledContent(AppInfo.branded("KV cache: values (-ctv)")) {
                    XeonDropdown(selection: $cacheTypeV, options: availableKVTypes.map { .init(value: $0, title: $0) }, width: 120)
                }
                .settingsGlyph("number.square")
                .infoTip(amdFlashActive
                    ? AppInfo.branded("Quantization for KV cache values. With the AMD Flash Attention kernel any standard value type (f16/q8_0/q4_0) runs on the GPU at full speed, including the fast long-prompt route. Quantizing values saves more memory; keeping them at f16 (with quantized keys) preserves more quality... both run equally fast.")
                    : AppInfo.branded("Quantization for KV cache values. ⚠️ On AMD GPUs (without the AMD Flash Attention kernel) this forces Flash Attention onto the CPU: generation drops ~3× (from ~50 to ~15-19 t/s on an 8B). Use only when you need huge context; otherwise keep f16 and quantize keys only."))
                if !turboKVIncompatible, let s = kvSuggestion, cacheTypeK != s.k || cacheTypeV != s.v {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppInfo.branded("Measured suggestion: \(s.k) keys, \(s.v) values"))
                                .font(.callout.weight(.medium))
                            Text(AppInfo.branded("Quality indistinguishable from f16, and 25% less cache than q8_0 on both."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button(AppInfo.branded("Apply")) { cacheTypeK = s.k; cacheTypeV = s.v }
                            .glassButton()
                            .controlSize(.small)
                            .help(AppInfo.branded("Sets keys to \(s.k) and values to \(s.v)."))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .glassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let reason = turboKVIncompatibleReason {
                    HStack(alignment: .center, spacing: 12) {
                        Label(AppInfo.branded(reason),
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if let s = kvSuggestion {
                            Spacer(minLength: 8)
                            Button(AppInfo.branded("Use \(s.k) / \(s.v)")) {
                                cacheTypeK = s.k; cacheTypeV = s.v
                            }
                            .glassButton()
                            .controlSize(.small)
                            .help(AppInfo.branded("Switches to a valid, measured combination."))
                        }
                    }
                } else if turboKVSelected {
                    Label(AppInfo.branded("Turbo on the keys is what costs quality, the more so the smaller the model. With keys at q8_0, values take Turbo4 with no appreciable loss at any size, and Turbo3 nearly so; Turbo on both is only worth it on large models."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(AppInfo.branded("Prompt cache reuse (fast)"), isOn: $cacheReuse)
                    .settingsGlyph("arrow.triangle.2.circlepath")
                    .infoTip(AppInfo.branded("When the prompt is rewritten/edited (coding assistants) or the reasoning is trimmed between turns, it reuses the cache by shifting it instead of reprocessing — much faster. It's an approximation: output stays coherent but can differ slightly from an exact recompute. Turn it off for identical, reproducible results."))
                Stepper(AppInfo.branded("CPU threads: \(threads)"),
                        value: $threads, in: 0...max(0, hardware.physicalCores))
                    .settingsGlyph("cpu")
                    .infoTip(AppInfo.branded("Threads for the CPU side (MoE experts, tokenization). Your machine has \(String(hardware.logicalCores)) threads; physical cores (\(String(hardware.physicalCores))) are usually optimal; more threads won't help if RAM bandwidth is the limit."))
                    .onAppear { if threads > hardware.physicalCores { threads = max(0, hardware.physicalCores) } }
                LabeledContent(AppInfo.branded("Standard Flash Attention (CPU)")) {
                    XeonDropdown(selection: $flashAttn, options: ["auto", "on", "off"].map { .init(value: $0, title: $0) }, width: 120)
                }
                .settingsGlyph("bolt.horizontal.circle")
                .disabled(amdFlashActive || kvNeedsFlashAttention)
                .infoTip(AppInfo.branded("Standard llama.cpp Flash Attention path. On AMD GPUs it falls back to CPU; it is forced to 'on' when KV is quantized. For GPU attention use the AMD kernel below."))
                if engineSelection.wrappedValue != "custom" {
                    Toggle(AppInfo.branded("AMD Flash Attention kernel (GPU)"), isOn: $faAmd)
                        .settingsGlyph("bolt.fill")
                        .infoTip(AppInfo.branded("Custom Metal kernel, on by default, that runs attention (prompt and generation) on the AMD GPU: standard heads 64/72/128/256/512 and TurboQuant padded heads 128/256/384/512/640. If you turn it off, quantized KV still requires Flash Attention but uses the standard CPU path."))
                    Label(amdFlashActive
                            ? AppInfo.branded("Using the AMD GPU kernel; Flash Attention is forced to 'on'.")
                            : kvNeedsFlashAttention
                              ? AppInfo.branded("Quantized KV requires Flash Attention: with the AMD kernel off, it uses standard FA on CPU.")
                              : AppInfo.branded("Standard Flash Attention runs on CPU on AMD GPUs; enable the AMD kernel to use the GPU."),
                          systemImage: amdFlashActive ? "bolt.fill" : "cpu")
                        .font(.caption).foregroundStyle(amdFlashActive ? .green : .secondary)
                }
                if !modelPath.isEmpty && ServerSettings.modelUsesMTP(at: modelPath) {
                    Label(AppInfo.branded("Automatic MTP active"),
                          systemImage: "hare.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .infoTip(AppInfo.branded("MTP turns on automatically whenever the GGUF includes the head, for both dense and MoE models."))
                }
                if engineSelection.wrappedValue != "custom" {
                    Toggle(AppInfo.branded("MoE expert prefetch (prompt)"), isOn: $prefetchExperts)
                        .settingsGlyph("square.stack.3d.down.forward")
                        .infoTip(AppInfo.branded("For MoE models with experts in RAM (ncmoe > 0): uploads expert weights to the GPU through a parallel Metal queue, overlapping the upload with compute. Measured 1.8×-4.4× prompt speed (35B, gemma-4-26B, gpt-oss) at no generation cost; the first prompt after loading the model is slightly slower while buffers warm up."))
                    if routerMode || ServerSettings.modelIsMoE(at: modelPath) {
                        LabeledContent(AppInfo.branded("Prompt micro-batch")) {
                            XeonDropdown(selection: $ubatch, options: ServerSettings.ubatchOptions.map {
                                .init(value: $0, title: ServerSettings.ubatchLabel($0, loc: loc))
                            })
                        }
                        .settingsGlyph("square.grid.3x3")
                        .infoTip(AppInfo.branded("How many prompt tokens the GPU processes at once. It only helps MoE models, and how much depends on where the experts live. With experts on the CPU every micro-batch uploads them over the bus, so a larger one pays that trip fewer times: measured on a Radeon RX 6700 XT, reading 2048 tokens goes from 475 to 886 tokens per second on a 35B, and from 546 to 1133 on a 30B. With the model whole on the card the gain is around 10%, the same on one GPU as split across several. Generation is unchanged in every case. In exchange it takes VRAM, around 0.5 GB per 512 tokens of micro-batch, so if you are tight you will have to lower the experts on CPU to make room."))
                    }
                }
                LabeledContent(AppInfo.branded("Concurrent requests")) {
                    XeonDropdown(selection: $parallelSlots, options: [
                        .init(value: 1, title: AppInfo.branded("1 (recommended)")),
                        .init(value: 2, title: "2"), .init(value: 4, title: "4"),
                        .init(value: 0, title: "Auto")
                    ])
                }
                .settingsGlyph("person.2")
                .infoTip(AppInfo.branded("How many requests the engine processes at once. With 1, requests queue instead of competing for the GPU, and a huge prompt interrupted by a client timeout (VS Code) resumes where it was on retry. Raise it only if several clients use the server at the same time."))
                if parallelSlots > 1 {
                    Toggle(AppInfo.branded("Separate context per request"), isOn: $separateKV)
                        .settingsGlyph("rectangle.split.2x1")
                        .infoTip(AppInfo.branded("Each simultaneous request gets its own share of the context (the context divided by the requests) instead of sharing it. Measured on a Radeon RX 6700 XT with several requests at once: 7 to 11% faster generation and 11 to 18% less wait with long prompts. In exchange, no conversation can grow past its share; off, the chat keeps its full window."))
                }
                Toggle(AppInfo.branded("Reasoning as plain text (external clients)"), isOn: $reasoningInline)
                    .settingsGlyph("brain")
                    .infoTip(AppInfo.branded("Sends the reasoning inline in the response (<think>…) instead of the separate reasoning_content field. Enable it if an external client (VS Code, plugins) appears stuck 'thinking' showing nothing. The in-app chat understands both formats."))
                LabeledContent(AppInfo.branded("Default reasoning")) {
                    XeonDropdown(selection: $serverDefaultReasoning, options: [
                        .init(value: "model", title: AppInfo.branded("Model default")),
                        .init(value: "off", title: AppInfo.branded("Off")),
                        .init(value: "low", title: AppInfo.branded("Low")),
                        .init(value: "medium", title: AppInfo.branded("Medium")),
                        .init(value: "high", title: AppInfo.branded("High")),
                    ])
                }
                .settingsGlyph("brain.head.profile")
                .infoTip(AppInfo.branded("Reasoning level for requests that do not choose one, such as those from VS Code or many agents. A request that sets it always wins. Levels only change anything on models whose template accepts them; Off works on every reasoning model."))
                LabeledContent(AppInfo.branded("Default response limit")) {
                    XeonDropdown(selection: $serverDefaultMaxTokens, options: [
                        .init(value: -1, title: AppInfo.branded("Same as the chat")),
                        .init(value: 0, title: AppInfo.branded("No limit")),
                        .init(value: 2048, title: "2K"), .init(value: 4096, title: "4K"),
                        .init(value: 8192, title: "8K"), .init(value: 16384, title: "16K"),
                        .init(value: 32768, title: "32K"),
                    ])
                }
                .settingsGlyph("text.append")
                .infoTip(AppInfo.branded("Response tokens for requests that do not set max_tokens, such as the web chat's or many apps'. It keeps a client without a limit from leaving the model reasoning or writing without end. “Same as the chat” uses the in-app chat's maximum."))
                Toggle(AppInfo.branded("Chat template (--jinja)"), isOn: $jinja)
                    .settingsGlyph("curlybraces")
                    .infoTip(AppInfo.branded("Uses the model's official chat template (message format, tools). Keep it on unless a specific model misbehaves."))
            }
            }

        }
        .formStyle(.grouped)
        .labeledContentStyle(SettingsLabeledContentStyle())
        .toggleStyle(SettingsCompactToggleStyle())
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity)
    }
}

/// Each appearance has one small shared bitmap. The selected 720 px image is
/// loaded lazily and reused by every guide, avoiding category-specific images.
struct SettingsGuideArtwork: View {
    @Environment(\.colorScheme) private var colorScheme
    private static let darkImage: NSImage? = Bundle.main
        .url(forResource: "settings-guide", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))
    private static let lightImage: NSImage? = Bundle.main
        .url(forResource: "settings-guide-light", withExtension: "jpg")
        .flatMap(NSImage.init(contentsOf:))

    private var image: NSImage? {
        colorScheme == .light ? (Self.lightImage ?? Self.darkImage) : Self.darkImage
    }

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                WorkspaceStyle.surface
            }
        }
        .accessibilityHidden(true)
        // scaledToFill overflows the frame and clipped() does not clip hit-testing,
        // so without this the artwork swallows clicks on the form beside it.
        .allowsHitTesting(false)
    }
}

// MARK: - InfoTip

/// A styled, pinnable explanation next to a setting, since the native `.help()`
/// tooltip cannot be styled.
struct InfoTip: View {
    let text: String
    /// When false (hover-reveal mode) the ⓘ is hidden until the host row is hovered
    /// or the popover is open — used outside Settings so the icon doesn't clutter.
    var forceVisible: Bool = true
    @State private var shown = false
    @State private var pinned = false
    @State private var pointerOnIcon = false
    @State private var hoverWork: DispatchWorkItem?

    private var visible: Bool { forceVisible || shown || pointerOnIcon }

    var body: some View {
        Image(systemName: "info.circle")
            .imageScale(.medium)
            .foregroundStyle(shown ? Color.accentColor : .secondary)
            .opacity(visible ? 1 : 0)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            // Hidden it still occupies the row, so let clicks reach the control
            // next to it. The tracker below keeps reporting hover regardless.
            .allowsHitTesting(visible)
            .background(
                HoverTracker { inside in
                    hoverWork?.cancel()
                    pointerOnIcon = inside
                    if inside {
                        let work = DispatchWorkItem { shown = true }
                        hoverWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                    } else if !pinned {
                        shown = false
                    }
                }
            )
            .onTapGesture {
                hoverWork?.cancel()
                pinned.toggle()
                shown = pinned
            }
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(width: 320)
                    .onHover { inside in
                        hoverWork?.cancel()
                        if !inside && !pinned { shown = false }
                    }
                    .onDisappear { pinned = false }
            }
            .accessibilityLabel(Text(text))
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        hoverWork?.cancel()
        let work = DispatchWorkItem {
            if !pinned { shown = false }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

extension View {
    /// Drop-in replacement for `.help(_:)`. Pass `revealOnHover: false` where the ⓘ
    /// must stay visible at rest.
    func infoTip(_ text: String, revealOnHover: Bool = true) -> some View {
        InfoTipRow(text: text, revealOnHover: revealOnHover) { self }
    }
}

/// Hosts a view plus its ⓘ, tracking row hover so the icon can be revealed on demand.
private struct InfoTipRow<Content: View>: View {
    let text: String
    let revealOnHover: Bool
    @ViewBuilder var content: Content
    @State private var hovering = false
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        HStack(spacing: 8) {
            content
            InfoTip(text: text, forceVisible: !revealOnHover || hovering)
        }
        // In a background layer that never changes: tracking the row would reinstall
        // the tracking area as the ⓘ appears, and AppKit answers that with an exit.
        .background(
            HoverTracker { inside in
                hovering = inside
            }
        )
    }
}

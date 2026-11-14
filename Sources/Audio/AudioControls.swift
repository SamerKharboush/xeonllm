// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct AudioControls: View {
    @ObservedObject var studio: AudioStudioController
    @EnvironmentObject private var loc: Localizer
    @EnvironmentObject private var models: ModelStore
    @EnvironmentObject private var server: ServerController
    @EnvironmentObject private var control: ControlPanelState
    @Environment(\.openWindow) private var openWindow

    @AppStorage(SettingsKeys.whisperModel) private var whisperModelID = WhisperModel.recommendedID
    @AppStorage(SettingsKeys.gpuIndex) private var gpuIndex = -1
    @AppStorage(SettingsKeys.whisperLoadPolicy) private var loadPolicyRaw = WhisperLoadPolicy.onDemand.rawValue
    @AppStorage(SettingsKeys.audioOperation) private var operationRaw = AudioStudioOperation.transcribe.rawValue
    @AppStorage(SettingsKeys.audioLanguage) private var language = "auto"
    @AppStorage(SettingsKeys.audioTargetLanguage) private var targetLanguage = "Spanish"
    @AppStorage(SettingsKeys.port) private var port = 8080
    @AppStorage(SettingsKeys.routerMode) private var routerMode = false
    @AppStorage(SettingsKeys.chatSelectedModel) private var routerModel = ""
    @AppStorage(SettingsKeys.audioTranslationModel) private var translationModel = ""
    @AppStorage(SettingsKeys.audioGlossary) private var glossary = ""
    @State private var usesCustomTargetLanguage = false
    @FocusState private var customTargetLanguageFocused: Bool
    @AppStorage(SettingsKeys.modelPath) private var modelPath = ""
    @AppStorage(SettingsKeys.audioVADMode) private var vadModeRaw = AudioVADMode.defaultMode.rawValue
    @AppStorage(SettingsKeys.ncmoe) private var ncmoe = 0

    private var model: WhisperModel { WhisperModel.model(id: whisperModelID) }
    private var operation: AudioStudioOperation {
        AudioStudioOperation(rawValue: operationRaw) ?? .transcribe
    }
    private var vadMode: AudioVADMode {
        AudioVADMode(rawValue: vadModeRaw) ?? .defaultMode
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceCard
                    Divider()
                    taskCard
                    Divider()
                    modelCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            Divider()
            actionCard
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 300)
        .buttonStyle(GlassPillButtonStyle())
        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        .onAppear {
            seedTargetLanguageIfNeeded()
            syncCustomTargetLanguage()
        }
        .onChange(of: operationRaw) { _, _ in
            seedTargetLanguageIfNeeded()
        }
    }

    private var sourceCard: some View {
        AudioSidebarSection(title: AppInfo.branded("File"), icon: "doc") {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: pickMedia) {
                    Label(AppInfo.branded("Choose audio or video…"),
                          systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .disabled(studio.isBusy)
                .help(AppInfo.branded("Accepts audio and video; XeonLLM extracts audio locally without changing the original."))

                if let source = studio.sourceURL {
                    Text(source.lastPathComponent)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Label(sourceSummary, systemImage: studio.isVideo ? "film" : "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(AppInfo.branded("You can also drop it onto the preview area."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var taskCard: some View {
        AudioSidebarSection(title: AppInfo.branded("Result"), icon: "captions.bubble") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppInfo.branded("Operation")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $operationRaw) {
                        Text(AppInfo.branded("Transcribe")).tag(AudioStudioOperation.transcribe.rawValue)
                        Text(AppInfo.branded("Translate to English")).tag(AudioStudioOperation.translateEnglish.rawValue)
                        Text(AppInfo.branded("Translate with chat")).tag(AudioStudioOperation.translateLocal.rawValue)
                    }
                    .labelsHidden()
                    .help(AppInfo.branded("Whisper transcribes or translates directly to English; other languages use the local chat model without changing timestamps."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppInfo.branded("Spoken language")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $language) {
                        ForEach(WhisperLanguage.common) { item in
                            Text(verbatim: item.name).tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .help(AppInfo.branded("Choosing the language improves accuracy; Automatic is useful when it is unknown."))
                }

                if operation == .translateLocal {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInfo.branded("Target language")).font(.caption).foregroundStyle(.secondary)
                        XeonDropdown(selection: targetLanguageSelection,
                                     options: targetLanguageOptions,
                                     placeholder: AppInfo.branded("Choose language"),
                                     width: 172,
                                     maximumListHeight: 320,
                                     listWidth: 260)
                    }
                    .help(AppInfo.branded("Choose the final language, such as Spanish, Korean, or French."))

                    if usesCustomTargetLanguage {
                        TextField(AppInfo.branded("Enter another language…"),
                                  text: $targetLanguage)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .workspaceFieldSurface()
                            .focused($customTargetLanguageFocused)
                            .onSubmit { commitCustomTargetLanguage() }
                    }
                    chatRequirement
                    translationModelControl
                    TextField(AppInfo.branded("Glossary: term = translation"),
                              text: $glossary, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .workspaceFieldSurface()
                        .lineLimit(2...5)
                        .help(AppInfo.branded("Pins names, brands and terminology, one per line, to keep them consistent throughout the video."))
                } else if operation == .translateEnglish {
                    Label(AppInfo.branded("Whisper's built-in translation always produces English."),
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var translationModelControl: some View {
        if routerMode {
            Picker(AppInfo.branded("Translation model"), selection: $translationModel) {
                ForEach(models.models) { item in
                    Text(ModelName.forPath(item.url.path).title)
                        .tag(ServerSettings.routerAlias(for: item.url.path))
                }
            }
            .help(AppInfo.branded("Choose the router model that will translate the subtitles."))
            .task { selectDefaultTranslationModel() }
            if let selected = models.models.first(where: {
                ServerSettings.routerAlias(for: $0.url.path) == translationModel
            }), selected.sizeBytes < 1_500_000_000 {
                Label(AppInfo.branded("A larger model usually preserves names, context, and JSON better in long videos."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if models.models.isEmpty {
            LabeledContent(AppInfo.branded("Translation model")) {
                Text(AppInfo.branded("No models")).lineLimit(1)
            }
            downloadModelButton
        } else {
            Picker(AppInfo.branded("Translation model"), selection: $modelPath) {
                Text(AppInfo.branded("No model")).tag("")
                ForEach(ModelFamilyGroup.grouped(models.models)) { group in
                    Section(group.isOther ? AppInfo.branded("Others") : group.family) {
                        ForEach(group.models) {
                            Text(ModelName.forPath($0.url.path).display)
                                .tag($0.url.path)
                        }
                    }
                }
            }
            .disabled(server.state == .running || server.state == .starting)
            // Selecting a model also seeds ncmoe so it never carries over stale
            // from the previous one, same as the dashboard picker.
            .onChange(of: modelPath) { _, path in
                ncmoe = Estimator.ncmoeForSelection(path: path, models: models.models)
            }
            .help(AppInfo.branded("Model that will translate the segments; it is the same one Chat uses. Stop the engine to change it."))
        }
    }

    private var downloadModelButton: some View {
        Button(AppInfo.branded("Download a model…"),
               systemImage: "arrow.down.circle", action: openModelCatalog)
        .controlSize(.small)
        .help(AppInfo.branded("Opens the catalog to download a language model, which translating requires."))
    }

    private func openModelCatalog() {
        control.section = .models
        openWindow(id: "control")
    }

    @ViewBuilder
    private var chatRequirement: some View {
        if server.state == .running {
            Label(AppInfo.branded("Chat is ready to translate the segments."), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Label(AppInfo.branded("This option needs the chat engine running."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if models.models.isEmpty {
                    downloadModelButton
                } else if modelPath.isEmpty {
                    Text(AppInfo.branded("Pick a translation model below to start it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if server.state == .stopped {
                    Button(AppInfo.branded("Start chat engine"),
                           systemImage: "play.fill") {
                        server.start(.fromDefaults())
                    }
                    .controlSize(.small)
                    .help(AppInfo.branded("Loads the configured model to translate after transcription."))
                }
            }
        }
    }

    private var modelCard: some View {
        AudioSidebarSection(title: "Whisper.cpp · GPU", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppInfo.branded("Model")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $whisperModelID) {
                        ForEach(WhisperModel.catalog) { item in
                            Text(verbatim: "\(item.name) · \(item.sizeMB) MB").tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .help(AppInfo.branded("Turbo offers the best balance; Large v3 prioritizes accuracy."))
                }

                Text(verbatim: model.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !models.whisperModelInstalled(model) {
                    downloadControl
                } else {
                    Label(AppInfo.branded("Model installed"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Divider()
                vadControl

                if hardware.gpus.count > 1 {
                    Picker("GPU", selection: $gpuIndex) {
                        Text(AppInfo.branded("Automatic")).tag(-1)
                        ForEach(Array(hardware.gpus.enumerated()), id: \.offset) { index, gpu in
                            Text(gpu.name).tag(index)
                        }
                    }
                    .help(AppInfo.branded("Select the AMD GPU that runs Whisper."))
                }
            }
        }
    }

    @ViewBuilder
    private var vadControl: some View {
        AudioVADCalibrationView()
        if vadMode.isEnabled && !models.whisperVADInstalled,
           let download = models.whisperVADDownload() {
            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: download.progress)
                if let error = download.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button(AppInfo.branded("Retry voice detector"),
                           systemImage: "arrow.clockwise") {
                        models.retryWhisperVADDownload(download)
                    }
                    .help(AppInfo.branded("Restarts the Silero VAD download."))
                } else if download.phase == .paused {
                    Button(AppInfo.branded("Resume voice detector"),
                           systemImage: "arrow.down.circle", action: download.resume)
                        .help(AppInfo.branded("Continues the Silero VAD download."))
                } else {
                    Text(AppInfo.branded("Downloading voice detector…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if vadMode.isEnabled && !models.whisperVADInstalled {
            VStack(alignment: .leading, spacing: 6) {
                Label(AppInfo.branded("Audio needs silence detection"),
                      systemImage: "waveform.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(AppInfo.branded("Download Silero VAD · 864 KB"),
                       systemImage: "arrow.down.circle.fill", action: models.downloadWhisperVAD)
                    .help(AppInfo.branded("Downloads the detector that separates speech and silence before running Whisper."))
            }
        }
        if vadMode.isEnabled && models.whisperVADInstalled && studio.sourceURL != nil {
            Button(AppInfo.branded("Preview VAD on 30 seconds"),
                   systemImage: "waveform.badge.magnifyingglass", action: previewVAD)
                .disabled(studio.isBusy)
                .help(AppInfo.branded("Analyzes a sample without replacing the existing transcript."))
            Text(AppInfo.branded("Change the mode or profile and repeat the preview to compare results."))
                .font(.caption)
                .foregroundStyle(.secondary)
            vadPreviewResult
        }
    }

    @ViewBuilder
    private var vadPreviewResult: some View {
        switch studio.vadPreviewState {
        case .idle:
            EmptyView()
        case .running:
            ProgressView(AppInfo.branded("Analyzing sample…"))
                .controlSize(.small)
        case .ready(let count, let speech, let sample):
            VStack(alignment: .leading, spacing: 4) {
                Label(AppInfo.branded("\(count) segments · \(Int(speech.rounded())) s of speech in \(Int(sample.rounded())) s"),
                      systemImage: count > 0 ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(count > 0 ? Color.green : Color.orange)
                if !studio.vadPreviewCues.isEmpty {
                    Text(studio.vadPreviewCues.prefix(5).map {
                        "\(MediaTime.compact($0.start))–\(MediaTime.compact($0.end))"
                    }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(AppInfo.branded("Intervals the current configuration considers speech."))
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        if let download = models.whisperDownload(model) {
            VStack(alignment: .leading, spacing: 5) {
                ProgressView(value: download.progress)
                if let error = download.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button(AppInfo.branded("Retry"), systemImage: "arrow.clockwise") {
                        models.retryWhisperDownload(download)
                    }
                    .help(AppInfo.branded("Restarts the model download."))
                } else if download.phase == .paused {
                    Button(AppInfo.branded("Resume"), systemImage: "arrow.down.circle",
                           action: download.resume)
                        .help(AppInfo.branded("Continues the download from where it paused."))
                } else {
                    Text(AppInfo.branded("Downloading \(model.name)…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Button(AppInfo.branded("Download \(model.name)"),
                   systemImage: "arrow.down.circle.fill") {
                models.downloadWhisperModel(model)
            }
            .glassButton(prominent: true)
            .help(AppInfo.branded("Downloads the model into the local Whisper model folder."))
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            if studio.isBusy {
                ProgressView(value: studio.progress)
                HStack {
                    Label(stageText, systemImage: stageIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let remaining = studio.remaining {
                        Text(AppInfo.branded("~\(MediaTime.compact(remaining)) left"))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button(server.state == .running
                       ? AppInfo.branded("Stop both engines")
                       : AppInfo.branded("Cancel"),
                       systemImage: "stop.fill", action: stopProcessing)
                    .frame(maxWidth: .infinity)
                    .help(AppInfo.branded("Cancels the job and frees Whisper; if chat is active, it stops that too."))
            } else {
                Button(action: startProcessing) {
                    Label(actionTitle, systemImage: operation == .transcribe ? "captions.bubble.fill" : "character.bubble.fill")
                        .frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true)
                .controlSize(.large)
                .disabled(!canStart)
                .help(AppInfo.branded("Processes the file locally and preserves exportable timestamps."))
                if !studio.originalCues.isEmpty && operation == .translateLocal {
                    Button(AppInfo.branded("Retry translation only"),
                           systemImage: "arrow.triangle.2.circlepath", action: retryTranslation)
                        .disabled(!canRetryTranslation)
                        .help(AppInfo.branded("Keeps the Whisper transcript and runs only Chat again."))
                }
            }

            if case .failed(let message) = studio.stage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var canStart: Bool {
        studio.sourceURL != nil && models.whisperModelInstalled(model)
            && (!vadMode.isEnabled || models.whisperVADInstalled)
            && (operation != .translateLocal || canUseTranslationServer)
    }

    private var canRetryTranslation: Bool {
        studio.canRetryTranslation && canUseTranslationServer
    }

    private var canUseTranslationServer: Bool {
        server.state == .running
            && !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionTitle: String {
        switch operation {
        case .transcribe: AppInfo.branded("Create subtitles")
        case .translateEnglish: AppInfo.branded("Transcribe and translate")
        case .translateLocal: AppInfo.branded("Transcribe and translate")
        }
    }

    private var stageText: String {
        switch studio.stage {
        case .preparing: AppInfo.branded("Preparing audio…")
        case .analyzingVAD: AppInfo.branded("Analyzing VAD…")
        case .transcribing: AppInfo.branded("Whisper is transcribing…")
        case .translating:
            AppInfo.branded("Translating batch \(studio.translatedBatchCount + 1) of \(max(1, studio.translationBatchCount))…")
        default: ""
        }
    }

    private var stageIcon: String {
        switch studio.stage {
        case .preparing: "waveform.badge.magnifyingglass"
        case .analyzingVAD: "waveform.badge.magnifyingglass"
        case .transcribing: "captions.bubble"
        case .translating: "character.bubble"
        default: "circle"
        }
    }

    private var sourceSummary: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(studio.fileSize), countStyle: .file)
        guard studio.duration > 0 else { return size }
        return "\(MediaTime.compact(studio.duration)) · \(size)"
    }

    private func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        studio.select(url)
    }

    private func startProcessing() {
        studio.start(
            modelURL: model.url(in: models.whisperDirectory), vadModelURL: models.whisperVADURL,
            vadConfiguration: AudioVADPreferences.configuration(), gpuIndex: gpuIndex,
            language: language, operation: operation, targetLanguage: targetLanguage,
            chatPort: port, routerModel: selectedTranslationModel, glossary: glossary,
            restorePersistentModel: loadPolicyRaw == WhisperLoadPolicy.alwaysLoaded.rawValue && server.state == .running
        )
    }

    private var selectedTranslationModel: String? {
        guard routerMode else { return nil }
        return translationModel.isEmpty ? (routerModel.isEmpty ? nil : routerModel) : translationModel
    }

    private func selectDefaultTranslationModel() {
        guard translationModel.isEmpty else { return }
        translationModel = routerModel.isEmpty
            ? models.models.first.map { ServerSettings.routerAlias(for: $0.url.path) } ?? ""
            : routerModel
    }

    private func seedTargetLanguageIfNeeded() {
        guard operation == .translateLocal else { return }
        let current = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            targetLanguage = TranslationLanguageOption.defaultTarget
        } else if let match = TranslationLanguageOption.matching(current), match.value != targetLanguage {
            targetLanguage = match.value
        }
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            if usesCustomTargetLanguage {
                return TranslationLanguageOption.customValue
            }
            return TranslationLanguageOption.matching(targetLanguage)?.value
                ?? TranslationLanguageOption.customValue
        } set: { selection in
            if selection == TranslationLanguageOption.customValue {
                usesCustomTargetLanguage = true
                targetLanguage = ""
                Task { @MainActor in
                    await Task.yield()
                    customTargetLanguageFocused = true
                }
            } else {
                usesCustomTargetLanguage = false
                customTargetLanguageFocused = false
                targetLanguage = selection
            }
        }
    }

    private var targetLanguageOptions: [XeonDropdown<String>.Option] {
        [
            .init(value: TranslationLanguageOption.customValue,
                  title: AppInfo.branded("Other…"),
                  systemImage: "ellipsis")
        ] + TranslationLanguageOption.all.map {
            .init(value: $0.value, title: $0.value)
        }
    }

    private func syncCustomTargetLanguage() {
        let current = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        usesCustomTargetLanguage = TranslationLanguageOption.matching(current) == nil
    }

    private func commitCustomTargetLanguage() {
        let current = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        targetLanguage = current
        if let match = TranslationLanguageOption.fuzzyMatch(current, minimumSimilarity: 0.80) {
            targetLanguage = match.value
            usesCustomTargetLanguage = false
        }
        customTargetLanguageFocused = false
    }

    private func retryTranslation() {
        studio.retryTranslation(targetLanguage: targetLanguage, port: port,
                                routerModel: selectedTranslationModel, glossary: glossary)
    }

    private func previewVAD() {
        studio.previewVAD(
            modelURL: model.url(in: models.whisperDirectory),
            vadModelURL: models.whisperVADURL,
            vadConfiguration: AudioVADPreferences.configuration(),
            gpuIndex: gpuIndex, language: language
        )
    }

    private func stopProcessing() {
        if server.state == .running || server.state == .starting {
            server.stop()
        } else {
            studio.cancel()
        }
    }
}

private struct TranslationLanguageOption: Identifiable {
    let id: String
    let value: String

    static let all: [TranslationLanguageOption] = {
        let locale = Locale(identifier: "en")
        var seen = Set<String>()
        return commonLanguageCodes.compactMap { code -> TranslationLanguageOption? in
            guard let english = locale.localizedString(forLanguageCode: code),
                  !english.isEmpty,
                  seen.insert(english.lowercased()).inserted else { return nil }
            return TranslationLanguageOption(
                id: code, value: english.capitalized(with: locale))
        }
        .sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }()

    /// Spanish is the default translation target: the interpreter's own speech.
    static let defaultTarget = all.first(where: { $0.id == "es" })?.value ?? "Spanish"

    /// Everyday translation targets. Less common and constructed languages stay
    /// available through “Other” without overwhelming the dropdown.
    private static let commonLanguageCodes = [
        "af", "sq", "de", "am", "ar", "hy", "az", "bn", "be", "my", "bs", "bg",
        "ca", "cs", "zh", "ko", "hr", "da", "sk", "sl", "es", "et", "eu", "fi",
        "fil", "fr", "cy", "ka", "el", "gu", "he", "hi", "hu", "id", "en", "is",
        "it", "ja", "kn", "kk", "km", "lo", "lv", "lt", "mk", "ms", "ml", "mr",
        "mn", "ne", "nl", "no", "fa", "pl", "pt", "pa", "ro", "ru", "sr", "si",
        "sv", "sw", "ta", "te", "th", "tr", "uk", "ur", "uz", "vi"
    ]

    static let customValue = "__xeonllm_custom_language__"

    static func matching(_ value: String) -> TranslationLanguageOption? {
        all.first {
            $0.id.caseInsensitiveCompare(value) == .orderedSame
                || $0.value.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    static func fuzzyMatch(_ value: String, minimumSimilarity: Double) -> TranslationLanguageOption? {
        let input = normalized(value)
        // Very short names are too ambiguous while typing (for example Ga, Ewe,
        // or Fon), so they must be chosen explicitly from the dropdown.
        guard input.count >= 4 else { return nil }

        return all
            .map { ($0, similarity(input, normalized($0.value))) }
            .filter { $0.1 >= minimumSimilarity }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .filter { $0.isLetter }
            .lowercased()
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    substitution
                )
            }
            previous = current
        }

        let distance = previous[right.count]
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }
}

/// The same flat hierarchy used by the Images and Video sidebars. Sections keep
/// their labels and spacing without adding a separate opaque card behind each one.
private struct AudioSidebarSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

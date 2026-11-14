// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SpeechModelsSettingsSection: View {
    @EnvironmentObject private var loc: Localizer
    @EnvironmentObject private var models: ModelStore
    @AppStorage(SettingsKeys.whisperModel) private var selectedID = WhisperModel.recommendedID
    @AppStorage(SettingsKeys.speechInputMethod) private var methodRaw = ""
    @AppStorage(SettingsKeys.whisperLoadPolicy) private var loadPolicyRaw = WhisperLoadPolicy.onDemand.rawValue

    private var selected: WhisperModel { WhisperModel.model(id: selectedID) }

    var body: some View {
        // The panel header above already names this category.
        Section {
            LabeledContent(AppInfo.branded("Microphone method")) {
                XeonDropdown(selection: $methodRaw, options: [
                    .init(value: "", title: AppInfo.branded("Choose…")),
                    .init(value: SpeechInputMethod.apple.rawValue, title: AppInfo.branded("Apple Dictation")),
                    .init(value: SpeechInputMethod.whisper.rawValue, title: "Whisper.cpp · GPU"),
                ])
            }
            .settingsGlyph("mic")
            .help(AppInfo.branded("Choose macOS dictation or GPU-accelerated Whisper.cpp."))

            if methodRaw == SpeechInputMethod.apple.rawValue {
                Text(AppInfo.branded("Live dictation with macOS's built-in service. It reserves no VRAM."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if methodRaw != SpeechInputMethod.apple.rawValue {
                LabeledContent(AppInfo.branded("Whisper loading")) {
                    XeonDropdown(selection: $loadPolicyRaw, options: [
                        .init(value: WhisperLoadPolicy.onDemand.rawValue, title: AppInfo.branded("On demand")),
                        .init(value: WhisperLoadPolicy.alwaysLoaded.rawValue, title: AppInfo.branded("Always loaded")),
                    ])
                }
                .settingsGlyph("memorychip")
                .help(AppInfo.branded("On demand releases VRAM; Always loaded reduces the wait for the next dictation."))

                Text(loadPolicyRaw == WhisperLoadPolicy.alwaysLoaded.rawValue
                     ? AppInfo.branded("Keeps the model in VRAM so the next dictation starts sooner.")
                     : AppInfo.branded("Releases the model and its VRAM after each transcription."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            LabeledContent(AppInfo.branded("Whisper model")) {
                XeonDropdown(selection: $selectedID, options: WhisperModel.catalog.map {
                    .init(value: $0.id, title: label(for: $0))
                }, width: 320)
            }
            .settingsGlyph("waveform")
            .help(AppInfo.branded("Choose the balance between speed, VRAM use, and accuracy."))

            LabeledContent(AppInfo.branded("Profile")) {
                Text(verbatim: selected.detail)
                    .foregroundStyle(.secondary)
            }
            .settingsGlyph("info.circle")

            if models.whisperModelInstalled(selected) {
                Label(AppInfo.branded("Installed and ready for microphone, audio, and video"),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if let download = models.whisperDownload(selected) {
                DownloadRow(item: download)
            } else {
                Button {
                    models.downloadWhisperModel(selected)
                } label: {
                    Label(AppInfo.branded("Download \(selected.name) (\(selected.sizeMB) MB)"),
                          systemImage: "arrow.down.circle")
                }
                .help(AppInfo.branded("Downloads the selected model for microphone, audio, and video."))
            }

            Text(AppInfo.branded("The model downloads on demand. Audio and video are transcribed locally on the GPU and passed to chat as text."))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func label(for model: WhisperModel) -> String {
        let badge: String
        switch model.tier {
        case .fast: badge = AppInfo.branded("Fast")
        case .recommended: badge = AppInfo.branded("Recommended")
        case .maximum: badge = AppInfo.branded("Maximum accuracy")
        case .advanced: badge = AppInfo.branded("Advanced")
        }
        return "\(model.name) · \(model.sizeMB) MB · \(badge)"
    }
}

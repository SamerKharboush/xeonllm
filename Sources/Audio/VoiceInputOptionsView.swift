// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct VoiceInputOptionsView: View {
    @EnvironmentObject private var loc: Localizer
    @EnvironmentObject private var models: ModelStore
    @Binding var methodRaw: String
    @Binding var loadPolicyRaw: String
    @Binding var whisperModelID: String
    let dismiss: () -> Void

    private var selectedModel: WhisperModel { WhisperModel.model(id: whisperModelID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppInfo.branded("Voice input"))
                .font(.headline)

            Button {
                methodRaw = SpeechInputMethod.apple.rawValue
            } label: {
                methodLabel(
                    title: AppInfo.branded("Apple Dictation"),
                    detail: AppInfo.branded("Live · no VRAM reserved"),
                    systemImage: "apple.logo",
                    selected: methodRaw == SpeechInputMethod.apple.rawValue)
            }
            .buttonStyle(.plain)
            .help(AppInfo.branded("Uses macOS built-in dictation without loading a model on the GPU."))

            Button {
                methodRaw = SpeechInputMethod.whisper.rawValue
            } label: {
                methodLabel(
                    title: "Whisper.cpp · GPU",
                    detail: AppInfo.branded("Private · multilingual · Radeon"),
                    systemImage: "waveform.badge.mic",
                    selected: methodRaw == SpeechInputMethod.whisper.rawValue)
            }
            .buttonStyle(.plain)
            .help(AppInfo.branded("Transcribes locally with Whisper.cpp on the AMD GPU."))

            if methodRaw == SpeechInputMethod.whisper.rawValue {
                Divider()
                Picker(AppInfo.branded("Model"), selection: $whisperModelID) {
                    ForEach(WhisperModel.catalog) { model in
                        Text("\(model.name) · \(model.sizeMB) MB").tag(model.id)
                    }
                }
                .help(AppInfo.branded("Choose the balance between speed, memory, and accuracy."))
                Picker(AppInfo.branded("Loading"), selection: $loadPolicyRaw) {
                    Text(AppInfo.branded("On demand")).tag(WhisperLoadPolicy.onDemand.rawValue)
                    Text(AppInfo.branded("Always loaded")).tag(WhisperLoadPolicy.alwaysLoaded.rawValue)
                }
                .help(AppInfo.branded("On demand releases VRAM; Always loaded starts dictation faster."))

                if models.whisperModelInstalled(selectedModel) {
                    Label(AppInfo.branded("Model installed"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let download = models.whisperDownload(selectedModel) {
                    DownloadRow(item: download)
                } else {
                    Button {
                        models.downloadWhisperModel(selectedModel)
                    } label: {
                        Label(AppInfo.branded("Download \(selectedModel.name)"),
                              systemImage: "arrow.down.circle")
                    }
                    .help(AppInfo.branded("Downloads this Whisper model to the Mac."))
                }
            }

            HStack {
                Spacer()
                Button(AppInfo.branded("Done"), action: dismiss)
                    .keyboardShortcut(.defaultAction)
                    .disabled(methodRaw.isEmpty)
                    .help(AppInfo.branded("Saves the selected voice input method."))
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func methodLabel(title: String, detail: String,
                             systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

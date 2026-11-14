// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

struct AudioCanvas: View {
    @ObservedObject var studio: AudioStudioController
    @EnvironmentObject private var loc: Localizer
    @AppStorage(SettingsKeys.audioExportFormat) private var exportFormatRaw = AudioExportFormat.srt.rawValue
    @AppStorage(SettingsKeys.audioExportTrack) private var exportTrackRaw = AudioExportTrack.translated.rawValue
    @AppStorage(SettingsKeys.audioTranscriptMode) private var transcriptModeRaw = AudioTranscriptMode.original.rawValue
    @AppStorage(SettingsKeys.audioTargetLanguage) private var targetLanguage = "Spanish"
    @AppStorage(SettingsKeys.audioGlossary) private var glossary = ""
    @AppStorage(SettingsKeys.audioTranslationModel) private var translationModel = ""
    @AppStorage(SettingsKeys.audioFollowTranscript) private var followTranscript = true
    @StateObject private var videoExporter = SubtitleVideoExporter()
    @State private var dropTargeted = false
    @State private var editing = false
    @State private var exportError = ""
    @State private var showExportError = false
    @State private var stylingSubtitles = false

    private var exportFormat: AudioExportFormat {
        AudioExportFormat(rawValue: exportFormatRaw) ?? .srt
    }
    private var exportTrack: AudioExportTrack {
        AudioExportTrack(rawValue: exportTrackRaw) ?? .translated
    }

    var body: some View {
        Group {
            if studio.sourceURL == nil {
                emptyDropZone
            } else {
                GeometryReader { geometry in
                    let showsTools = geometry.size.width >= 760
                    HStack(alignment: .top, spacing: 14) {
                        mainWorkspace(showInlineTools: !showsTools)
                        if showsTools {
                            toolsPanel
                                .frame(width: min(270, max(230, geometry.size.width * 0.28)))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .buttonStyle(GlassPillButtonStyle())
        .background(dropTargeted ? Color.appAccent.opacity(0.08) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, Self.accepts(url), !studio.isBusy else { return false }
            studio.select(url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(AppInfo.branded("Could not export"),
               isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
        .onChange(of: transcriptModeRaw) { _, value in
            studio.setTranscriptMode(AudioTranscriptMode(rawValue: value) ?? .original)
        }
        .onChange(of: studio.hasTranslation) { _, available in
            guard available else { return }
            let preferred = AudioTranscriptMode(rawValue: transcriptModeRaw) ?? .bilingual
            studio.setTranscriptMode(preferred == .original ? .bilingual : preferred)
            transcriptModeRaw = studio.transcriptMode.rawValue
        }
        .onChange(of: videoExporter.error) { _, message in
            guard let message else { return }
            exportError = message
            showExportError = true
        }
        .onChange(of: videoExporter.completedURL) { _, url in
            guard let url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .sheet(isPresented: $stylingSubtitles) {
            SubtitleStyleSheet(sourceURL: studio.sourceURL,
                               cues: studio.exportCues(for: exportTrack))
                .environmentObject(loc)
        }
    }

    private var emptyDropZone: some View {
        ContentUnavailableView {
            Label(AppInfo.branded("Audio and subtitles"),
                  systemImage: "waveform.and.mic")
        } description: {
            Text(AppInfo.branded("Drop a movie, recording, or audio track here to transcribe it locally on the GPU."))
        } actions: {
            Button(AppInfo.branded("Choose file…"),
                   systemImage: "folder", action: pickMedia)
                .glassButton(prominent: true)
                .controlSize(.large)
                .help(AppInfo.branded("Select an audio or video file from your Mac."))
            Button(AppInfo.branded("Open project…"),
                   systemImage: "folder.badge.gearshape", action: openProject)
                .help(AppInfo.branded("Opens a saved transcript without processing it again."))
            if studio.hasRecoveryProject {
                Button(AppInfo.branded("Recover last work"),
                       systemImage: "clock.arrow.circlepath", action: recoverProject)
                    .help(AppInfo.branded("Restores the last automatically saved work."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }

    private func mainWorkspace(showInlineTools: Bool) -> some View {
        VStack(spacing: 14) {
            AudioMediaPreview(studio: studio)
                .padding(14)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))

            VStack(spacing: 0) {
                resultHeader(showInlineTools: showInlineTools)
                Divider()
                SubtitlePreview(studio: studio, followPlayback: $followTranscript,
                                editing: editing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultHeader(showInlineTools: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.branded("Transcript"))
                        .font(.headline)
                    if !studio.cues.isEmpty {
                        Text(resultSummary).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if studio.hasTranslation {
                    GlassSegmentedControl(selection: $transcriptModeRaw, segments: [
                        .init(value: AudioTranscriptMode.original.rawValue, title: AppInfo.branded("Original")),
                        .init(value: AudioTranscriptMode.translated.rawValue, title: AppInfo.branded("Translation")),
                        .init(value: AudioTranscriptMode.bilingual.rawValue, title: AppInfo.branded("Both")),
                    ])
                }
                if showInlineTools, !studio.cues.isEmpty {
                    inlineActions
                } else if showInlineTools {
                    projectMenu
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46, alignment: .leading)
            if videoExporter.isExporting {
                Divider()
                AudioExportProgressBar(exporter: videoExporter)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: videoExporter.isExporting ? 78 : 46, alignment: .topLeading)
    }

    private var inlineActions: some View {
        HStack(spacing: 8) {
            projectMenu
            Toggle(isOn: $followTranscript) {
                Label(AppInfo.branded("Follow playback"), systemImage: "location.fill")
                    .labelStyle(.iconOnly)
            }
                .toggleStyle(.button)
                .iconHelp(AppInfo.branded("Follow playback"))
            Toggle(isOn: $editing) {
                Label(AppInfo.branded("Edit segments"), systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
                .toggleStyle(.button)
                .iconHelp(AppInfo.branded("Edit segments"))
            Button(AppInfo.branded("Copy text"), systemImage: "doc.on.doc", action: copyText)
                .help(AppInfo.branded("Copies the text without timestamps."))
                .labelStyle(.iconOnly)
                .buttonStyle(GlassIconButtonStyle())
                .iconHelp(AppInfo.branded("Copy text"))
            exportMenu
        }
    }

    private var projectMenu: some View {
        Menu {
            Button(AppInfo.branded("Open project…"), systemImage: "folder", action: openProject)
            Button(AppInfo.branded("Save project…"), systemImage: "square.and.arrow.down", action: saveProject)
                .help(AppInfo.branded("Saves the transcript, translation and glossary to restore them without reprocessing."))
                .disabled(studio.originalCues.isEmpty)
            if studio.hasRecoveryProject {
                Button(AppInfo.branded("Recover last work"),
                       systemImage: "clock.arrow.circlepath", action: recoverProject)
            }
        } label: {
            Label(AppInfo.branded("Project"), systemImage: "folder.badge.gearshape")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .iconHelp(AppInfo.branded("Project"))
    }

    private var exportMenu: some View {
        Menu {
            exportMenuContent
        } label: {
            Label(AppInfo.branded("Export"), systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .iconHelp(AppInfo.branded("Export"))
    }

    @ViewBuilder private var exportMenuContent: some View {
        Picker(AppInfo.branded("Format"), selection: $exportFormatRaw) {
            ForEach(AudioExportFormat.allCases) { Text($0.rawValue.uppercased()).tag($0.rawValue) }
        }
        Picker(AppInfo.branded("Content"), selection: $exportTrackRaw) {
            Text(AppInfo.branded("Original")).tag(AudioExportTrack.original.rawValue)
            Text(AppInfo.branded("Translation")).tag(AudioExportTrack.translated.rawValue)
            Text(AppInfo.branded("Bilingual")).tag(AudioExportTrack.bilingual.rawValue)
        }
        Divider()
        Button(AppInfo.branded("Save subtitles…"), systemImage: "doc.badge.arrow.up", action: exportResult)
        if studio.isVideo {
            Button(AppInfo.branded("Subtitle appearance…"),
                   systemImage: "textformat") { stylingSubtitles = true }
            Button(AppInfo.branded("Create captioned video…"),
                   systemImage: "film", action: exportCaptionedVideo)
                .disabled(videoExporter.isExporting)
        }
    }

    private var toolsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toolSectionTitle(AppInfo.branded("Transcript tools"), icon: "sparkles")
                toolButton(AppInfo.branded("Follow playback"),
                           icon: "location.fill", active: followTranscript) {
                    followTranscript.toggle()
                }
                toolButton(AppInfo.branded("Edit segments"),
                           icon: "pencil", active: editing) { editing.toggle() }
                toolButton(AppInfo.branded("Copy text"), icon: "doc.on.doc") { copyText() }

                Divider()
                toolSectionTitle(AppInfo.branded("Project"), icon: "folder.badge.gearshape")
                toolButton(AppInfo.branded("Open project…"), icon: "folder") { openProject() }
                toolButton(AppInfo.branded("Save project…"), icon: "square.and.arrow.down",
                           disabled: studio.originalCues.isEmpty) { saveProject() }
                if studio.hasRecoveryProject {
                    toolButton(AppInfo.branded("Recover last work"),
                               icon: "clock.arrow.circlepath") { recoverProject() }
                }

                Divider()
                toolSectionTitle(AppInfo.branded("Export formats"),
                                 icon: "square.and.arrow.up")
                VStack(spacing: 7) {
                    ForEach(AudioExportFormat.allCases) { format in
                        Button {
                            exportFormatRaw = format.rawValue
                            exportResult()
                        } label: {
                            HStack {
                                Text(format.rawValue.uppercased())
                                    .font(.caption2.bold()).frame(width: 36)
                                    .padding(.vertical, 4)
                                    .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 6))
                                Text(exportDescription(format)).font(.caption)
                                Spacer()
                                Image(systemName: "square.and.arrow.down").foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(studio.cues.isEmpty)
                        .padding(8)
                        .background(WorkspaceStyle.field, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WorkspaceStyle.border))
                    }
                }

                Picker(AppInfo.branded("Content"), selection: $exportTrackRaw) {
                    Text(AppInfo.branded("Original")).tag(AudioExportTrack.original.rawValue)
                    Text(AppInfo.branded("Translation")).tag(AudioExportTrack.translated.rawValue)
                    Text(AppInfo.branded("Bilingual")).tag(AudioExportTrack.bilingual.rawValue)
                }

                if studio.isVideo {
                    Divider()
                    toolSectionTitle(AppInfo.branded("Captioned video"), icon: "film")
                    toolButton(AppInfo.branded("Appearance"), icon: "textformat") { stylingSubtitles = true }
                    toolButton(AppInfo.branded("Create MOV copy…"), icon: "film.badge.plus",
                               disabled: videoExporter.isExporting || studio.cues.isEmpty) {
                        exportCaptionedVideo()
                    }
                }
            }
            .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }

    private func toolSectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline)
    }

    private func toolButton(_ title: String, icon: String, active: Bool = false,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).foregroundStyle(active ? Color.appAccent : Color.secondary)
                    .frame(width: 18)
                Text(title).font(.callout)
                Spacer()
                if active { Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.appAccent) }
            }
            .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled)
        .background(WorkspaceStyle.field, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(WorkspaceStyle.border))
    }

    private func exportDescription(_ format: AudioExportFormat) -> String {
        switch format {
        case .srt: return AppInfo.branded("SubRip subtitles")
        case .vtt: return AppInfo.branded("WebVTT subtitles")
        case .text: return AppInfo.branded("Plain text")
        case .json: return AppInfo.branded("Data with timestamps")
        }
    }

    private var resultSummary: String {
        let words = studio.cues.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let language = studio.detectedLanguage.isEmpty ? "" : " · \(studio.detectedLanguage.uppercased())"
        let translating = studio.translationBatchCount > 0 && studio.stage == .translating
        let translation = translating
            ? " · " + AppInfo.branded("\(studio.translatedBatchCount)/\(studio.translationBatchCount) translated")
            : ""
        return AppInfo.branded("\(studio.cues.count) segments · \(words) words\(language)\(translation)")
    }

    private func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .audiovisualContent]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        studio.select(url)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(studio.content(for: .text, track: exportTrack), forType: .string)
    }

    private func exportResult() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension) ?? .plainText]
        let base = studio.sourceURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        panel.nameFieldStringValue = "\(base).\(exportFormat.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try studio.content(for: exportFormat, track: exportTrack)
                .write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let base = studio.sourceURL?.deletingPathExtension().lastPathComponent ?? "audio"
        panel.nameFieldStringValue = "\(base).xeon-audio.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try studio.saveProject(to: url, targetLanguage: targetLanguage, glossary: glossary)
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try studio.loadProject(from: url)
            targetLanguage = studio.translationTargetLanguage
            glossary = studio.translationGlossary
            translationModel = studio.translationModel
            transcriptModeRaw = studio.transcriptMode.rawValue
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private func exportCaptionedVideo() {
        guard let sourceURL = studio.sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "\(sourceURL.deletingPathExtension().lastPathComponent)-subtitulado.mov"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        videoExporter.export(sourceURL: sourceURL, cues: studio.exportCues(for: exportTrack),
                             outputURL: outputURL)
    }

    private func recoverProject() {
        do {
            try studio.loadRecoveryProject()
            targetLanguage = studio.translationTargetLanguage
            glossary = studio.translationGlossary
            translationModel = studio.translationModel
            transcriptModeRaw = studio.transcriptMode.rawValue
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }

    private static func accepts(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }
}

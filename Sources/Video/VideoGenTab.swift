// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

private enum VideoSidebarMode: Hashable { case create, batch }

struct VideoControls: View {
    @ObservedObject var pool: VideoGenPool
    @EnvironmentObject var loc: Localizer
    @EnvironmentObject var models: ModelStore

    @AppStorage(SettingsKeys.videoModel) private var modelName = ""
    @AppStorage(SettingsKeys.videoFrames) private var frames = 33
    @AppStorage(SettingsKeys.videoSteps) private var steps = 30
    @AppStorage(SettingsKeys.videoRecipeVersion) private var recipeVersion = 0
    @AppStorage(SettingsKeys.videoSize) private var sizeLabel = ""
    @AppStorage(SettingsKeys.videoGPU) private var gpuIndex = -1
    @AppStorage(SettingsKeys.videoVAETiling) private var vaeTiling = true
    @AppStorage(SettingsKeys.videoNegativePrompt) private var negativePrompt = ""
    @AppStorage(SettingsKeys.videoNegativeSeeded) private var negativeSeeded = false
    @State private var prompt = ""
    @State private var seed = -1
    @State private var initImage = ""
    @State private var sidebarMode = VideoSidebarMode.create

    private var gen: VideoGenerator { pool.generator }
    private var vram: Double { ImageControls.vram(of: gpuIndex) }
    private var model: VideoGenModel {
        VideoGenCatalog.all.first { $0.name == modelName }
            ?? VideoGenCatalog.recommended(vramGB: vram)
    }
    private var installed: Bool { VideoGenerator.installed(model, in: models) }
    private var size: VideoGenSize {
        model.sizes.first { $0.label == sizeLabel } ?? model.sizes[0]
    }
    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && installed && VideoGenerator.engineInstalled
    }
    private var vramFraction: Double {
        VideoGenLimits.vramFraction(width: size.width, height: size.height, frames: frames,
                                    vramGB: vram, model: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarMode) {
                Text(AppInfo.branded("Create")).tag(VideoSidebarMode.create)
                Text(AppInfo.branded("Batch")).tag(VideoSidebarMode.batch)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modelCard
                    promptCard
                    settingsCard
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
            }
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(minWidth: 300)
        .buttonStyle(GlassPillButtonStyle())
        .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        .onAppear {
            models.refreshIfNeeded()
            pool.modelStore = models
            if modelName.isEmpty { modelName = VideoGenCatalog.recommended(vramGB: vram).name }
            if !negativeSeeded { negativePrompt = model.negativePrompt; negativeSeeded = true }
            if recipeVersion < 1 { steps = model.defaultSteps; recipeVersion = 1 }
        }
        .onChange(of: sidebarMode) { _, value in
            pool.section = value == .batch ? .queue : .videos
        }
        .onChange(of: modelName) { _, _ in
            steps = model.defaultSteps
            sizeLabel = ""
            if VideoGenCatalog.isDefaultNegative(negativePrompt) { negativePrompt = model.negativePrompt }
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(AppInfo.branded("Instance"), systemImage: "cube")
                    .font(.headline)
                Spacer()
                Text(AppInfo.branded("Experimental"))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.branded("Model")).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $modelName) {
                    ForEach(VideoGenCatalog.all) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                Text(model.detail)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !installed { installBox }
            if !model.fitsVRAMClass(vram) {
                Label(AppInfo.branded("Requires \(Int(model.minVRAMGB)) GB of VRAM; \(Int(vram)) GB is available."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppInfo.branded("Prompt")).font(.headline)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .font(.body).frame(minHeight: 96)
                    .scrollContentBackground(.hidden).padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                if prompt.isEmpty {
                    Text(AppInfo.branded("Describe the motion, scene, and camera…"))
                        .font(.body).foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
            negativePromptRow
            if model.supportsI2V { initImageRow }
        }
    }

    private var negativePromptRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppInfo.branded("Negative prompt")).font(.subheadline)
                Spacer()
                Button { negativePrompt = model.negativePrompt } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(GlassIconButtonStyle()).controlSize(.small)
                .disabled(negativePrompt == model.negativePrompt)
                .iconHelp(AppInfo.branded("Restore the model prompt"))
            }
            TextEditor(text: $negativePrompt)
                .font(.callout).frame(minHeight: 44)
                .scrollContentBackground(.hidden).padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if negativePrompt.isEmpty {
                        Text(AppInfo.branded("blurry, deformed, watermark, text…"))
                            .font(.callout).foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 12) {
            settingRow(AppInfo.branded("Resolution"),
                       help: AppInfo.branded("Only the sizes the model states. Outside them the picture comes back soft, or the model does not accept the shape at all.")) {
                // shows the size a run will use, which is the model's first while none is chosen
                Picker("", selection: Binding(get: { size.label }, set: { sizeLabel = $0 })) {
                    ForEach(model.sizes) { Text($0.label).tag($0.label) }
                }
                .labelsHidden().frame(width: 140, alignment: .trailing)
            }
            settingRow(AppInfo.branded("Frames"),
                       help: AppInfo.branded("The temporal VAEs supported by the engine require 4n+1 frame counts.")) {
                Picker("", selection: $frames) {
                    ForEach(VideoGenLimits.frameCounts, id: \.self) { count in
                        Text("\(count) · \(String(format: "%.1f", VideoGenLimits.seconds(frames: count, fps: model.fps)))s").tag(count)
                    }
                }
                .labelsHidden().frame(width: 140, alignment: .trailing)
            }
            settingRow(AppInfo.branded("Steps"),
                       help: AppInfo.branded("More steps refine the detail and take proportionally longer. The model ships its own recommendation.")) {
                Stepper("\(steps)", value: $steps, in: 8...60, step: 2).frame(width: 140, alignment: .trailing)
            }
            settingRow(AppInfo.branded("Seed"),
                       help: AppInfo.branded("Repeat the same seed with the same prompt to reproduce a video. Change it to explore variations.")) {
                TextField("", value: $seed, format: .number).workspaceTextField().frame(width: 140)
            }
            if !hardware.gpus.isEmpty {
                settingRow("GPU",
                           help: AppInfo.branded("Which GPU generates the video. With several cards, leave the one driving the display free.")) {
                    if hardware.gpus.count > 1 {
                        Picker("", selection: $gpuIndex) {
                            Text(AppInfo.branded("Automatic")).tag(-1)
                            ForEach(Array(hardware.gpus.enumerated()), id: \.offset) { i, gpu in Text(gpu.name).tag(i) }
                        }
                        .labelsHidden().frame(width: 140, alignment: .trailing)
                    } else {
                        Text(hardware.gpus[0].name).font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            settingRow(AppInfo.branded("Decode in tiles"),
                       help: AppInfo.branded("Recommended. Without it the decode brightens every fourth frame and the clip flickers, and it asks for up to 16 GB instead of 3.4. It costs 26% of the decode.")) {
                Toggle("", isOn: $vaeTiling).labelsHidden().toggleStyle(.switch)
            }
            if let warning = framesBeyondNative {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let recommended = VideoGenLimits.recommendedVRAMGB(model: model, frames: frames) {
                Label(AppInfo.branded("This configuration recommends \(Int(recommended)) GB of VRAM."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if vramFraction > 0.9 {
                Label(AppInfo.branded("Estimated use: \(Int(vramFraction * 100))% of VRAM."), systemImage: "memorychip")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(modelNote).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var initImageRow: some View {
        HStack(spacing: 6) {
            Text(AppInfo.branded("Init image (img2video)")).font(.caption)
                .help(AppInfo.branded("This model can animate a still: it becomes the first frame."))
            Spacer(minLength: 6)
            Button(initImage.isEmpty ? AppInfo.branded("Choose…")
                                     : URL(fileURLWithPath: initImage).lastPathComponent) { pickInitImage() }
                .font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 150, alignment: .trailing)
            if !initImage.isEmpty {
                Button { initImage = "" } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(GlassIconButtonStyle())
                    .iconHelp(AppInfo.branded("Remove image"))
            }
        }
    }

    private func settingRow<Content: View>(_ title: String, help: String = "",
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.callout)
            Spacer(minLength: 8)
            content()
        }
        .help(help)
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if gen.isBusy {
                Button(role: .cancel) { pool.cancelCurrent() } label: {
                    Label(AppInfo.branded("Cancel"), systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else if sidebarMode == .create {
                Button { pool.generate(request) } label: {
                    Label(AppInfo.branded("Generate video"), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true).controlSize(.large).disabled(!canSubmit)
            } else {
                Button { addToQueue() } label: {
                    Label(AppInfo.branded("Add to queue"), systemImage: "text.badge.plus").frame(maxWidth: .infinity)
                }
                .glassButton(prominent: true).controlSize(.large).disabled(!canSubmit)
                HStack(spacing: 8) {
                    Text(AppInfo.branded("\(pool.queue.count) pending"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        pool.queueActive ? pool.stopQueue() : pool.startQueue()
                    } label: {
                        Label(pool.queueActive ? AppInfo.branded("Pause") : AppInfo.branded("Process"),
                              systemImage: pool.queueActive ? "pause.fill" : "play.fill")
                    }
                    .glassButton().disabled(pool.queue.isEmpty && !pool.queueActive)
                }
            }
            if case .failed(let why) = gen.state, !why.isEmpty {
                Label(failureText(why), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            Text(AppInfo.branded("Generation runs locally. Time depends on your hardware."))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var request: VideoGenerationRequest {
        VideoGenerationRequest(modelName: model.name,
                               prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                               negativePrompt: negativePrompt,
                               width: size.width, height: size.height,
                               frameCount: frames, steps: steps, seed: seed,
                               fps: model.fps, gpuIndex: gpuIndex, initImagePath: initImage)
    }

    private func addToQueue() { guard canSubmit else { return }; pool.enqueue(request); prompt = "" }

    private var modelNote: String {
        let sizes = model.sizes.map(\.label).joined(separator: ", ")
        if model.nativeFrames > 0 {
            let seconds = String(format: "%.1f", VideoGenLimits.seconds(frames: model.nativeFrames, fps: model.fps))
            return AppInfo.branded("Native resolutions: \(sizes) · \(model.nativeFrames) frames (\(seconds) s) at \(model.fps) fps.")
        }
        return AppInfo.branded("Native resolutions: \(sizes) · \(model.fps) fps.")
    }

    /// Past what the model was trained on the motion drifts, which reads as an app bug.
    private var framesBeyondNative: String? {
        guard model.nativeFrames > 0, frames > model.nativeFrames else { return nil }
        return AppInfo.branded("Past the \(model.nativeFrames) frames the model learned: the motion may drift. That is the model's limit, not the app's.")
    }

    private var installBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.components) { component in
                let present = componentPresent(component)
                HStack(spacing: 8) {
                    Image(systemName: present ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(present ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(component.label).font(.caption)
                        Text(component.fileName).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let item = models.imageDownload(fileName: component.fileName) {
                        InlineDownloadProgress(item: item)
                    } else if !present {
                        Text(String(format: "%.1f GB", component.sizeGB))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Button {
                for component in model.components where !componentPresent(component) {
                    models.downloadImageComponent(urlString: component.urlString, fileName: component.fileName)
                }
            } label: {
                Label(AppInfo.branded("Download components"), systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .glassButton()
            .help(AppInfo.branded("Downloads only what is missing: the Wan models share a text encoder, so switching between them does not fetch it again."))
        }
        .padding(10)
        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspaceStyle.border))
    }

    private func componentPresent(_ component: ImageGenComponent) -> Bool {
        models.hasComponent(component)
    }
    private func failureText(_ why: String) -> String {
        switch why {
        case "OOM": return AppInfo.branded("Out of VRAM. Lower the resolution or frame count.")
        case "TIMEOUT": return AppInfo.branded("The GPU timed out. Lower the resolution or frame count.")
        default: return why
        }
    }
    private func pickInitImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { initImage = url.path }
    }
}

// MARK: - Detail

struct VideoCanvas: View {
    @ObservedObject var pool: VideoGenPool
    @EnvironmentObject var loc: Localizer
    @State private var selectedID: GeneratedVideo.ID?

    private var selected: GeneratedVideo? {
        pool.gallery.first(where: { $0.id == selectedID }) ?? pool.gallery.first
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                detailTabPicker
                Spacer()
            }
            .frame(minHeight: 38)
            if pool.section == .videos { videos } else {
                VideoQueueView(pool: pool) { result in selectedID = result.id; pool.section = .videos }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .buttonStyle(GlassPillButtonStyle())
        .onAppear { selectedID = pool.gallery.first?.id }
        .onChange(of: pool.gallery.map(\.id)) { _, _ in selectedID = pool.gallery.first?.id }
    }

    private var detailTabPicker: some View {
        HStack(spacing: 3) {
            detailTabButton(.videos, title: AppInfo.branded("Videos"),
                            systemImage: "play.rectangle.on.rectangle")
            detailTabButton(.queue,
                            title: pool.queue.isEmpty
                                ? AppInfo.branded("Queue")
                                : AppInfo.branded("Queue \(pool.queue.count)"),
                            systemImage: "list.bullet.rectangle")
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
        .fixedSize()
    }

    private func detailTabButton(_ section: VideoStudioSection, title: String,
                                 systemImage: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { pool.section = section }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(pool.section == section ? .semibold : .medium))
                .foregroundStyle(pool.section == section ? Color.white : Color.secondary)
                .frame(width: 118, height: 30)
                .background(pool.section == section ? Color.appAccent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pool.section == section ? .isSelected : [])
    }

    @ViewBuilder private var videos: some View {
        if !VideoGenerator.engineInstalled {
            centeredState(icon: "exclamationmark.triangle", title: AppInfo.branded("Video engine unavailable"),
                          detail: AppInfo.branded("Install or build the generation engine to create videos."), color: .orange)
        } else if pool.gallery.isEmpty {
            if pool.generator.isBusy { generationCanvas } else {
                centeredState(icon: "play.rectangle.on.rectangle", title: AppInfo.branded("Create your first video"),
                              detail: AppInfo.branded("Choose a model, describe the scene, and press Generate."))
            }
        } else {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 16) {
                    hero
                    if geometry.size.width >= 760 { gallery.frame(width: min(300, max(230, geometry.size.width * 0.26))) }
                }
            }
        }
    }

    private var generationCanvas: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack").font(.system(size: 42, weight: .light)).foregroundStyle(.tertiary)
            VideoGenerationProgressCard(gen: pool.generator, compact: false)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let selected { VideoPlaybackView(result: selected).id(selected.id).padding(12) }
                if pool.generator.isBusy { VideoGenerationProgressCard(gen: pool.generator, compact: true).padding(16) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(WorkspaceStyle.canvas)
            if let selected { resultFooter(selected) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                if pool.generator.isBusy { VideoGenerationThumbnail(gen: pool.generator) }
                ForEach(pool.gallery) { result in
                    VideoResultThumbnail(result: result, selected: result.id == selected?.id) { selectedID = result.id }
                }
            }
            .padding(2)
        }
    }

    private func resultFooter(_ result: GeneratedVideo) -> some View {
        HStack(spacing: 12) {
            Circle().fill(.green).frame(width: 9, height: 9)
            Text(AppInfo.branded("Generated in \(result.duration)s"))
                .font(.caption.weight(.medium)).foregroundStyle(.green)
            Text("\(result.width) × \(result.height) · \(result.frameCount)f · \(result.fps) fps")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button { exportMP4(result) } label: { Label(AppInfo.branded("Save"), systemImage: "square.and.arrow.down") }
            Button { reveal(result) } label: { Label(AppInfo.branded("Reveal in Finder"), systemImage: "folder") }
        }
        .controlSize(.small).padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Divider() }
    }

    private func centeredState(icon: String, title: String, detail: String, color: Color = .secondary) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 42, weight: .light)).foregroundStyle(color)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }
}

private struct VideoQueueView: View {
    @ObservedObject var pool: VideoGenPool
    @EnvironmentObject var loc: Localizer
    let select: (GeneratedVideo) -> Void
    @State private var grid = true

    var body: some View {
        VStack(spacing: 14) {
            queueToolbar
            if pool.queue.isEmpty && pool.gallery.isEmpty && !pool.generator.isBusy { emptyState } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if pool.generator.isBusy {
                            sectionTitle(AppInfo.branded("In progress"), count: 1, icon: "gearshape.2")
                            VideoGenerationProgressCard(gen: pool.generator, compact: false)
                        }
                        if !pool.queue.isEmpty {
                            sectionTitle(AppInfo.branded("Pending"), count: pool.queue.count, icon: "clock")
                            ForEach(Array(pool.queue.enumerated()), id: \.element.id) { index, request in pendingRow(request, number: index + 1) }
                        }
                        if !pool.gallery.isEmpty {
                            sectionTitle(AppInfo.branded("Results"), count: pool.gallery.count, icon: "play.rectangle.on.rectangle")
                            if grid {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 440), spacing: 12)], spacing: 12) {
                                    ForEach(pool.gallery) { resultCard($0) }
                                }
                            } else {
                                VStack(spacing: 10) { ForEach(pool.gallery) { resultRow($0) } }
                            }
                        }
                    }
                    .padding(2)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 40, weight: .light)).foregroundStyle(.tertiary)
            Text(AppInfo.branded("Build a batch from the sidebar")).font(.title3.weight(.semibold))
            Text(AppInfo.branded("Add prompts with their settings and process them in order."))
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.border))
    }

    private var queueToolbar: some View {
        HStack(spacing: 10) {
            Label(AppInfo.branded("\(pool.queue.count) pending"), systemImage: "list.number").font(.callout.weight(.medium))
            if pool.generator.isBusy { Text(AppInfo.branded("Processing")).font(.caption).foregroundStyle(.green) }
            Spacer()
            FeedLayoutPicker(grid: $grid)
            Button { pool.queueActive ? pool.stopQueue() : pool.startQueue() } label: {
                Label(pool.queueActive ? AppInfo.branded("Pause") : AppInfo.branded("Process"),
                      systemImage: pool.queueActive ? "pause.fill" : "play.fill")
            }
            .glassButton(prominent: true).disabled(pool.queue.isEmpty && !pool.queueActive)
            if pool.generator.isBusy {
                Button(role: .cancel) { pool.cancelCurrent() } label: { Label(AppInfo.branded("Cancel current"), systemImage: "stop.circle") }
            }
        }
        .padding(12)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    private func pendingRow(_ request: VideoGenerationRequest, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.caption.weight(.bold)).foregroundStyle(Color.appAccent)
                .frame(width: 28, height: 28).background(Color.appAccent.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(request.prompt).font(.callout.weight(.medium)).lineLimit(2)
                Text("\(request.modelName) · \(request.width) × \(request.height) · \(request.frameCount)f · \(request.fps) fps")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { pool.remove(request.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(GlassIconButtonStyle()).iconHelp(AppInfo.branded("Remove from queue"))
        }
        .padding(12)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    private func resultCard(_ result: GeneratedVideo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { select(result) } label: { resultPreview(result).frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fill).clipped() }
                .buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 10))
            Text(result.prompt).font(.callout.weight(.medium)).lineLimit(2)
            Text("\(result.width) × \(result.height) · \(result.frameCount)f · \(result.modelName) · \(result.duration)s")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Button { exportMP4(result) } label: { Label(AppInfo.branded("Save"), systemImage: "square.and.arrow.down") }
                Button { reveal(result) } label: { Label("Finder", systemImage: "folder") }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    private func resultRow(_ result: GeneratedVideo) -> some View {
        HStack(spacing: 12) {
            Button { select(result) } label: { resultPreview(result).frame(width: 150, height: 84).clipped() }
                .buttonStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(result.prompt).font(.callout.weight(.medium)).lineLimit(2)
                Text("\(result.modelName) · \(result.width) × \(result.height) · \(result.frameCount)f · \(result.duration)s")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { exportMP4(result) } label: { Image(systemName: "square.and.arrow.down") }
                .buttonStyle(GlassIconButtonStyle())
                .iconHelp(AppInfo.branded("Save video"))
            Button { reveal(result) } label: { Image(systemName: "folder") }
                .buttonStyle(GlassIconButtonStyle())
                .iconHelp(AppInfo.branded("Reveal in Finder"))
        }
        .padding(10)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }

    @ViewBuilder private func resultPreview(_ result: GeneratedVideo) -> some View {
        if let preview = result.preview { Image(nsImage: preview).resizable().scaledToFill() }
        else { Image(systemName: "film").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
    private func sectionTitle(_ title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(Color.appAccent)
            Text(title).font(.headline)
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct VideoGenerationProgressCard: View {
    @ObservedObject var gen: VideoGenerator
    @EnvironmentObject var loc: Localizer
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(stageTitle).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(Int(gen.progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: gen.progress).tint(Color.appAccent)
            HStack {
                Text(gen.lastModelName).lineLimit(1); Spacer(); Text(timeText).monospacedDigit()
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(compact ? 12 : 16).frame(width: compact ? 270 : nil)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.border))
    }
    private var stageTitle: String {
        switch gen.stage {
        case .loading: return AppInfo.branded("Loading models…")
        case .sampling: return AppInfo.branded("Sampling · step \(gen.stepText)")
        case .decoding: return AppInfo.branded("Decoding frames…")
        }
    }
    private var timeText: String {
        if let eta = gen.etaSeconds { return AppInfo.branded("\(gen.elapsed)s · ~\(eta)s left") }
        return AppInfo.branded("\(gen.elapsed)s elapsed")
    }
}

private struct VideoGenerationThumbnail: View {
    @ObservedObject var gen: VideoGenerator
    @EnvironmentObject var loc: Localizer
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                ProgressView().controlSize(.small)
                Text(AppInfo.branded("Generating video")).font(.caption.weight(.semibold))
                Spacer(); Text("\(Int(gen.progress * 100))%").font(.caption2.monospacedDigit())
            }
            ProgressView(value: gen.progress).tint(Color.appAccent)
            Text(gen.lastModelName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text("\(gen.lastWidth) × \(gen.lastHeight) · \(gen.lastFrameCount)f")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 126, alignment: .bottomLeading)
        .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appAccent.opacity(0.8), lineWidth: 1.5))
    }
}

private struct VideoResultThumbnail: View {
    let result: GeneratedVideo
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    if let preview = result.preview {
                        Image(nsImage: preview).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else { Image(systemName: "film").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.modelName).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text("\(result.width) × \(result.height) · \(result.frameCount)f").lineLimit(1).minimumScaleFactor(0.7)
                            Spacer(minLength: 2); Text("\(result.duration)s")
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.64))
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.appAccent : Color.secondary.opacity(0.22), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain).help(result.prompt)
    }
}

private struct VideoPlaybackView: View {
    let result: GeneratedVideo
    @EnvironmentObject var loc: Localizer
    @State private var playing = true
    @State private var frameIndex = 0
    @State private var playbackFrames: [NSImage] = []
    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1.0 / Double(max(1, result.fps)))) { context in
                let count = playbackFrames.count
                if count > 0 {
                    let tick = Int(context.date.timeIntervalSinceReferenceDate * Double(max(1, result.fps)))
                    let index = playing ? ((tick % count) + count) % count : min(max(0, frameIndex), count - 1)
                    Image(nsImage: playbackFrames[index]).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                } else if let preview = result.preview { Image(nsImage: preview).resizable().scaledToFit() }
            }
            HStack(spacing: 10) {
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                    .buttonStyle(GlassIconButtonStyle(active: playing))
                    .iconHelp(playing ? AppInfo.branded("Pause") : AppInfo.branded("Play"))
                if !playing, playbackFrames.count > 1 {
                    Slider(value: Binding(get: { Double(frameIndex) }, set: { frameIndex = Int($0) }),
                           in: 0...Double(playbackFrames.count - 1))
                    Text("\(frameIndex + 1)/\(playbackFrames.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text(result.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(AppInfo.branded("\(result.frameCount) frames"))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: result.id) {
            let urls = result.frameURLs
            // Decoded off the main actor as Data (Sendable); NSImage is built here,
            // because AppKit types are main-actor bound.
            let frames = await Task.detached(priority: .userInitiated) { () -> [Data] in
                urls.compactMap(VideoGenerator.displayFrameData)
            }.value
            guard !Task.isCancelled else { return }
            playbackFrames = frames.compactMap(NSImage.init(data:))
            frameIndex = 0
        }
    }
}

private func reveal(_ result: GeneratedVideo) {
    if let first = result.frameURLs.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
}

private func exportMP4(_ result: GeneratedVideo) {
    let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "xeonllm-video.mp4"
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    let urls = result.frameURLs; let fps = result.fps
    Task.detached {
        do {
            let frames = urls.compactMap { NSImage(contentsOf: $0) }
            try VideoExporter.writeMP4(frames: frames, fps: fps, to: destination)
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        } catch {
            await MainActor.run {
                let alert = NSAlert(); alert.messageText = AppInfo.name; alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning; alert.runModal()
            }
        }
    }
}

// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// Per-model vision control: an on/off switch plus, when on, the projector to
/// pin or auto-pair. `inline` is one compact row; `settings` is a form section.
struct VisionProjectorControl: View {
    enum Layout { case inline, settings, detail }

    let modelPath: String
    /// Anchor the switch to the leading edge (model cards, left-aligned) or the
    /// trailing edge (server card, right-aligned) so revealing the menu never
    /// shifts the switch's position.
    var switchLeading: Bool = false
    var layout: Layout = .inline
    var loadEnabled: Binding<Bool>? = nil
    @EnvironmentObject var loc: Localizer
    @State private var version = 0

    @ViewBuilder
    var body: some View {
        let _ = version
        let override = ServerSettings.mmprojOverride(forModel: modelPath)
        let enabled = override != "" && (loadEnabled?.wrappedValue ?? true)
        let resolved = ServerSettings.mmprojPath(forModel: modelPath)
        let mismatch = resolved.map { ServerSettings.mmprojIncompatible(model: modelPath, projector: $0) } ?? false
        let candidates = ServerSettings.compatibleProjectors(forModel: modelPath)
        let current = resolved.map(Self.stem)
            ?? (candidates.isEmpty ? AppInfo.branded("automatic") : AppInfo.branded("none paired, pick one"))
        if layout == .settings {
            settingsRows(enabled: enabled, current: current, mismatch: mismatch, candidates: candidates)
        } else if layout == .detail {
            detailRow(override: override, current: current, mismatch: mismatch, candidates: candidates)
        } else {
            inlineRow(enabled: enabled, current: current, mismatch: mismatch, candidates: candidates)
        }
    }

    private static func stem(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func detailRow(override: String?, current: String, mismatch: Bool, candidates: [String]) -> some View {
        let selected = override == "" ? "off" : (override ?? "auto")
        var options: [XeonDropdown<String>.Option] = [
            .init(value: "auto", title: AppInfo.branded("Automatic"), subtitle: current, systemImage: "wand.and.stars"),
            .init(value: "off", title: AppInfo.branded("Text only"), subtitle: AppInfo.branded("Do not load a projector"), systemImage: "eye.slash")
        ]
        for path in candidates {
            options.append(.init(value: path, title: Self.stem(path),
                                 subtitle: AppInfo.branded("Matches the model's dimension"), systemImage: "eye"))
        }
        if let override, !override.isEmpty, !candidates.contains(override) {
            options.append(.init(value: override, title: AppInfo.branded("Custom projector"),
                                 subtitle: URL(fileURLWithPath: override).lastPathComponent, systemImage: "doc"))
        }
        options.append(.init(value: "choose", title: AppInfo.branded("Choose file…"),
                             subtitle: AppInfo.branded("Select an mmproj GGUF file"), systemImage: "folder"))
        return XeonDropdown(selection: Binding(get: { selected }, set: { value in
            switch value {
            case "off": set("")
            case "auto": set(nil)
            case "choose": pick()
            default: set(value)
            }
        }), options: options,
            placeholder: mismatch ? AppInfo.branded("Incompatible projector") : AppInfo.branded("Select vision"),
            width: 220, listWidth: 320)
    }

    private func inlineRow(enabled: Bool, current: String, mismatch: Bool, candidates: [String]) -> some View {
        HStack(spacing: 8) {
            if switchLeading { toggle(enabled) }
            if enabled {
                Menu {
                    ForEach(candidates, id: \.self) { path in
                        Button(Self.stem(path)) { set(path) }
                    }
                    Button(AppInfo.branded("Choose file…")) { pick() }
                    Button(AppInfo.branded("Automatic")) { set(nil) }
                } label: {
                    HStack(spacing: 4) {
                        Text("mmproj:").foregroundStyle(.secondary)
                        Text(current).lineLimit(1).truncationMode(.middle)
                        if mismatch {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help(AppInfo.branded("The projector doesn't match the model's dimension; vision may fail."))
                        }
                    }
                    .font(.caption)
                }
                .menuStyle(.button).glassButton().controlSize(.small).fixedSize()
            } else {
                Text(AppInfo.branded("text-only")).font(.caption).foregroundStyle(.secondary)
            }
            if !switchLeading { toggle(enabled) }
        }
    }

    private func settingsRows(enabled: Bool, current: String, mismatch: Bool, candidates: [String]) -> some View {
        Group {
            Toggle(AppInfo.branded("Read images"),
                   isOn: Binding(get: { enabled }, set: { set($0 ? nil : "") }))
                .help(AppInfo.branded("With vision off the model answers text only and the projector is not loaded."))
            if enabled {
                LabeledContent(AppInfo.branded("Projector")) {
                    Menu(current) {
                        Button(AppInfo.branded("Automatic")) { set(nil) }
                        ForEach(candidates, id: \.self) { path in
                            Button(Self.stem(path)) { set(path) }
                        }
                        Button(AppInfo.branded("Choose file…")) { pick() }
                    }
                    .fixedSize()
                }
                if mismatch {
                    Label(AppInfo.branded("The projector doesn't match the model's dimension; vision may fail."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggle(_ enabled: Bool) -> some View {
        Toggle("", isOn: Binding(get: { enabled }, set: { set($0 ? nil : "") }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .help(AppInfo.branded("Turn vision on or off for this model"))
    }

    private func set(_ value: String?) {
        ServerSettings.setMmprojOverride(value, forModel: modelPath)
        loadEnabled?.wrappedValue = value != ""
        // Enabling (auto or a file) re-arms the vision load path.
        if value != "" { UserDefaults.standard.set(true, forKey: SettingsKeys.loadVision) }
        version += 1
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { set(url.path) }
    }
}

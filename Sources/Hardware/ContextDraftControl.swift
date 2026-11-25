// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Per-model opt-in for draft-model-free n-gram speculation. The engine reuses text
/// already in the conversation as drafts; this control decides whether that is allowed.
/// Off by default: it is a speed trade, not a quality one. `inline` is one compact row;
/// `settings` is a form section; `detail` is a dropdown row.
struct ContextDraftControl: View {
    enum Layout { case inline, settings, detail }

    let modelPath: String
    var layout: Layout = .detail
    @EnvironmentObject private var loc: Localizer
    @State private var enabled = false

    private var helpText: String {
        AppInfo.branded("Faster when the reply reuses text already in the conversation, such as rewrites, edits or code changes; can be a little slower otherwise. The answer is usually the same, but a close word choice can come out differently. Applies when the server restarts.")
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch layout {
            case .detail: detailRow
            case .settings: settingsRow
            case .inline: inlineRow
            }
        }
        .onAppear { enabled = ServerSettings.contextDraftEnabled(forModel: modelPath) }
        .onChange(of: enabled) { _, value in ServerSettings.setContextDraftEnabled(value, forModel: modelPath) }
    }

    private var detailRow: some View {
        XeonDropdown(selection: $enabled, options: [
            .init(value: false, title: AppInfo.branded("Off"),
                  subtitle: AppInfo.branded("One token per step"), systemImage: "circle"),
            .init(value: true, title: AppInfo.branded("On"),
                  subtitle: AppInfo.branded("Reuse conversation text"), systemImage: "text.append")
        ], width: 220, listWidth: 300)
        .help(helpText)
    }

    private var settingsRow: some View {
        LabeledContent(AppInfo.branded("Reuse conversation text")) {
            Picker(AppInfo.branded("Reuse conversation text"), selection: $enabled) {
                Text(AppInfo.branded("Off")).tag(false)
                Text(AppInfo.branded("On")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .help(helpText)
    }

    private var inlineRow: some View {
        Picker("Context draft", selection: $enabled) {
            Text(AppInfo.branded("Off")).tag(false)
            Text(AppInfo.branded("On")).tag(true)
        }
        .labelsHidden()
        .fixedSize()
        .font(.caption)
        .help(helpText)
    }
}
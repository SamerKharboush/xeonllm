// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Per-model MTP policy. The engine still chooses the embedded head or matching
/// assistant automatically; this control decides whether that acceleration is allowed.
/// `inline` is one compact row; `settings` is a form section.
struct MTPControl: View {
    enum Layout { case inline, settings, detail }

    let modelPath: String
    var layout: Layout = .detail
    @EnvironmentObject private var loc: Localizer
    @State private var enabled = true

    private var sourceText: String {
        ServerSettings.modelHasMTP(at: modelPath)
            ? AppInfo.branded("Embedded MTP head")
            : AppInfo.branded("External MTP draft")
    }

    private var helpText: String {
        AppInfo.branded("Automatic predicts several tokens per step with the model's head. On text it accepts rarely it can generate slower than without it; Disabled generates one token per step. Applies when the server restarts.")
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
        .onAppear { enabled = ServerSettings.mtpEnabled(forModel: modelPath) }
        .onChange(of: enabled) { _, value in ServerSettings.setMTPEnabled(value, forModel: modelPath) }
    }

    private var detailRow: some View {
        XeonDropdown(selection: $enabled, options: [
            .init(value: true, title: AppInfo.branded("Automatic"),
                  subtitle: sourceText, systemImage: "hare.fill"),
            .init(value: false, title: AppInfo.branded("Disabled"),
                  subtitle: AppInfo.branded("One-token decoding"), systemImage: "hare")
        ], width: 220, listWidth: 300)
        .help(helpText)
    }

    private var settingsRow: some View {
        LabeledContent(AppInfo.branded("Prediction")) {
            Picker(AppInfo.branded("Prediction"), selection: $enabled) {
                Text(AppInfo.branded("Disabled")).tag(false)
                Text(AppInfo.branded("Automatic")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .help(helpText)
    }

    private var inlineRow: some View {
        Picker("MTP", selection: $enabled) {
            Text(AppInfo.branded("Off")).tag(false)
            Text(AppInfo.branded("Auto")).tag(true)
        }
        .labelsHidden()
        .fixedSize()
        .font(.caption)
        .help(helpText)
    }
}

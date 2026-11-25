// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Per-model opt-in for repeatable temperature-0 answers under Dynamic MoE. The engine
/// keeps its load-time expert residency (XEON_DMOE_REPEATABLE=1), so the same request
/// gives the same answer. Off by default: it is a speed trade, not a quality one.
/// `inline` is one compact row; `settings` is a form section; `detail` is a dropdown row.
struct RepeatableAnswersControl: View {
    enum Layout { case inline, settings, detail }

    let modelPath: String
    var layout: Layout = .detail
    @EnvironmentObject private var loc: Localizer
    @State private var enabled = false

    private var helpText: String {
        AppInfo.branded("Mixture-of-experts models split their experts between the processor and the graphics card, and which one computes an expert can change from run to run, so the same question at temperature 0 can get a different answer. This keeps the experts where they were loaded, so the same request gives the same answer (the app sends one short warm-up request when the model loads). Generation is somewhat slower. Applies when the model runs on its own server, not in router mode.")
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
        .onAppear { enabled = ServerSettings.repeatableAnswersEnabled(forModel: modelPath) }
        .onChange(of: enabled) { _, value in ServerSettings.setRepeatableAnswersEnabled(value, forModel: modelPath) }
    }

    private var detailRow: some View {
        XeonDropdown(selection: $enabled, options: [
            .init(value: false, title: AppInfo.branded("Off"),
                  subtitle: AppInfo.branded("Experts may move between runs"), systemImage: "circle"),
            .init(value: true, title: AppInfo.branded("On"),
                  subtitle: AppInfo.branded("Keep experts where they loaded"), systemImage: "arrow.triangle.2.circlepath")
        ], width: 220, listWidth: 300)
        .help(helpText)
    }

    private var settingsRow: some View {
        LabeledContent(AppInfo.branded("Repeatable answers")) {
            Picker(AppInfo.branded("Repeatable answers"), selection: $enabled) {
                Text(AppInfo.branded("Off")).tag(false)
                Text(AppInfo.branded("On")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .help(helpText)
    }

    private var inlineRow: some View {
        Picker("Repeatable answers", selection: $enabled) {
            Text(AppInfo.branded("Off")).tag(false)
            Text(AppInfo.branded("On")).tag(true)
        }
        .labelsHidden()
        .fixedSize()
        .font(.caption)
        .help(helpText)
    }
}
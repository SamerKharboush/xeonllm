// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AudioExportProgressBar: View {
    @ObservedObject var exporter: SubtitleVideoExporter
    @EnvironmentObject private var loc: Localizer

    var body: some View {
        HStack(spacing: 10) {
            Label(AppInfo.branded("Creating captioned video…"),
                  systemImage: "film.stack")
                .font(.caption)
            ProgressView(value: exporter.progress)
            Text(exporter.progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .frame(minWidth: 38, alignment: .trailing)
            Button(AppInfo.branded("Cancel export"),
                   systemImage: "xmark", action: exporter.cancel)
                .labelStyle(.iconOnly)
                .help(AppInfo.branded("Cancels captioned video creation."))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

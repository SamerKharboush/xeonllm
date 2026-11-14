// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct DflashMemoryWarningSheet: View {
    let warning: DflashRuntimeWarning
    let useAutomatic: () -> Void
    let disable: () -> Void
    let continueAnyway: () -> Void
    @EnvironmentObject private var loc: Localizer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Label(AppInfo.branded("DFlash is using almost all VRAM"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.title2)
                .bold()
                .foregroundStyle(.orange)

            Text(AppInfo.branded("The server is holding \(usedText) of \(totalText) GiB (\(fractionText)). This configuration can lose performance, page memory, or fail as the context grows."))

            Text(AppInfo.branded("Recommendation: return to Auto so XeonLLM can choose a safe configuration; you can also disable DFlash or continue and remember this decision."))
                .foregroundStyle(.secondary)

            HStack {
                Button(AppInfo.branded("Continue"), action: continueAction)
                Spacer()
                Button(AppInfo.branded("Disable and restart"),
                       role: .destructive, action: disableAction)
                Button(AppInfo.branded("Auto and restart"),
                       action: automaticAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .interactiveDismissDisabled()
    }

    private var usedText: String {
        warning.usedGB.formatted(.number.precision(.fractionLength(2)))
    }

    private var totalText: String {
        warning.totalGB.formatted(.number.precision(.fractionLength(2)))
    }

    private var fractionText: String {
        warning.fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    private func automaticAction() {
        dismiss()
        useAutomatic()
    }

    private func disableAction() {
        dismiss()
        disable()
    }

    private func continueAction() {
        dismiss()
        continueAnyway()
    }
}

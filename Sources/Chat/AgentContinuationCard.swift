// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AgentContinuationCard: View {
    let continueAction: () -> Void
    let stopAction: () -> Void
    @EnvironmentObject private var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppInfo.branded("The agent reached its 8-turn limit. Continue?"),
                  systemImage: "arrow.clockwise.circle")
                .font(.callout)
            HStack {
                Button(AppInfo.branded("Continue"), systemImage: "play.fill",
                       action: continueAction)
                    .buttonStyle(.borderedProminent)
                Button(AppInfo.branded("Stop"), systemImage: "stop.fill",
                       role: .destructive, action: stopAction)
                    .glassButton()
            }
        }
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.25)))
        .accessibilityElement(children: .contain)
    }
}

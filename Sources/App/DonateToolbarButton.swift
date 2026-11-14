// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Toolbar shortcut to the project repository: a heart that now and then spells
/// out its label, so it is noticed without taking the space all the time.
struct DonateToolbarButton: View {
    @EnvironmentObject private var loc: Localizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var announcing = false

    private var expanded: Bool { hovering || announcing }

    var body: some View {
        // The toolbar re-hosts an item whose size changes, so the label unfolds
        // inside a fixed width.
        HStack {
            Spacer(minLength: 0)
            Menu {
                ForEach(AppInfo.donateOptions, id: \.url) { option in
                    Button {
                        guard let url = URL(string: option.url) else { return }
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text(option.label)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if expanded {
                        Text(AppInfo.branded("Donate"))
                            .font(.system(size: 12, weight: .semibold))
                            .fixedSize()
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.appAccent)
                        .scaleEffect(hovering ? 1.15 : 1)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.quaternary.opacity(expanded ? 1 : 0.6), in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(AppInfo.branded("Donate"))
            .help(AppInfo.branded("Support development"))
            .onHover { inside in animate { hovering = inside } }
        }
        .frame(width: 96, height: 28)
        .task { await announce() }
    }

    private func announce() async {
        try? await Task.sleep(for: .seconds(2))
        while !Task.isCancelled {
            animate { announcing = true }
            try? await Task.sleep(for: .seconds(4))
            animate { announcing = false }
            try? await Task.sleep(for: .seconds(Int.random(in: 180...480)))
        }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25), change)
    }
}

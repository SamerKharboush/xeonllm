// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct QueuedMessageBanner: View {
    let message: QueuedChatMessage
    let cancel: () -> Void
    @EnvironmentObject private var loc: Localizer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(Color.appAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.branded("Steering message queued"))
                    .font(.caption.weight(.semibold))
                Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(AppInfo.branded("Cancel steering message"),
                   systemImage: "xmark", action: cancel)
                       .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.appAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.appAccent.opacity(0.22)))
    }

    private var summary: String {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = message.attachments.count + message.imageURIs.count
        if text.isEmpty { return AppInfo.branded("\(files) attachment(s)") }
        return files == 0 ? text : AppInfo.branded("\(text) · \(files) attachment(s)")
    }
}

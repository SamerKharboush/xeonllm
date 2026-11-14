// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ForkConversationSheet: View {
    let sourceTitle: String
    let confirm: (String?, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: Localizer
    @State private var title = ""
    @State private var includeAttachments = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(AppInfo.branded("Fork conversation"),
                  systemImage: "arrow.triangle.branch")
                .font(.title2.weight(.semibold))
            Text(AppInfo.branded("Creates an independent conversation through this message. The original conversation is unchanged."))
                .foregroundStyle(.secondary)
            TextField(AppInfo.branded("Title (optional)"), text: $title,
                      prompt: Text(AppInfo.branded("Fork of \(sourceTitle)")))
                .workspaceTextField()
            Toggle(AppInfo.branded("Include files, images, audio and video"),
                   isOn: $includeAttachments)
            HStack {
                Spacer()
                Button(AppInfo.branded("Cancel")) { dismiss() }
                Button(AppInfo.branded("Create fork")) {
                    let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    confirm(value.isEmpty ? nil : value, includeAttachments)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 500)
    }
}

// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SubtitleEditorToolbar: View {
    @ObservedObject var studio: AudioStudioController
    @Binding var searchText: String
    @Binding var replacement: String
    @EnvironmentObject private var loc: Localizer

    var body: some View {
        HStack(spacing: 8) {
            TextField(AppInfo.branded("Find"), text: $searchText)
                .workspaceTextField()
                .help(AppInfo.branded("Filters segments by text."))
            TextField(AppInfo.branded("Replace with"), text: $replacement)
                .workspaceTextField()
                .help(AppInfo.branded("Text that will replace all matches."))
            Button(AppInfo.branded("Replace all"), systemImage: "text.badge.checkmark") {
                studio.replaceAll(searchText, with: replacement)
            }
            .disabled(searchText.isEmpty)
            .help(AppInfo.branded("Replaces matches in both the original and translation."))
            Button(AppInfo.branded("Undo"), systemImage: "arrow.uturn.backward",
                   action: studio.undoEdit)
                .labelStyle(.iconOnly)
                .disabled(!studio.canUndoEdit)
                .help(AppInfo.branded("Undoes the last subtitle edit."))
            Button(AppInfo.branded("Redo"), systemImage: "arrow.uturn.forward",
                   action: studio.redoEdit)
                .labelStyle(.iconOnly)
                .disabled(!studio.canRedoEdit)
                .help(AppInfo.branded("Redoes the last undone edit."))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

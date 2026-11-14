// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

struct WhisperLanguage: Identifiable, Hashable {
    let id: String
    let name: String

    static let common: [WhisperLanguage] = [
        .init(id: "auto", name: "Detect automatically"),
        .init(id: "es", name: "Spanish"),
        .init(id: "en", name: "English"),
        .init(id: "fr", name: "French"),
        .init(id: "de", name: "German"),
        .init(id: "it", name: "Italian"),
        .init(id: "pt", name: "Portuguese"),
        .init(id: "ja", name: "Japanese"),
        .init(id: "ko", name: "Korean"),
        .init(id: "zh", name: "Chinese"),
        .init(id: "ru", name: "Russian")
    ]
}
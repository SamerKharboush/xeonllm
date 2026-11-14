// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum AudioTranslationError: LocalizedError {
    case server(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let status, let detail):
            let suffix = detail.isEmpty ? "" : ": \(detail)"
            return "The chat engine rejected the translation (HTTP \(status))\(suffix)"
        case .invalidResponse:
            return "The model did not return every translated subtitle; try another chat model."
        }
    }
}

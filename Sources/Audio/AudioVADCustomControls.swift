// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AudioVADCustomControls: View {
    @EnvironmentObject private var loc: Localizer

    @Binding var threshold: Double
    @Binding var minSpeechMS: Double
    @Binding var minSilenceMS: Double
    @Binding var maxSpeechSeconds: Double
    @Binding var speechPadMS: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(AppInfo.branded("Speech confidence")) {
                HStack {
                    Slider(value: $threshold, in: 0.1...0.95, step: 0.05)
                    Text(threshold, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .help(AppInfo.branded("A high value rejects more weak voices; it can also miss a quiet main voice."))

            LabeledContent(AppInfo.branded("Minimum speech")) {
                HStack {
                    Slider(value: $minSpeechMS, in: 100...2_000, step: 50)
                    Text(minSpeechMS / 1_000,
                         format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .help(AppInfo.branded("Rejects speech shorter than this duration, shown in seconds."))

            LabeledContent(AppInfo.branded("Silence to split")) {
                HStack {
                    Slider(value: $minSilenceMS, in: 50...2_000, step: 50)
                    Text(minSilenceMS / 1_000,
                         format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .help(AppInfo.branded("Splits a segment when silence reaches this duration, shown in seconds."))

            LabeledContent(AppInfo.branded("Maximum segment")) {
                HStack {
                    Slider(value: $maxSpeechSeconds, in: 10...120, step: 5)
                    Text(maxSpeechSeconds, format: .number)
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .help(AppInfo.branded("Forces periodic splits so one phrase cannot feed excessively long segments."))

            LabeledContent(AppInfo.branded("Word padding")) {
                HStack {
                    Slider(value: $speechPadMS, in: 0...500, step: 20)
                    Text(speechPadMS / 1_000,
                         format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
            .help(AppInfo.branded("Keeps a small margin around speech so words are not clipped."))

            Button(AppInfo.branded("Reset settings"),
                   systemImage: "arrow.counterclockwise", action: resetValues)
                .controlSize(.small)
                .help(AppInfo.branded("Restores custom values to the Balanced profile."))
        }
    }

    private func resetValues() {
        let defaults = AudioVADProfile.balanced.calibration
        threshold = defaults.threshold
        minSpeechMS = Double(defaults.minSpeechDurationMS)
        minSilenceMS = Double(defaults.minSilenceDurationMS)
        maxSpeechSeconds = defaults.maxSpeechDurationSeconds
        speechPadMS = Double(defaults.speechPadMS)
    }
}

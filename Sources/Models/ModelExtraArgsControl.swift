import SwiftUI

/// Per-model CLI arguments. They are appended after the shared field in Settings, so a model
/// can override a flag that one also sets.
struct ModelExtraArgsControl: View {
    let modelPath: String

    @EnvironmentObject var loc: Localizer
    @State private var text = ""

    var body: some View {
        TextField(AppInfo.branded("Arguments"),
                  text: $text,
                  prompt: Text(verbatim: "-md /path/head.gguf --spec-type draft-mtp"))
            .workspaceTextField()
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .accessibilityLabel(AppInfo.branded("Extra arguments for this model"))
            .help(AppInfo.branded("Added after the extra arguments in Settings, and win over them. They apply to this model only."))
            .task(id: modelPath) { text = ServerSettings.extraArgs(forModel: modelPath) }
            .onChange(of: text) { _, new in
                ServerSettings.setExtraArgs(new, forModel: modelPath)
            }
    }
}

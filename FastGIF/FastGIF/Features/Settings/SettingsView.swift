import SwiftUI

/// Editor preferences — surfaced from the toolbar More menu.
/// One source-of-truth for power-user toggles; defaults are conservative
/// so first-launch users get the simpler experience.
struct SettingsView: View {
    @AppStorage("editor.msPrecision") private var msPrecision: Bool = false
    @AppStorage("editor.showTrimGuides") private var showTrimGuides: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $msPrecision) {
                        VStack(alignment: .leading, spacing: Theme.spacing4) {
                            Text("Millisecond precision")
                            Text("Show 0.000s timecodes and let trim handles land between frames.")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("Timeline")
                } footer: {
                    Text("Frame snapping stays on by default — switch this on for shot-accurate edits like sticker timing.")
                }

                Section {
                    Toggle(isOn: $showTrimGuides) {
                        Text("Show trim guides")
                    }
                } header: {
                    Text("Editor")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }
}

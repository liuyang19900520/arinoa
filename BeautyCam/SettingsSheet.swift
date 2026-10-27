import SwiftUI

/// Minimal settings sheet, reachable from the gear button in the camera top bar.
struct SettingsSheet: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("语言") {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            languageRaw = lang.rawValue
                        } label: {
                            HStack {
                                Text(lang.displayName).foregroundStyle(.primary)
                                Spacer()
                                if languageRaw == lang.rawValue {
                                    Image(systemName: "checkmark").foregroundStyle(.pink)
                                }
                            }
                        }
                        .accessibilityIdentifier("lang-\(lang.rawValue)")
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("settingsDone")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

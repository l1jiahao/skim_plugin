import SwiftUI

public struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Provider")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Preset")
                    Picker("Preset", selection: $model.config.providerPreset) {
                        ForEach(ProviderPreset.allCases, id: \.self) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: model.config.providerPreset) { preset in
                        if preset == .deepSeek {
                            model.config.applyDeepSeekDefaults()
                        }
                    }
                }
                GridRow {
                    Text("Base URL")
                    TextField("https://api.openai.com/v1", text: $model.config.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Model")
                    TextField("gpt-4o-mini", text: $model.config.model)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("API key")
                    SecureField("Stored locally, not in Keychain", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Picker("PDF context", selection: $model.config.contextMode) {
                ForEach(PDFContextMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if model.config.isDeepSeekOptimized {
                Picker("DeepSeek mode", selection: Binding(
                    get: { model.config.deepSeekInteractionMode },
                    set: { model.setDeepSeekInteractionMode($0) }
                )) {
                    ForEach(DeepSeekInteractionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("DeepSeek thinking mode", isOn: $model.config.deepSeekThinkingEnabled)
                Picker("Reasoning effort", selection: $model.config.deepSeekReasoningEffort) {
                    ForEach(DeepSeekReasoningEffort.allCases, id: \.self) { effort in
                        Text(effort.rawValue).tag(effort)
                    }
                }
                .disabled(!model.config.deepSeekThinkingEnabled)

                HStack {
                    Text("Long context")
                    Slider(
                        value: Binding(
                            get: { Double(model.config.maxLongContextCharacters) },
                            set: { model.config.maxLongContextCharacters = Int($0) }
                        ),
                        in: 120_000...1_200_000,
                        step: 40_000
                    )
                    Text("\(model.config.maxLongContextCharacters / 1000)k chars")
                        .foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .trailing)
                }
            } else {
                Toggle("Provider supports PDF file input", isOn: $model.config.supportsPDFInput)
                Toggle("Attach the complete PDF when supported", isOn: $model.config.useFullPDFWhenAvailable)
                    .disabled(!model.config.supportsPDFInput)
            }

            Divider()

            Text("Window")
                .font(.title3.weight(.semibold))
            Toggle("Dock next to Skim", isOn: $model.config.autoDockToSkim)
            HStack {
                Text("Width")
                Slider(value: $model.config.sidebarWidth, in: 360...720, step: 20)
                Text("\(Int(model.config.sidebarWidth)) px")
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }

            Text("DeepSeek mode sends extracted full paper text as a stable long-context prefix to benefit from context caching. The API key is persisted in the app support folder with owner-only file permissions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    model.persistSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

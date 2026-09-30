import SwiftUI
import EnvStudioCore

struct MasterEnvironmentPicker: View {
    @EnvironmentObject private var store: DocumentStore

    private enum PickerValue: Hashable {
        case mixed
        case environment(EnvStage)
    }

    var body: some View {
        Picker("", selection: binding) {
            if case .mixed = store.masterSelection {
                Text("Mixed").tag(PickerValue.mixed)
            }
            ForEach(EnvStage.ordered) { env in
                Text(env.displayName).tag(PickerValue.environment(env))
            }
        }
        .labelsHidden()
        .frame(width: 140)
    }

    private var binding: Binding<PickerValue> {
        Binding(
            get: {
                switch store.masterSelection {
                case .mixed:
                    return .mixed
                case .uniform(let env):
                    return .environment(env)
                }
            },
            set: { newValue in
                switch newValue {
                case .mixed:
                    break
                case .environment(let env):
                    store.setMasterEnvironment(env)
                }
            }
        )
    }
}

struct VariableRowView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectivity: ConnectivityStore
    let variableKey: String

    @State private var keyText = ""

    private var variable: EnvVariable? {
        store.document.variable(forKey: variableKey)
    }

    var body: some View {
        HStack(spacing: 8) {
            ActivatingTextField(
                text: $keyText,
                placeholder: "KEY",
                isSecure: false
            )
            .frame(width: 200)
            .onSubmit { commitKey() }

            ActivatingTextField(
                text: store.valueBinding(forKey: variableKey),
                placeholder: "valor",
                isSecure: false
            )
            .frame(maxWidth: .infinity)

            Picker("", selection: environmentBinding) {
                ForEach(EnvStage.ordered) { env in
                    Text(env.displayName).tag(env)
                }
            }
            .labelsHidden()
            .frame(width: 100)

            TagsMenu(selected: tagsBinding)
                .frame(width: 140, alignment: .leading)

            Picker("", selection: tunnelFlagBinding) {
                Text("—").tag("")
                let flags = connectivity.sqlTunnelFlags()
                let current = variable?.tunnelFlag ?? ""
                if !current.isEmpty, !flags.contains(current) {
                    Text(current).tag(current)
                }
                ForEach(flags, id: \.self) { flag in
                    Text(flag).tag(flag)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .help("Liga esta variável a um túnel SQL. Ao gerar o token, a senha é atualizada neste ambiente.")
        }
        .padding(.vertical, 4)
        .onAppear { syncKeyFromStore() }
        .onChange(of: variable?.key) { _, _ in syncKeyFromStore() }
    }

    private var environmentBinding: Binding<EnvStage> {
        Binding(
            get: { variable?.activeEnvironment ?? .local },
            set: { store.setVariableEnvironment(key: variableKey, environment: $0) }
        )
    }

    private var tagsBinding: Binding<Set<VariableTag>> {
        Binding(
            get: { variable?.tags ?? [] },
            set: { store.setTags(key: variableKey, tags: $0) }
        )
    }

    private var tunnelFlagBinding: Binding<String> {
        Binding(
            get: { variable?.tunnelFlag ?? "" },
            set: { store.setTunnelFlag(key: variableKey, flag: $0) }
        )
    }

    private func syncKeyFromStore() {
        guard let variable else { return }
        keyText = variable.key
    }

    private func commitKey() {
        let trimmed = keyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != variableKey else { return }
        store.updateVariableKey(oldKey: variableKey, newKey: trimmed)
    }
}

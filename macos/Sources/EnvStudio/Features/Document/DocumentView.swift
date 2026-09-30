import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EnvStudioCore

struct DocumentView: View {
    @EnvironmentObject private var store: DocumentStore
    @State private var showImportSheet = false
    @State private var showExportSheet = false
    @State private var replicateTarget: EnvStage?
    @State private var showReplicateConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            masterBar
            if !store.warnings.isEmpty {
                warningsBar
            }
            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
            }
            tableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.document.variables) { variable in
                        VariableRowView(variableKey: variable.key)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
            }
            footer
        }
        .sheet(isPresented: $showImportSheet) {
            ImportSheet(isPresented: $showImportSheet)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(isPresented: $showExportSheet)
        }
        .alert(
            "Replicar valores ativos?",
            isPresented: $showReplicateConfirm,
            presenting: replicateTarget
        ) { target in
            Button("Replicar", role: .destructive) {
                store.replicateActiveValues(to: target)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { target in
            Text(
                "Copia o valor exibido de cada variável (ambiente da linha) para o bloco \"\(target.displayName)\", sobrescrevendo todos os valores desse ambiente. Salve depois para gravar no .env."
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button("Abrir pasta…") {
                pickFolder()
            }
            Text(store.folderPathDisplay)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            if showsUnsavedIndicator {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text(unsavedIndicatorTitle)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Toggle("Salvar automaticamente", isOn: $store.autoSaveEnabled)
                .toggleStyle(.switch)
                .disabled(store.folderURL == nil)
            Button("Recarregar") {
                store.reload()
            }
            .disabled(store.folderURL == nil)
            Button("Importar…") {
                showImportSheet = true
            }
            .disabled(store.folderURL == nil)
            Button("Salvar") {
                store.save()
            }
            .disabled(store.folderURL == nil || !store.hasUnsavedChanges)
            .keyboardShortcut("s", modifiers: .command)
            Button("Exportar…") {
                showExportSheet = true
            }
            .disabled(store.document.variables.isEmpty)
        }
        .padding(12)
    }

    private var masterBar: some View {
        HStack {
            Text("Ambiente global:")
                .fontWeight(.semibold)
            MasterEnvironmentPicker()
            Spacer()
            if store.isAutoSaving {
                Text("Salvando…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if showsUnsavedIndicator {
                Text("● Não salvo")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let status = store.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var warningsBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(store.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Variável")
                .frame(width: 200, alignment: .leading)
            Text("Valor")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Ambiente")
                .frame(width: 100, alignment: .leading)
            Text("Tags")
                .frame(width: 140, alignment: .leading)
            Text("Túnel SQL")
                .frame(width: 140, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Adicionar variável") {
                    store.addVariable()
                }
                .disabled(store.folderURL == nil)
                Spacer()
                replicateValuesMenu
            }
            if !store.managedFolders.isEmpty {
                managedFoldersBar
            }
        }
        .padding(12)
    }

    private var managedFoldersBar: some View {
        DisclosureGroup("Pastas gerenciadas (\(store.managedFolders.count))") {
            ForEach(store.managedFolders, id: \.path) { url in
                HStack {
                    Text(url.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Remover do app") {
                        store.forgetManagedFolder(url)
                    }
                    .font(.caption)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var replicateValuesMenu: some View {
        Menu {
            Section("Replicar valores ativos → ambiente") {
                ForEach(EnvStage.ordered) { stage in
                    Button("Sobrescrever bloco \(stage.displayName)") {
                        replicateTarget = stage
                        showReplicateConfirm = true
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .imageScale(.small)
        }
        .menuStyle(.borderlessButton)
        .opacity(0.35)
        .disabled(store.folderURL == nil || store.document.variables.isEmpty)
        .help(
            "Copia o valor ativo de cada linha para outro ambiente (local/dev/hom/prod), sobrescrevendo aquele bloco inteiro."
        )
    }

    private var showsUnsavedIndicator: Bool {
        if store.autoSaveEnabled {
            return store.hasUnsavedChanges || store.isAutoSaving
        }
        return store.hasUnsavedChanges
    }

    private var unsavedIndicatorTitle: String {
        if store.isAutoSaving {
            return "Salvando…"
        }
        return "Alterações não salvas"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar"
        if panel.runModal() == .OK, let url = panel.url {
            store.openFolder(url)
        }
    }
}

struct TagsMenu: View {
    @Binding var selected: Set<VariableTag>

    private var activeTag: VariableTag? {
        VariableTag.normalizedSingle(from: selected).first
    }

    var body: some View {
        Menu {
            Button {
                selected = []
            } label: {
                if activeTag == nil {
                    Label("Nenhuma", systemImage: "checkmark")
                } else {
                    Text("Nenhuma")
                }
            }
            Divider()
            ForEach(VariableTag.allCases) { tag in
                Button {
                    select(tag)
                } label: {
                    if activeTag == tag {
                        Label(tag.label, systemImage: "checkmark")
                    } else {
                        Text(tag.label)
                    }
                }
            }
        } label: {
            if let activeTag {
                Text(activeTag.label)
                    .lineLimit(1)
            } else {
                Text("Nenhuma")
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func select(_ tag: VariableTag) {
        if activeTag == tag {
            selected = []
        } else {
            selected = [tag]
        }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EnvStudioCore

struct ImportSheet: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var isPresented: Bool

    @State private var pastedText = ""
    @State private var mode: EnvDocumentMerger.ImportMode = .merge
    @State private var targetEnvironment: EnvStage = .local

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importar .env")
                .font(.title2)

            Text(
                "Cole o conteúdo abaixo. Arquivos flat preenchem o ambiente escolhido; blocos com # local / # dev usam o formato multi-seção."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("Modo", selection: $mode) {
                Text("Mesclar").tag(EnvDocumentMerger.ImportMode.merge)
                Text("Substituir documento").tag(EnvDocumentMerger.ImportMode.replace)
            }
            .pickerStyle(.segmented)

            Picker("Ambiente (import flat)", selection: $targetEnvironment) {
                ForEach(EnvStage.ordered) { env in
                    Text(env.displayName).tag(env)
                }
            }

            TextEditor(text: $pastedText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)

            HStack {
                Spacer()
                Button("Cancelar") {
                    isPresented = false
                }
                Button("Aplicar") {
                    store.importPastedText(
                        pastedText,
                        mode: mode,
                        targetEnvironment: targetEnvironment
                    )
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }
}

struct ExportSheet: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var isPresented: Bool

    @State private var omitSecretLines = true
    @State private var exportText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exportar .env flat")
                .font(.title2)

            Text(
                "Usa o ambiente ativo de cada variável. Marque secrets e connection strings com uma tag por variável; a exportação redige credenciais ou omite linhas secret."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Toggle("Omitir linhas com tag secret", isOn: $omitSecretLines)
                .onChange(of: omitSecretLines) { _, _ in refreshExport() }

            TextEditor(text: $exportText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .disabled(true)

            HStack {
                Button("Copiar") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportText, forType: .string)
                }
                Button("Salvar como…") {
                    saveToFile()
                }
                Spacer()
                Button("Fechar") {
                    isPresented = false
                }
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .onAppear { refreshExport() }
        .onChange(of: omitSecretLines) { _, _ in refreshExport() }
        .onChange(of: store.document) { _, _ in refreshExport() }
    }

    private func refreshExport() {
        exportText = store.exportFlatText(omitSecretLines: omitSecretLines)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = ".env.export"
        if panel.runModal() == .OK, let url = panel.url {
            try? exportText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

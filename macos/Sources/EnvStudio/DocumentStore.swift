import Foundation
import SwiftUI
import EnvStudioCore

@MainActor
public final class DocumentStore: ObservableObject {
    @Published public private(set) var folderURL: URL?
    @Published public private(set) var document = EnvDocument()
    @Published public private(set) var warnings: [EnvSectionParser.ParseWarning] = []
    @Published public private(set) var hasUnsavedChanges = false
    @Published public var envFileName = ".env"
    @Published public var errorMessage: String?
    @Published public var statusMessage: String?
    @Published public var autoSaveEnabled = UserDefaults.standard.bool(
        forKey: DocumentStore.autoSaveDefaultsKey
    ) {
        didSet {
            UserDefaults.standard.set(
                autoSaveEnabled,
                forKey: Self.autoSaveDefaultsKey
            )
            if autoSaveEnabled, hasUnsavedChanges {
                cancelAutoSaveTask()
                saveToDisk(isAutomatic: false)
            }
        }
    }
    @Published public private(set) var isAutoSaving = false
    @Published public private(set) var managedFolders: [URL] = ManagedWorkspaceRegistry.load()

    private static let autoSaveDefaultsKey = "envStudio.autoSaveEnabled"
    private static let autoSaveDebounceNs: UInt64 = 500_000_000

    private var savedEnvSnapshot: String?
    private var savedMetadataSnapshot: String?
    private var autoSaveTask: Task<Void, Never>?

    public init() {}

    public var masterSelection: MasterEnvironmentSelection {
        EnvDocument.masterSelection(from: document.variables)
    }

    public var folderPathDisplay: String {
        folderURL?.path ?? "Nenhuma pasta selecionada"
    }

    public func openFolder(_ url: URL) {
        folderURL = url
        ManagedWorkspaceRegistry.register(folder: url)
        managedFolders = ManagedWorkspaceRegistry.load()
        reload()
    }

    public func forgetManagedFolder(_ url: URL) {
        ManagedWorkspaceRegistry.remove(folder: url)
        managedFolders = ManagedWorkspaceRegistry.load()
        statusMessage = "Pasta removida da lista do app (o arquivo .env no disco permanece)."
    }

    public func reload() {
        guard let folderURL else { return }
        cancelAutoSaveTask()
        errorMessage = nil
        let envURL = folderURL.appendingPathComponent(envFileName)
        let metadata = StudioMetadataStore.load(from: folderURL)

        if FileManager.default.fileExists(atPath: envURL.path) {
            do {
                let text = try String(contentsOf: envURL, encoding: .utf8)
                let result = EnvSectionParser.parse(text)
                document = result.document
                warnings = result.warnings
                StudioMetadataStore.applyTags(to: &document, metadata: metadata)
            } catch {
                errorMessage = "Falha ao ler .env: \(error.localizedDescription)"
            }
        } else {
            document = EnvDocument()
            warnings = []
        }
        captureSavedSnapshot()
        statusMessage = "Recarregado"
    }

    public func save() {
        cancelAutoSaveTask()
        saveToDisk(isAutomatic: false)
    }

    private func saveToDisk(isAutomatic: Bool) {
        guard let folderURL else {
            errorMessage = "Selecione uma pasta primeiro."
            return
        }
        if isAutomatic {
            isAutoSaving = true
        }
        defer {
            if isAutomatic {
                isAutoSaving = false
            }
        }
        let envURL = folderURL.appendingPathComponent(envFileName)
        do {
            let text = EnvSectionWriter.render(document)
            try text.write(to: envURL, atomically: true, encoding: .utf8)
            let metadata = StudioMetadataStore.metadata(from: document)
            try StudioMetadataStore.save(metadata, to: folderURL)
            captureSavedSnapshot()
            statusMessage = isAutomatic ? "Salvo automaticamente" : "Salvo"
            errorMessage = nil
        } catch {
            errorMessage = "Falha ao salvar: \(error.localizedDescription)"
        }
    }

    public func setMasterEnvironment(_ environment: EnvStage) {
        mutateDocument { $0.setMasterEnvironment(environment) }
    }

    public func setVariableEnvironment(key: String, environment: EnvStage) {
        mutateDocument { document in
            guard let index = document.variables.firstIndex(where: { $0.key == key }) else {
                return
            }
            document.variables[index].activeEnvironment = environment
        }
    }

    public func updateVariableKey(oldKey: String, newKey: String) {
        mutateDocument { document in
            guard let index = document.variables.firstIndex(where: { $0.key == oldKey }) else {
                return
            }
            document.variables[index].key = newKey
            if let orderIndex = document.keyOrder.firstIndex(of: oldKey) {
                document.keyOrder[orderIndex] = newKey
            }
        }
    }

    public func updateVariableValue(key: String, value: String) {
        let sanitized = SingleLineFieldPolicy.sanitize(value)
        mutateDocument { document in
            guard let index = document.variables.firstIndex(where: { $0.key == key }) else {
                return
            }
            document.variables[index].setDisplayValue(sanitized)
        }
    }

    /// Copia o valor **ativo** de cada variável (select da linha) para o ambiente alvo,
    /// sobrescrevendo todos os valores daquele ambiente.
    public func replicateActiveValues(to target: EnvStage) {
        mutateDocument { document in
            for index in document.variables.indices {
                let activeValue = document.variables[index].displayValue
                document.variables[index].values[target] = activeValue
            }
        }
        statusMessage = autoSaveEnabled
            ? "Valores replicados em '\(target.displayName)' (salvando automaticamente…)"
            : "Valores ativos replicados em '\(target.displayName)' — salve para gravar no .env"
    }

    public func setTags(key: String, tags: Set<VariableTag>) {
        mutateDocument { document in
            guard let index = document.variables.firstIndex(where: { $0.key == key }) else {
                return
            }
            document.variables[index].tags = VariableTag.normalizedSingle(from: tags)
        }
    }

    public func setTunnelFlag(key: String, flag: String?) {
        mutateDocument { document in
            guard let index = document.variables.firstIndex(where: { $0.key == key }) else {
                return
            }
            let trimmed = flag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            document.variables[index].tunnelFlag = trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Atualiza variáveis ligadas ao túnel na pasta aberta e nas demais pastas registradas.
    public func applyTunnelToken(flag: String, stage: EnvStage, escapedPassword: String) -> String {
        let others = TunnelLinkedEnvSync.apply(
            folders: managedFolders,
            envFileName: envFileName,
            tunnelFlag: flag,
            stage: stage,
            escapedPassword: escapedPassword,
            excluding: folderURL
        )
        var localUpdated = 0
        var localSkipped = 0
        if folderURL != nil {
            var counts = TunnelTokenApplyCounts()
            mutateDocument { document in
                counts = TunnelLinkedValueUpdater.apply(
                    document: &document,
                    tunnelFlag: flag,
                    stage: stage,
                    escapedPassword: escapedPassword
                )
            }
            localUpdated = counts.variablesUpdated
            localSkipped = counts.skipped
            if localUpdated > 0 {
                saveToDisk(isAutomatic: true)
            }
        }
        let files = others.filesUpdated + (localUpdated > 0 ? 1 : 0)
        let variables = others.variablesUpdated + localUpdated
        let skipped = others.skipped + localSkipped
        if variables == 0 && skipped == 0 {
            return " Nenhuma variável ligada a «\(flag)»."
        }
        var text = " \(variables) variável(is) em \(files) arquivo(s)."
        if skipped > 0 {
            text += " \(skipped) ignorada(s) (URL sem senha)."
        }
        return text
    }

    public func valueBinding(forKey key: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.document.variable(forKey: key)?.displayValue ?? ""
            },
            set: { [weak self] newValue in
                self?.updateVariableValue(key: key, value: newValue)
            }
        )
    }

    public func addVariable() {
        mutateDocument { document in
            var counter = 1
            var key = "NEW_VAR"
            while document.variable(forKey: key) != nil {
                counter += 1
                key = "NEW_VAR_\(counter)"
            }
            var variable = EnvVariable(key: key, values: [:], activeEnvironment: .local)
            for env in EnvStage.ordered {
                variable.values[env] = ""
            }
            document.upsertVariable(variable)
        }
    }

    public func importPastedText(
        _ text: String,
        mode: EnvDocumentMerger.ImportMode,
        targetEnvironment: EnvStage
    ) {
        let multi = EnvDocumentMerger.detectMultiSection(text)
        var merged = EnvDocumentMerger.applyImport(
            existing: document,
            pastedText: text,
            mode: mode,
            targetEnvironment: targetEnvironment,
            isMultiSectionPaste: multi
        )
        if let folderURL {
            let metadata = StudioMetadataStore.load(from: folderURL)
            StudioMetadataStore.applyTags(to: &merged, metadata: metadata)
        }
        document = merged
        refreshDirtyState()
        statusMessage = autoSaveEnabled
            ? "Importação aplicada (salvando automaticamente…)"
            : "Importação aplicada (salve para persistir)"
        scheduleAutoSaveIfNeeded()
    }

    public func exportFlatText(omitSecretLines: Bool) -> String {
        ExportRedactor.exportFlat(
            document: document,
            options: ExportOptions(omitSecretLines: omitSecretLines)
        )
    }

    /// Aplica URL de conexão na variável nomeada, no bloco do ambiente indicado.
    public func applyConnectionString(
        envVarName: String,
        url: String,
        environment: EnvStage
    ) {
        mutateDocument { document in
            if let index = document.variables.firstIndex(where: { $0.key == envVarName }) {
                document.variables[index].values[environment] = url
                document.variables[index].activeEnvironment = environment
                return
            }
            var variable = EnvVariable(
                key: envVarName,
                values: [:],
                activeEnvironment: environment
            )
            for env in EnvStage.ordered {
                variable.values[env] = env == environment ? url : ""
            }
            document.upsertVariable(variable)
        }
        statusMessage = "\(envVarName) atualizado (\(environment.displayName))."
    }

    private func mutateDocument(_ transform: (inout EnvDocument) -> Void) {
        var copy = document
        transform(&copy)
        document = copy
        refreshDirtyState()
        scheduleAutoSaveIfNeeded()
    }

    private func cancelAutoSaveTask() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    private func scheduleAutoSaveIfNeeded() {
        guard autoSaveEnabled, folderURL != nil, hasUnsavedChanges else {
            return
        }
        cancelAutoSaveTask()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoSaveDebounceNs)
            guard !Task.isCancelled else { return }
            guard autoSaveEnabled, folderURL != nil, hasUnsavedChanges else {
                return
            }
            saveToDisk(isAutomatic: true)
        }
    }

    private func captureSavedSnapshot() {
        savedEnvSnapshot = EnvSectionWriter.render(document)
        savedMetadataSnapshot = metadataSnapshotString()
        hasUnsavedChanges = false
    }

    private func refreshDirtyState() {
        guard folderURL != nil else {
            hasUnsavedChanges = false
            return
        }
        let envNow = EnvSectionWriter.render(document)
        let metaNow = metadataSnapshotString()
        if savedEnvSnapshot == nil {
            hasUnsavedChanges = !envNow.isEmpty || !(metaNow == "{}")
        } else {
            hasUnsavedChanges = envNow != savedEnvSnapshot || metaNow != savedMetadataSnapshot
        }
    }

    private func metadataSnapshotString() -> String {
        let metadata = StudioMetadataStore.metadata(from: document)
        guard let data = try? JSONEncoder().encode(metadata),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

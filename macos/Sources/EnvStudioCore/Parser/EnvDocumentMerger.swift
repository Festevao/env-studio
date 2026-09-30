import Foundation

public enum EnvDocumentMerger {
    public enum ImportMode {
        case replace
        case merge
    }

    public static func applyImport(
        existing: EnvDocument,
        pastedText: String,
        mode: ImportMode,
        targetEnvironment: EnvStage,
        isMultiSectionPaste: Bool
    ) -> EnvDocument {
        if mode == .replace {
            if isMultiSectionPaste {
                return EnvSectionParser.parse(pastedText).document
            }
            return bootstrapFromFlat(pastedText, activeEnvironment: targetEnvironment)
        }

        var document = existing
        if isMultiSectionPaste {
            let imported = EnvSectionParser.parse(pastedText).document
            for variable in imported.variables {
                mergeVariable(into: &document, variable: variable)
            }
            return document
        }

        let flat = EnvSectionParser.parseFlat(pastedText, targetEnvironment: targetEnvironment)
        for variable in flat.variables {
            if var current = document.variable(forKey: variable.key) {
                current.values[targetEnvironment] = variable.values[targetEnvironment]
                document.upsertVariable(current)
            } else {
                var newVar = variable
                for env in EnvStage.ordered where env != targetEnvironment {
                    newVar.values[env] = newVar.values[env] ?? ""
                }
                document.upsertVariable(newVar)
            }
        }
        return document
    }

    private static func bootstrapFromFlat(
        _ text: String,
        activeEnvironment: EnvStage
    ) -> EnvDocument {
        let flat = EnvSectionParser.parseFlat(text, targetEnvironment: activeEnvironment)
        let variables: [EnvVariable] = flat.variables.map { variable in
            var copy = variable
            for env in EnvStage.ordered {
                if copy.values[env] == nil {
                    copy.values[env] = env == activeEnvironment
                        ? (copy.values[activeEnvironment] ?? "")
                        : ""
                }
            }
            copy.activeEnvironment = activeEnvironment
            return copy
        }
        return EnvDocument(variables: variables, keyOrder: flat.keyOrder)
    }

    private static func mergeVariable(into document: inout EnvDocument, variable: EnvVariable) {
        if var current = document.variable(forKey: variable.key) {
            for (env, value) in variable.values {
                current.values[env] = value
            }
            current.activeEnvironment = variable.activeEnvironment
            document.upsertVariable(current)
        } else {
            document.upsertVariable(variable)
        }
    }

    public static func detectMultiSection(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            EnvStage.parseSectionHeader(String(line)) != nil
        }
    }
}

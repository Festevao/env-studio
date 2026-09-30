import Foundation

public struct EnvVariable: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var values: [EnvStage: String]
    public var activeEnvironment: EnvStage
    public var tags: Set<VariableTag>
    /// Flag do túnel SSM (`mysql`, `arenas-mysql`) ligada a esta variável.
    public var tunnelFlag: String?

    public init(
        key: String,
        values: [EnvStage: String] = [:],
        activeEnvironment: EnvStage = .local,
        tags: Set<VariableTag> = [],
        tunnelFlag: String? = nil
    ) {
        self.key = key
        self.values = values
        self.activeEnvironment = activeEnvironment
        self.tags = tags
        self.tunnelFlag = tunnelFlag
    }

    public var displayValue: String {
        values[activeEnvironment] ?? ""
    }

    public mutating func setDisplayValue(_ value: String) {
        values[activeEnvironment] = value
    }
}

public struct EnvDocument: Equatable, Sendable {
    public var variables: [EnvVariable]
    public var keyOrder: [String]

    public init(variables: [EnvVariable] = [], keyOrder: [String] = []) {
        self.variables = variables
        self.keyOrder = keyOrder
    }

    public static func masterSelection(from variables: [EnvVariable]) -> MasterEnvironmentSelection {
        guard let first = variables.first else { return .uniform(.local) }
        let env = first.activeEnvironment
        for variable in variables.dropFirst() where variable.activeEnvironment != env {
            return .mixed
        }
        return .uniform(env)
    }

    public mutating func setMasterEnvironment(_ environment: EnvStage) {
        for index in variables.indices {
            variables[index].activeEnvironment = environment
        }
    }

    public func variable(forKey key: String) -> EnvVariable? {
        variables.first { $0.key == key }
    }

    public mutating func upsertVariable(_ variable: EnvVariable) {
        if let index = variables.firstIndex(where: { $0.key == variable.key }) {
            variables[index] = variable
        } else {
            variables.append(variable)
            if !keyOrder.contains(variable.key) {
                keyOrder.append(variable.key)
            }
        }
    }
}

import Foundation

public enum TunnelEnvironment: String, CaseIterable, Identifiable, Codable, Sendable {
    case dev
    case hom
    case prod

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

public enum TunnelDriver: String, Codable, Sendable {
    case mysql
    case postgres
    case none
}

public struct TunnelDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String { flag }
    public var flag: String
    public var aliases: String
    public var title: String
    public var remoteHost: String
    public var remotePort: Int
    public var localPort: Int
    public var generateToken: Bool
    public var database: String
    public var driver: TunnelDriver
    public var envVarName: String?

    public init(
        flag: String,
        aliases: String = "",
        title: String,
        remoteHost: String,
        remotePort: Int,
        localPort: Int,
        generateToken: Bool = false,
        database: String = "",
        driver: TunnelDriver = .none,
        envVarName: String? = nil
    ) {
        self.flag = flag
        self.aliases = aliases
        self.title = title
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localPort = localPort
        self.generateToken = generateToken
        self.database = database
        self.driver = driver
        self.envVarName = envVarName
    }

    public var isAvailable: Bool {
        !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var resolvedEnvVarName: String {
        if let envVarName, !envVarName.isEmpty { return envVarName }
        return TunnelDefinition.defaultEnvVarName(forFlag: flag)
    }

    public static func defaultEnvVarName(forFlag flag: String) -> String {
        if flag == "mysql" { return "MYSQL_DATABASE_URL" }
        let upper = flag.uppercased().replacingOccurrences(of: "-", with: "_")
        return "\(upper)_DATABASE_URL"
    }

    public func tunnelKey(environment: TunnelEnvironment) -> String {
        "\(environment.rawValue)-\(flag)"
    }
}

public struct AwsEnvironmentConfig: Codable, Equatable, Sendable {
    public var awsProfileName: String
    public var region: String
    public var ssmTargetInstanceId: String
    public var rdsIamUsername: String
    public var rdsCaPath: String
    public var tunnels: [TunnelDefinition]

    public init(
        awsProfileName: String,
        region: String,
        ssmTargetInstanceId: String,
        rdsIamUsername: String = "felipi.trindade",
        rdsCaPath: String = "~/.aws/rds/global-bundle.pem",
        tunnels: [TunnelDefinition] = []
    ) {
        self.awsProfileName = awsProfileName
        self.region = region
        self.ssmTargetInstanceId = ssmTargetInstanceId
        self.rdsIamUsername = rdsIamUsername
        self.rdsCaPath = rdsCaPath
        self.tunnels = tunnels
    }
}

public struct ConnectivityConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var awsCliPath: String?
    public var environments: [String: AwsEnvironmentConfig]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        awsCliPath: String? = nil,
        environments: [String: AwsEnvironmentConfig] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.awsCliPath = awsCliPath
        self.environments = environments
    }

    public func config(for environment: TunnelEnvironment) -> AwsEnvironmentConfig? {
        environments[environment.rawValue]
    }

    public mutating func setConfig(_ config: AwsEnvironmentConfig, for environment: TunnelEnvironment) {
        environments[environment.rawValue] = config
    }
}

public enum TunnelListenState: Equatable, Sendable {
    case closed
    case listeningOwned
    case listeningExternal(pids: [Int32])
    /// Mesma porta local já usada por outro túnel (ex.: MySQL dev em 26524 — prod não está aberto).
    case portUsedByOtherTunnel(ownerKey: String)
}

public struct RdsTokenSession: Equatable, Sendable {
    public var rawToken: String
    public var databaseURL: String
    public var envVarName: String
    public var generatedAt: Date
    public var expiresAt: Date

    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public var remainingSeconds: Int {
        max(0, Int(expiresAt.timeIntervalSince(Date())))
    }
}

public enum RdsPasswordTestResult: Equatable, Sendable {
    case none
    case success(Date)
    case failure(String, Date)
}

public extension ConnectivityConfig {
    func allTunnelFingerprints() -> [TunnelOpenFingerprint] {
        var result: [TunnelOpenFingerprint] = []
        for environment in TunnelEnvironment.allCases {
            guard let envConfig = config(for: environment) else { continue }
            for tunnel in envConfig.tunnels where tunnel.isAvailable {
                let key = tunnel.tunnelKey(environment: environment)
                result.append(
                    TunnelOpenFingerprint.make(
                        tunnelKey: key,
                        tunnel: tunnel,
                        awsProfileName: envConfig.awsProfileName,
                        region: envConfig.region,
                        ssmTargetInstanceId: envConfig.ssmTargetInstanceId
                    )
                )
            }
        }
        return result
    }
}

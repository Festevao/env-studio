import Foundation

public struct TunnelOpenFingerprint: Codable, Equatable, Sendable {
    public var tunnelKey: String
    public var localPort: Int
    public var awsProfileName: String
    public var region: String
    public var ssmTargetInstanceId: String
    public var remoteHost: String
    public var remotePort: Int

    public init(
        tunnelKey: String,
        localPort: Int,
        awsProfileName: String,
        region: String,
        ssmTargetInstanceId: String,
        remoteHost: String,
        remotePort: Int
    ) {
        self.tunnelKey = tunnelKey
        self.localPort = localPort
        self.awsProfileName = awsProfileName
        self.region = region
        self.ssmTargetInstanceId = ssmTargetInstanceId
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    public static func make(
        tunnelKey: String,
        tunnel: TunnelDefinition,
        awsProfileName: String,
        region: String,
        ssmTargetInstanceId: String
    ) -> TunnelOpenFingerprint {
        TunnelOpenFingerprint(
            tunnelKey: tunnelKey,
            localPort: tunnel.localPort,
            awsProfileName: awsProfileName,
            region: region,
            ssmTargetInstanceId: ssmTargetInstanceId,
            remoteHost: tunnel.remoteHost,
            remotePort: tunnel.remotePort
        )
    }

    public func matchesSSMParameters(host: String, remotePort: Int, localPort: Int) -> Bool {
        remoteHost == host && self.remotePort == remotePort && self.localPort == localPort
    }
}

public struct ActiveTunnelSessionsFile: Codable, Equatable, Sendable {
    public var sessions: [TunnelOpenFingerprint]

    public init(sessions: [TunnelOpenFingerprint] = []) {
        self.sessions = sessions
    }
}

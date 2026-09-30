import Foundation

public enum ConnectivityDefaults {
    public static func seededConfig() -> ConnectivityConfig {
        var config = ConnectivityConfig()
        for environment in TunnelEnvironment.allCases {
            config.setConfig(emptyEnvironment(), for: environment)
        }
        return config
    }

    public static func restoreEnvironment(_: TunnelEnvironment) -> AwsEnvironmentConfig {
        emptyEnvironment()
    }

    private static func emptyEnvironment() -> AwsEnvironmentConfig {
        AwsEnvironmentConfig(
            awsProfileName: "",
            region: "us-east-1",
            ssmTargetInstanceId: "",
            rdsIamUsername: "",
            tunnels: []
        )
    }
}

import Foundation

public enum ConnectivityDefaults {
    public static func seededConfig() -> ConnectivityConfig {
        var config = ConnectivityConfig()
        config.setConfig(devEnvironment(), for: .dev)
        config.setConfig(homEnvironment(), for: .hom)
        config.setConfig(prodEnvironment(), for: .prod)
        return config
    }

    public static func restoreEnvironment(_ environment: TunnelEnvironment) -> AwsEnvironmentConfig {
        switch environment {
        case .dev: return devEnvironment()
        case .hom: return homEnvironment()
        case .prod: return prodEnvironment()
        }
    }

    private static func devEnvironment() -> AwsEnvironmentConfig {
        AwsEnvironmentConfig(
            awsProfileName: "dev",
            region: "us-east-1",
            ssmTargetInstanceId: "i-04b4e03afa6f0c6dc",
            tunnels: [
                TunnelDefinition(
                    flag: "mysql",
                    aliases: "m,sql",
                    title: "MySQL",
                    remoteHost: "medcof-oficina.ckzw0e6wyjvy.us-east-1.rds.amazonaws.com",
                    remotePort: 3306,
                    localPort: 26524,
                    generateToken: true,
                    database: "medcof",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "arenas-mysql",
                    aliases: "a,arenas",
                    title: "MySQL ARENAS",
                    remoteHost: "medcof-arenas-rds.ckzw0e6wyjvy.us-east-1.rds.amazonaws.com",
                    remotePort: 5432,
                    localPort: 26525,
                    generateToken: false,
                    database: "arenas",
                    driver: .postgres
                ),
                TunnelDefinition(
                    flag: "sica-rds",
                    aliases: "s,sica",
                    title: "SICA RDS",
                    remoteHost: "",
                    remotePort: 3306,
                    localPort: 26526,
                    generateToken: false,
                    database: "sica",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "rabbit-amqp",
                    aliases: "rq,amqp",
                    title: "RabbitMQ AMQP",
                    remoteHost: "b-4e14d787-a18a-4245-b65f-4751b582f72d.mq.us-east-1.on.aws",
                    remotePort: 5671,
                    localPort: 5671,
                    driver: .none
                ),
                TunnelDefinition(
                    flag: "rabbit-web",
                    aliases: "rw,rweb",
                    title: "RabbitMQ WEB",
                    remoteHost: "b-4e14d787-a18a-4245-b65f-4751b582f72d.mq.us-east-1.on.aws",
                    remotePort: 443,
                    localPort: 8443,
                    driver: .none
                ),
            ]
        )
    }

    private static func homEnvironment() -> AwsEnvironmentConfig {
        AwsEnvironmentConfig(
            awsProfileName: "hom",
            region: "us-east-1",
            ssmTargetInstanceId: "i-0800da09ca5dc93c5",
            tunnels: [
                TunnelDefinition(
                    flag: "mysql",
                    aliases: "m,sql",
                    title: "MySQL",
                    remoteHost: "medcof-oficina.c2fmsagyah5s.us-east-1.rds.amazonaws.com",
                    remotePort: 3306,
                    localPort: 26524,
                    generateToken: true,
                    database: "medcof",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "arenas-mysql",
                    aliases: "a,arenas",
                    title: "MySQL ARENAS",
                    remoteHost: "",
                    remotePort: 5432,
                    localPort: 26525,
                    driver: .postgres
                ),
                TunnelDefinition(
                    flag: "sica-rds",
                    aliases: "s,sica",
                    title: "SICA RDS",
                    remoteHost: "sica-rds.c2fmsagyah5s.us-east-1.rds.amazonaws.com",
                    remotePort: 3306,
                    localPort: 26526,
                    generateToken: false,
                    database: "sica",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "rabbit-amqp",
                    aliases: "rq,amqp",
                    title: "RabbitMQ AMQP",
                    remoteHost: "b-c1827fc8-109e-46f8-b343-9c215ff0f27d.mq.us-east-1.on.aws",
                    remotePort: 5671,
                    localPort: 5671,
                    driver: .none
                ),
                TunnelDefinition(
                    flag: "rabbit-web",
                    aliases: "rw,rweb",
                    title: "RabbitMQ WEB",
                    remoteHost: "b-c1827fc8-109e-46f8-b343-9c215ff0f27d.mq.us-east-1.on.aws",
                    remotePort: 15671,
                    localPort: 8443,
                    driver: .none
                ),
            ]
        )
    }

    private static func prodEnvironment() -> AwsEnvironmentConfig {
        AwsEnvironmentConfig(
            awsProfileName: "prod",
            region: "us-east-1",
            ssmTargetInstanceId: "i-02cb5cdec0236b148",
            tunnels: [
                TunnelDefinition(
                    flag: "mysql",
                    aliases: "m,sql",
                    title: "MySQL",
                    remoteHost: "medcof-rds.cq5am0qsa12l.us-east-1.rds.amazonaws.com",
                    remotePort: 3306,
                    localPort: 26524,
                    generateToken: true,
                    database: "medcof",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "arenas-mysql",
                    aliases: "a,arenas",
                    title: "MySQL ARENAS",
                    remoteHost: "",
                    remotePort: 5432,
                    localPort: 26525,
                    driver: .postgres
                ),
                TunnelDefinition(
                    flag: "sica-rds",
                    aliases: "s,sica",
                    title: "SICA RDS",
                    remoteHost: "sica-rds.cq5am0qsa12l.us-east-1.rds.amazonaws.com",
                    remotePort: 3306,
                    localPort: 26526,
                    generateToken: false,
                    database: "sica",
                    driver: .mysql
                ),
                TunnelDefinition(
                    flag: "rabbit-amqp",
                    aliases: "rq,amqp",
                    title: "RabbitMQ AMQP",
                    remoteHost: "b-f824ddfd-e331-406b-86b7-e44403e6c620.mq.us-east-1.on.aws",
                    remotePort: 5671,
                    localPort: 5671,
                    driver: .none
                ),
                TunnelDefinition(
                    flag: "rabbit-web",
                    aliases: "rw,rweb",
                    title: "RabbitMQ WEB",
                    remoteHost: "b-f824ddfd-e331-406b-86b7-e44403e6c620.mq.us-east-1.on.aws",
                    remotePort: 443,
                    localPort: 8443,
                    driver: .none
                ),
            ]
        )
    }
}

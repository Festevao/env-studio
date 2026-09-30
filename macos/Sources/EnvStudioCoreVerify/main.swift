import EnvStudioCore
import EnvStudioConnectivity
import Foundation

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private let fixture = """
# local --------------------------------------------------------

EXAMPLE_VAR=local_value

# dev ---------------------------------------------------------

#EXAMPLE_VAR=dev_value

# hom --------------------------------------------------------

#EXAMPLE_VAR=hom_value

# prod --------------------------------------------------------

#EXAMPLE_VAR=prod_value
"""

@main
enum EnvStudioCoreVerify {
    static func main() {
        testParseActiveLocal()
        testWriterRoundTrip()
        testSetMasterToProd()
        testSecretExport()
        testOmitSecretLinesExport()
        testSqlRedact()
        testGenericConnectionRedact()
        testNormalizedSingleTag()
        testConnectivityDatabaseURL()
        testPortMonitorParse()
        testTunnelSessionRegistryCrossEnv()
        testTunnelSSMParameterParse()
        testTunnelRegistryPruneExemptWhileOpening()
        testConnectivityTunnelCatalog()
        testConnectionPasswordReplace()
        testMetadataWithoutTunnelFlags()
        print("EnvStudioCoreVerify: all checks passed")
    }

    static func testParseActiveLocal() {
        let result = EnvSectionParser.parse(fixture)
        assert(result.document.variables.count == 1, "variable count")
        let variable = result.document.variables[0]
        assert(variable.key == "EXAMPLE_VAR", "key")
        assert(variable.activeEnvironment == .local, "active local")
        assert(variable.values[.local] == "local_value", "local value")
    }

    static func testWriterRoundTrip() {
        let parsed = EnvSectionParser.parse(fixture).document
        let rendered = EnvSectionWriter.render(parsed)
        assert(rendered.contains("EXAMPLE_VAR=local_value"), "active line")
        assert(rendered.contains("#EXAMPLE_VAR=dev_value"), "commented dev")
        let again = EnvSectionParser.parse(rendered).document
        assert(again.variables.first?.activeEnvironment == .local, "round-trip active")
    }

    static func testSetMasterToProd() {
        var document = EnvSectionParser.parse(fixture).document
        document.setMasterEnvironment(.prod)
        let rendered = EnvSectionWriter.render(document)
        assert(rendered.contains("EXAMPLE_VAR=prod_value"), "prod active")
        let reparsed = EnvSectionParser.parse(rendered)
        assert(reparsed.document.variables.first?.activeEnvironment == .prod, "reparsed prod")
    }

    static func testSecretExport() {
        let variable = EnvVariable(
            key: "JWT_SECRET",
            values: [.local: "super-secret"],
            activeEnvironment: .local,
            tags: [.secret]
        )
        let document = EnvDocument(variables: [variable], keyOrder: ["JWT_SECRET"])
        let text = ExportRedactor.exportFlat(document: document)
        assert(text == "JWT_SECRET=\n", "secret export empty value")
    }

    static func testOmitSecretLinesExport() {
        let variable = EnvVariable(
            key: "JWT_SECRET",
            values: [.local: "super-secret"],
            activeEnvironment: .local,
            tags: [.secret]
        )
        let document = EnvDocument(variables: [variable], keyOrder: ["JWT_SECRET"])
        let text = ExportRedactor.exportFlat(
            document: document,
            options: ExportOptions(omitSecretLines: true)
        )
        assert(text.isEmpty, "omit secret lines")
    }

    static func testNormalizedSingleTag() {
        let merged = VariableTag.normalizedSingle(from: [.sqlStringConn, .secret])
        assert(merged == [.secret], "secret wins over connection tag")
        let single = VariableTag.normalizedSingle(from: [.mongoStringConn])
        assert(single == [.mongoStringConn], "single tag preserved")
    }

    static func testSqlRedact() {
        let url = "mysql://user:pass%40word@127.0.0.1:3306/medcof?sslmode=require"
        let redacted = ExportRedactor.redact(value: url, tags: [.sqlStringConn])
        assert(
            redacted
                == "mysql://<user>:<password>@127.0.0.1:3306/medcof?sslmode=require",
            "sql redact"
        )
    }

    static func testGenericConnectionRedact() {
        let url = "mysql2://admin:s3cret@db.internal:5432/app"
        let redacted = ExportRedactor.redact(value: url, tags: [.sqlStringConn])
        assert(
            redacted == "mysql2://<user>:<password>@db.internal:5432/app",
            "generic url redact fallback"
        )
    }

    static func testConnectivityDatabaseURL() {
        let built = DatabaseURLBuilder.buildDatabaseURL(
            driver: .mysql,
            username: "user",
            token: "a@b",
            localPort: 26524,
            database: "medcof",
            sslCertPath: "/tmp/cert.pem"
        )
        assert(built.contains("a%40b"), "token encoded in url")
    }

    static func testPortMonitorParse() {
        let fixture = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        session   42 user   22u  IPv4 0x0      0t0  TCP 127.0.0.1:26524 (LISTEN)
        """
        let pids = PortMonitor.parseListeningPids(lsofOutput: fixture, localPort: 26524)
        assert(pids == [42], "lsof parse")
    }

    static func testTunnelSessionRegistryCrossEnv() {
        let registry = TunnelSessionRegistry(loadPersisted: false)
        let devFingerprint = TunnelOpenFingerprint(
            tunnelKey: "dev-mysql",
            localPort: 26524,
            awsProfileName: "medcof-dev",
            region: "us-east-1",
            ssmTargetInstanceId: "i-dev",
            remoteHost: "dev-db.internal",
            remotePort: 3306
        )
        registry.register(devFingerprint)
        let homFingerprint = TunnelOpenFingerprint(
            tunnelKey: "hom-mysql",
            localPort: 26524,
            awsProfileName: "medcof-hom",
            region: "us-east-1",
            ssmTargetInstanceId: "i-hom",
            remoteHost: "hom-db.internal",
            remotePort: 3306
        )
        let known = [devFingerprint, homFingerprint]
        let homState = registry.resolveListenState(
            tunnelKey: "hom-mysql",
            localPort: 26524,
            listeningPids: [999],
            knownFingerprints: known
        )
        if case .portUsedByOtherTunnel(let owner) = homState {
            assert(owner == "dev-mysql", "hom blocked by dev owner")
        } else {
            assert(false, "hom should be portUsedByOtherTunnel")
        }
        let devState = registry.resolveListenState(
            tunnelKey: "dev-mysql",
            localPort: 26524,
            listeningPids: [999],
            knownFingerprints: known
        )
        assert(devState == .listeningOwned, "dev owned")
        let closed = registry.resolveListenState(
            tunnelKey: "dev-mysql",
            localPort: 26524,
            listeningPids: [],
            knownFingerprints: known
        )
        assert(closed == .closed, "empty pids closed without unregister")
    }

    static func testTunnelRegistryPruneExemptWhileOpening() {
        let registry = TunnelSessionRegistry(loadPersisted: false)
        let localPort = 47_651
        let fingerprint = TunnelOpenFingerprint(
            tunnelKey: "dev-mysql",
            localPort: localPort,
            awsProfileName: "dev",
            region: "us-east-1",
            ssmTargetInstanceId: "i-dev",
            remoteHost: "db.internal",
            remotePort: 3306
        )
        registry.register(fingerprint)
        registry.pruneStaleOwnership(exemptTunnelKeys: ["dev-mysql"])
        assert(registry.isRegistered(tunnelKey: "dev-mysql"), "opening exempt keeps registry")
        registry.pruneStaleOwnership(exemptTunnelKeys: [])
        assert(!registry.isRegistered(tunnelKey: "dev-mysql"), "prune clears when port empty")
        let launching = registry.resolveListenState(
            tunnelKey: "dev-mysql",
            localPort: localPort,
            listeningPids: [42],
            knownFingerprints: [fingerprint],
            activeLauncherKeys: ["dev-mysql"]
        )
        assert(launching == .listeningOwned, "launcher active counts as owned")
    }

    static func testTunnelSSMParameterParse() {
        let command = """
        /opt/homebrew/bin/aws ssm start-session --parameters host=db.example,portNumber=3306,localPortNumber=26524
        """
        let parsed = TunnelProcessInspector.parseSSMParameters(from: command)
        assert(parsed?.host == "db.example", "host parse")
        assert(parsed?.remotePort == 3306, "remote port parse")
        assert(parsed?.localPort == 26524, "local port parse")
        guard let params = parsed else {
            assert(false, "parsed params")
            return
        }
        let dev = TunnelOpenFingerprint(
            tunnelKey: "dev-mysql",
            localPort: 26524,
            awsProfileName: "p",
            region: "us-east-1",
            ssmTargetInstanceId: "i",
            remoteHost: "db.example",
            remotePort: 3306
        )
        let hom = TunnelOpenFingerprint(
            tunnelKey: "hom-mysql",
            localPort: 26524,
            awsProfileName: "p",
            region: "us-east-1",
            ssmTargetInstanceId: "i",
            remoteHost: "other.example",
            remotePort: 3306
        )
        assert(
            dev.matchesSSMParameters(
                host: params.host,
                remotePort: params.remotePort,
                localPort: params.localPort
            ),
            "fingerprint match"
        )
        assert(
            !hom.matchesSSMParameters(
                host: params.host,
                remotePort: params.remotePort,
                localPort: params.localPort
            ),
            "fingerprint mismatch other env"
        )
    }

    static func testConnectivityTunnelCatalog() {
        assert(TunnelFlagValidator.normalize("My-Service_1") == nil, "invalid chars")
        assert(TunnelFlagValidator.normalize("  my-api  ") == "my-api", "normalize flag")
        var config = ConnectivityConfig()
        let tunnel = TunnelDefinition(
            flag: "custom-svc",
            title: "Custom",
            remoteHost: "",
            remotePort: 443,
            localPort: 8443,
            driver: .none
        )
        do {
            try config.addTunnelAcrossEnvironments(tunnel)
        } catch {
            assert(false, "add failed")
            return
        }
        assert(config.containsTunnel(flag: "custom-svc"), "added all envs")
        assert(
            config.tunnel(flag: "custom-svc", environment: .hom)?.localPort == 8443,
            "hom entry"
        )
        do {
            try config.addTunnelAcrossEnvironments(tunnel)
            assert(false, "duplicate should throw")
        } catch TunnelCatalogError.duplicateFlag {
            // expected
        } catch {
            assert(false, "wrong error")
        }
        do {
            try config.removeTunnelAcrossEnvironments(flag: "custom-svc")
        } catch {
            assert(false, "remove failed")
            return
        }
        assert(!config.containsTunnel(flag: "custom-svc"), "removed all envs")
    }

    static func testConnectionPasswordReplace() {
        let url = "mysql://user:old@127.0.0.1:26524/medcof?sslmode=require"
        let next = ConnectionStringPassword.replacingPassword(
            in: url,
            escapedPassword: "a%40b"
        )
        assert(
            next == "mysql://user:a%40b@127.0.0.1:26524/medcof?sslmode=require",
            "password swap"
        )
        assert(
            ConnectionStringPassword.replacingPassword(
                in: "mysql://127.0.0.1/db",
                escapedPassword: "x"
            ) == nil,
            "no userinfo"
        )
        var document = EnvDocument(
            variables: [
                EnvVariable(
                    key: "MYSQL_DATABASE_URL",
                    values: [.dev: url],
                    activeEnvironment: .dev,
                    tags: [.sqlStringConn],
                    tunnelFlag: "mysql"
                ),
                EnvVariable(
                    key: "DB_PASSWORD",
                    values: [.dev: "old", .prod: "keep"],
                    activeEnvironment: .dev,
                    tags: [.sqlPassword],
                    tunnelFlag: "mysql"
                ),
            ],
            keyOrder: ["MYSQL_DATABASE_URL", "DB_PASSWORD"]
        )
        let counts = TunnelLinkedValueUpdater.apply(
            document: &document,
            tunnelFlag: "mysql",
            stage: .dev,
            escapedPassword: "tok%40en"
        )
        assert(counts.variablesUpdated == 2, "two updates")
        assert(
            document.variable(forKey: "MYSQL_DATABASE_URL")?.values[.dev]
                == "mysql://user:tok%40en@127.0.0.1:26524/medcof?sslmode=require",
            "url password only"
        )
        assert(
            document.variable(forKey: "DB_PASSWORD")?.values[.dev] == "tok%40en",
            "escaped password value"
        )
        assert(
            document.variable(forKey: "DB_PASSWORD")?.values[.prod] == "keep",
            "other stage untouched"
        )
    }

    static func testMetadataWithoutTunnelFlags() {
        let json = #"{"variables":{"A":["secret"]}}"#
        let decoded = try? JSONDecoder().decode(StudioMetadata.self, from: Data(json.utf8))
        assert(decoded?.variables["A"] == ["secret"], "legacy tags")
        assert(decoded?.tunnelFlags.isEmpty == true, "missing tunnelFlags defaults empty")
    }
}

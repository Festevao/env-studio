import EnvStudioConnectivity
import XCTest

final class ConnectivityTests: XCTestCase {
    func testDatabaseURLEncoding() {
        let url = DatabaseURLBuilder.buildDatabaseURL(
            driver: .mysql,
            username: "user",
            token: "pass@word",
            localPort: 26524,
            database: "medcof",
            sslCertPath: "/tmp/cert.pem"
        )
        XCTAssertTrue(url.contains("pass%40word"))
        XCTAssertTrue(url.hasPrefix("mysql://user:"))
    }

    func testPortMonitorParse() {
        let fixture = """
        COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        session   123 user   22u  IPv4 0xdeadbeef      0t0  TCP 127.0.0.1:26524 (LISTEN)
        """
        let pids = PortMonitor.parseListeningPids(lsofOutput: fixture, localPort: 26524)
        XCTAssertEqual(pids, [123])
    }

    func testDefaultEnvVarName() {
        XCTAssertEqual(
            TunnelDefinition.defaultEnvVarName(forFlag: "mysql"),
            "MYSQL_DATABASE_URL"
        )
        XCTAssertEqual(
            TunnelDefinition.defaultEnvVarName(forFlag: "sica-rds"),
            "SICA_RDS_DATABASE_URL"
        )
    }
}

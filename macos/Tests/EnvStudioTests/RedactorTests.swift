import EnvStudioCore
import XCTest

final class RedactorTests: XCTestCase {
    func testSecretExportsEmptyValue() {
        let variable = EnvVariable(
            key: "JWT_SECRET",
            values: [.local: "super-secret"],
            activeEnvironment: .local,
            tags: [.secret]
        )
        let document = EnvDocument(variables: [variable], keyOrder: ["JWT_SECRET"])
        let text = ExportRedactor.exportFlat(document: document)
        XCTAssertEqual(text, "JWT_SECRET=\n")
    }

    func testSqlStringRedactsUserPassword() {
        let url =
            "mysql://user:pass%40word@127.0.0.1:3306/medcof?sslmode=require"
        let redacted = ExportRedactor.redact(
            value: url,
            tags: [.sqlStringConn]
        )
        XCTAssertEqual(
            redacted,
            "mysql://<user>:<password>@127.0.0.1:3306/medcof?sslmode=require"
        )
    }

    func testMongoRedact() {
        let url = "mongodb+srv://admin:secret@cluster.example.net/mydb"
        let redacted = ExportRedactor.redact(
            value: url,
            tags: [.mongoStringConn]
        )
        XCTAssertTrue(redacted.contains("<user>:<password>@"))
    }
}

import EnvStudioCore
import XCTest

final class ParserWriterTests: XCTestCase {
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

    func testParseActiveLocal() {
        let result = EnvSectionParser.parse(fixture)
        XCTAssertEqual(result.document.variables.count, 1)
        let variable = result.document.variables[0]
        XCTAssertEqual(variable.key, "EXAMPLE_VAR")
        XCTAssertEqual(variable.activeEnvironment, .local)
        XCTAssertEqual(variable.values[.local], "local_value")
        XCTAssertEqual(variable.values[.dev], "dev_value")
        XCTAssertEqual(variable.values[.prod], "prod_value")
    }

    func testWriterRoundTripPreservesActive() {
        let parsed = EnvSectionParser.parse(fixture).document
        let rendered = EnvSectionWriter.render(parsed)
        let again = EnvSectionParser.parse(rendered).document
        XCTAssertEqual(again.variables.first?.activeEnvironment, .local)
        XCTAssertTrue(rendered.contains("EXAMPLE_VAR=local_value"))
        XCTAssertTrue(rendered.contains("#EXAMPLE_VAR=dev_value"))
    }

    func testSetMasterToProdInModel() {
        var document = EnvSectionParser.parse(fixture).document
        document.setMasterEnvironment(.prod)
        let rendered = EnvSectionWriter.render(document)
        XCTAssertTrue(rendered.contains("#EXAMPLE_VAR=local_value"))
        XCTAssertTrue(rendered.contains("EXAMPLE_VAR=prod_value"))
        let reparsed = EnvSectionParser.parse(rendered)
        XCTAssertEqual(reparsed.document.variables.first?.activeEnvironment, .prod)
    }
}

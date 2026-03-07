import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct DetectUnusedCodeToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = DetectUnusedCodeTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "detect_unused_code")
        #expect(schema.description?.contains("Periphery") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = DetectUnusedCodeTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["package_path"] != nil)
        #expect(properties["project"] != nil)
        #expect(properties["schemes"] != nil)
        #expect(properties["retain_public"] != nil)
        #expect(properties["skip_build"] != nil)
        #expect(properties["exclude_targets"] != nil)
        #expect(properties["report_exclude"] != nil)
    }

    @Test
    func `Parses JSON output with unused declarations`() {
        let json = """
        [
          {
            "name": "unusedFunc()",
            "kind": "function.free",
            "hints": ["unused"],
            "accessibility": "internal",
            "location": "/path/to/Foo.swift:12:6",
            "modules": ["MyModule"],
            "ids": ["s:8MyModule10unusedFuncyyF"],
            "attributes": [],
            "modifiers": []
          },
          {
            "name": "OldStruct",
            "kind": "struct",
            "hints": ["unused"],
            "accessibility": "public",
            "location": "/path/to/Bar.swift:5:15",
            "modules": ["MyModule"],
            "ids": ["s:8MyModule9OldStructV"],
            "attributes": [],
            "modifiers": []
          }
        ]
        """
        let results = DetectUnusedCodeTool.parseJSONOutput(json)
        #expect(results.count == 2)
        #expect(results[0].name == "unusedFunc()")
        #expect(results[0].kind == "function.free")
        #expect(results[0].hints == ["unused"])
        #expect(results[0].accessibility == "internal")
        #expect(results[0].file == "/path/to/Foo.swift")
        #expect(results[0].line == 12)
        #expect(results[0].column == 6)
        #expect(results[1].name == "OldStruct")
        #expect(results[1].kind == "struct")
        #expect(results[1].accessibility == "public")
        #expect(results[1].file == "/path/to/Bar.swift")
        #expect(results[1].line == 5)
        #expect(results[1].column == 15)
    }

    @Test
    func `Parses empty JSON array`() {
        let results = DetectUnusedCodeTool.parseJSONOutput("[]")
        #expect(results.isEmpty)
    }

    @Test
    func `Handles invalid JSON gracefully`() {
        let results = DetectUnusedCodeTool.parseJSONOutput("not json")
        #expect(results.isEmpty)
    }

    @Test
    func `Parses multiple hint types`() {
        let json = """
        [
          {
            "name": "helperMethod()",
            "kind": "function.method.instance",
            "hints": ["redundantPublicAccessibility"],
            "accessibility": "public",
            "location": "/path/to/Foo.swift:33:17",
            "modules": ["M"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          },
          {
            "name": "Foundation",
            "kind": "import",
            "hints": ["unusedImport"],
            "accessibility": "internal",
            "location": "/path/to/Bar.swift:1:1",
            "modules": ["M"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          },
          {
            "name": "debugFlag",
            "kind": "var.instance",
            "hints": ["assignOnlyProperty"],
            "accessibility": "internal",
            "location": "/path/to/Baz.swift:10:9",
            "modules": ["M"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          }
        ]
        """
        let results = DetectUnusedCodeTool.parseJSONOutput(json)
        #expect(results.count == 3)
        #expect(results[0].hints == ["redundantPublicAccessibility"])
        #expect(results[1].hints == ["unusedImport"])
        #expect(results[1].kind == "import")
        #expect(results[2].hints == ["assignOnlyProperty"])
    }

    @Test
    func `Formats results grouped by file`() {
        let declarations = [
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "unusedFunc()", kind: "function.free",
                hints: ["unused"], accessibility: "internal",
                file: "/path/to/Foo.swift", line: 12, column: 6,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "OldStruct", kind: "struct",
                hints: ["unused"], accessibility: "internal",
                file: "/path/to/Foo.swift", line: 45, column: 8,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "Foundation", kind: "import",
                hints: ["unusedImport"], accessibility: "internal",
                file: "/path/to/Bar.swift", line: 1, column: 1,
            ),
        ]
        let output = DetectUnusedCodeTool.formatResults(declarations)
        #expect(output.contains("3 unused declaration(s) found:"))
        #expect(output.contains("/path/to/Bar.swift"))
        #expect(output.contains("/path/to/Foo.swift"))
        #expect(output.contains("12:6 func unusedFunc() [unused] (internal)"))
        #expect(output.contains("45:8 struct OldStruct [unused] (internal)"))
        #expect(output.contains("1:1 import Foundation [unusedImport] (internal)"))
    }

    @Test
    func `Format kind maps known kinds correctly`() {
        #expect(DetectUnusedCodeTool.formatKind("function.free") == "func")
        #expect(DetectUnusedCodeTool.formatKind("function.method.instance") == "method")
        #expect(DetectUnusedCodeTool.formatKind("function.method.static") == "static method")
        #expect(DetectUnusedCodeTool.formatKind("function.method.class") == "class method")
        #expect(DetectUnusedCodeTool.formatKind("var.instance") == "property")
        #expect(DetectUnusedCodeTool.formatKind("var.static") == "static property")
        #expect(DetectUnusedCodeTool.formatKind("var.global") == "var")
        #expect(DetectUnusedCodeTool.formatKind("enumelement") == "case")
        #expect(DetectUnusedCodeTool.formatKind("typealias") == "typealias")
        #expect(DetectUnusedCodeTool.formatKind("import") == "import")
        #expect(DetectUnusedCodeTool.formatKind("struct") == "struct")
        #expect(DetectUnusedCodeTool.formatKind("class") == "class")
        #expect(DetectUnusedCodeTool.formatKind("protocol") == "protocol")
    }

    @Test
    func `Parse location handles standard format`() {
        let (file, line, column) = DetectUnusedCodeTool.parseLocation("/path/to/file.swift:42:10")
        #expect(file == "/path/to/file.swift")
        #expect(line == 42)
        #expect(column == 10)
    }

    @Test
    func `Parse location handles missing components`() {
        let (file, line, column) = DetectUnusedCodeTool.parseLocation("/path/to/file.swift")
        #expect(file == "/path/to/file.swift")
        #expect(line == 0)
        #expect(column == 0)
    }
}

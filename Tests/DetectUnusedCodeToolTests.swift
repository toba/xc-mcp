import MCP
import Testing
@testable import XCMCPCore
import Foundation
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
        #expect(properties["format"] != nil)
        #expect(properties["limit"] != nil)
        #expect(properties["kind_filter"] != nil)
        #expect(properties["file_filter"] != nil)
        #expect(properties["result_file"] != nil)
        #expect(properties["mark"] != nil)
        #expect(properties["group_by"] != nil)
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
    func `Formats detail results grouped by file`() {
        let declarations = [
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "unusedFunc()", kind: "function.free",
                hints: ["unused"], accessibility: "internal",
                module: "MyModule",
                file: "/path/to/Foo.swift", line: 12, column: 6,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "OldStruct", kind: "struct",
                hints: ["unused"], accessibility: "internal",
                module: "MyModule",
                file: "/path/to/Foo.swift", line: 45, column: 8,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "Foundation", kind: "import",
                hints: ["unusedImport"], accessibility: "internal",
                module: "MyModule",
                file: "/path/to/Bar.swift", line: 1, column: 1,
            ),
        ]
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatDetail(
            declarations, limit: 0, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )
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

    // MARK: - Summary format tests

    @Test
    func `Summary format shows kind and file breakdown`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/periphery-abc123.json",
        )
        let output = DetectUnusedCodeTool.formatSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/periphery-abc123.json",
            checklistPath: "/tmp/periphery-abc123-checklist.json",
            state: state,
        )

        #expect(output.contains("5 unused declaration(s) in 3 file(s)"))
        #expect(output.contains("By kind:"))
        #expect(output.contains("func"))
        #expect(output.contains("import"))
        #expect(output.contains("property"))
        #expect(output.contains("By file"))
        #expect(output.contains("Results cached: /tmp/periphery-abc123.json"))
    }

    @Test
    func `Summary format shows filtered count`() {
        let declarations = Self.sampleDeclarations()
        let filtered = Array(declarations.prefix(2))
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatSummary(
            filtered, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(output.contains("2 unused declaration(s) in"))
        #expect(output.contains("filtered from 5 total"))
    }

    // MARK: - Detail format tests

    @Test
    func `Detail format shows declarations with cache path`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/periphery-abc123.json",
        )
        let output = DetectUnusedCodeTool.formatDetail(
            declarations, limit: 100, totalUnfiltered: declarations.count,
            cachePath: "/tmp/periphery-abc123.json",
            checklistPath: "/tmp/periphery-abc123-checklist.json",
            state: state,
        )

        #expect(output.contains("5 unused declaration(s) found:"))
        #expect(output.contains("func unusedFunc()"))
        #expect(output.contains("Results cached: /tmp/periphery-abc123.json"))
    }

    @Test
    func `Detail format truncates at limit`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatDetail(
            declarations, limit: 2, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(output.contains("3 more declaration(s) omitted (limit: 2)"))
    }

    @Test
    func `Detail format with limit 0 shows all`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatDetail(
            declarations, limit: 0, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(!output.contains("omitted"))
        #expect(output.contains("5 unused declaration(s) found:"))
    }

    @Test
    func `Detail format shows filtered count`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatDetail(
            Array(declarations.prefix(2)), limit: 100,
            totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(output.contains("filtered from 5 total"))
    }

    // MARK: - Filter tests

    @Test
    func `Kind filter includes matching declarations`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: ["import"], fileFilter: [],
        )

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "Foundation")
    }

    @Test
    func `Kind filter with multiple kinds`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: ["func", "import"], fileFilter: [],
        )

        #expect(filtered.count == 2)
    }

    @Test
    func `File filter includes matching declarations`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: [], fileFilter: ["Foo.swift"],
        )

        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.file.contains("Foo.swift") })
    }

    @Test
    func `File filter with directory substring`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: [], fileFilter: ["/path/to/"],
        )

        #expect(filtered.count == 5) // all match
    }

    @Test
    func `Combined kind and file filters`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: ["func"], fileFilter: ["Foo.swift"],
        )

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "unusedFunc()")
    }

    @Test
    func `Empty filters return all declarations`() {
        let declarations = Self.sampleDeclarations()
        let filtered = DetectUnusedCodeTool.applyFilters(
            declarations, kindFilter: [], fileFilter: [],
        )

        #expect(filtered.count == declarations.count)
    }

    // MARK: - Hash tests

    @Test
    func `Short hash produces 12 char hex string`() throws {
        let hash = DetectUnusedCodeTool.shortHash("test input")
        #expect(hash.count == 12) // 6 bytes * 2 hex chars
        #expect(try hash.allSatisfy(\.isHexDigit))
    }

    @Test
    func `Short hash is deterministic`() {
        let hash1 = DetectUnusedCodeTool.shortHash("same input")
        let hash2 = DetectUnusedCodeTool.shortHash("same input")
        #expect(hash1 == hash2)
    }

    @Test
    func `Short hash differs for different inputs`() {
        let hash1 = DetectUnusedCodeTool.shortHash("input A")
        let hash2 = DetectUnusedCodeTool.shortHash("input B")
        #expect(hash1 != hash2)
    }

    // MARK: - Compact path tests

    @Test
    func `Compact path strips Users prefix`() {
        let result = DetectUnusedCodeTool.compactPath("/Users/jason/Developer/project/Foo.swift")
        #expect(result == "~/Developer/project/Foo.swift")
    }

    @Test
    func `Compact path leaves non-Users paths unchanged`() {
        let result = DetectUnusedCodeTool.compactPath("/var/tmp/Foo.swift")
        #expect(result == "/var/tmp/Foo.swift")
    }

    // MARK: - Checklist tests

    @Test
    func `Summary includes checklist path when state exists`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/periphery-abc123.json",
        )

        let output = DetectUnusedCodeTool.formatSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/periphery-abc123.json",
            checklistPath: "/tmp/periphery-abc123-checklist.json",
            state: state,
        )

        // Fresh checklist — no progress line (all pending)
        #expect(!output.contains("Progress:"))
        #expect(output.contains("Checklist: /tmp/periphery-abc123-checklist.json"))
        #expect(output.contains("By kind:"))
        #expect(output.contains("func"))
    }

    @Test
    func `Summary shows progress after marking items`() {
        let declarations = Self.sampleDeclarations()
        var state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )

        state.items[1].status = .done
        state.items[1].note = "Removed"
        state.items[2].status = .skipped
        state.items[2].note = "Needed for NSObject"

        let output = DetectUnusedCodeTool.formatSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(output.contains("3 pending"))
        #expect(output.contains("1 done"))
        #expect(output.contains("1 skipped"))
    }

    @Test
    func `ChecklistState round trips through JSON`() throws {
        let state = DetectUnusedCodeTool.ChecklistState(
            version: 1, source: "/tmp/test.json",
            items: [
                .init(id: "file:1:2:foo", status: .pending),
                .init(id: "file:3:4:bar", status: .done, note: "Removed"),
                .init(id: "file:5:6:baz", status: .falsePositive),
            ],
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(
            DetectUnusedCodeTool.ChecklistState.self, from: data,
        )

        #expect(decoded.version == 1)
        #expect(decoded.source == "/tmp/test.json")
        #expect(decoded.items.count == 3)
        #expect(decoded.items[0].status == .pending)
        #expect(decoded.items[1].status == .done)
        #expect(decoded.items[1].note == "Removed")
        #expect(decoded.items[2].status == .falsePositive)
    }

    @Test
    func `checklistPath derivation`() {
        #expect(
            DetectUnusedCodeTool.checklistPath(forCache: "/tmp/periphery-abc123.json")
                == "/tmp/periphery-abc123-checklist.json",
        )
        #expect(
            DetectUnusedCodeTool.checklistPath(forCache: "/tmp/results.json")
                == "/tmp/results-checklist.json",
        )
    }

    @Test
    func `makeItemID is deterministic`() {
        let decl = DetectUnusedCodeTool.UnusedDeclaration(
            name: "foo()", kind: "function.free",
            hints: ["unused"], accessibility: "internal",
            module: "MyModule",
            file: "/path/to/Foo.swift", line: 12, column: 6,
        )
        let id1 = DetectUnusedCodeTool.makeItemID(decl)
        let id2 = DetectUnusedCodeTool.makeItemID(decl)
        #expect(id1 == id2)
        #expect(id1 == "/path/to/Foo.swift:12:6:foo()")
    }

    @Test
    func `parseMarkAction extracts mark object from arguments`() {
        let arguments: [String: Value] = [
            "mark": .object([
                "indices": .array([.int(1), .int(3)]),
                "status": .string("done"),
                "note": .string("Removed"),
            ]),
        ]
        let action = DetectUnusedCodeTool.parseMarkAction(from: arguments)
        #expect(action != nil)
        #expect(action?.indices == [1, 3])
        #expect(action?.status == .done)
        #expect(action?.note == "Removed")
    }

    @Test
    func `parseMarkAction returns nil for missing mark`() {
        let arguments: [String: Value] = [:]
        #expect(DetectUnusedCodeTool.parseMarkAction(from: arguments) == nil)
    }

    @Test
    func `false_positive is tracked in progress`() {
        let declarations = Self.sampleDeclarations()
        var state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )

        state.items[4].status = .falsePositive
        state.items[4].note = "Used via reflection"

        let output = DetectUnusedCodeTool.formatSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json",
            checklistPath: "/tmp/test-checklist.json",
            state: state,
        )

        #expect(output.contains("4 pending"))
        #expect(output.contains("1 false positive"))
    }

    // MARK: - Group by tests

    @Test
    func `Grouped summary by target shows per-module breakdown`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "target",
        )

        #expect(output.contains("5 unused declaration(s) in 3 file(s)"))
        #expect(output.contains("By target:"))
        #expect(output.contains("Core"))
        #expect(output.contains("Tests"))
        #expect(output.contains("DocX"))
    }

    @Test
    func `Grouped summary by target shows top kinds per group`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "target",
        )

        // Core has func(1) and property(1)
        #expect(output.contains("func (1)"))
        #expect(output.contains("property (1)"))
    }

    @Test
    func `Grouped summary by kind shows per-kind breakdown`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "kind",
        )

        #expect(output.contains("By kind:"))
        #expect(output.contains("property"))
        #expect(output.contains("func"))
        #expect(output.contains("import"))
        #expect(output.contains("method"))
    }

    @Test
    func `Grouped summary by directory groups by last two path components`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "directory",
        )

        #expect(output.contains("By directory:"))
        #expect(output.contains("path/to"))
    }

    @Test
    func `Grouped summary shows filtered count`() {
        let declarations = Self.sampleDeclarations()
        let filtered = Array(declarations.prefix(2))
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            filtered, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "target",
        )

        #expect(output.contains("2 unused declaration(s)"))
        #expect(output.contains("filtered from 5 total"))
    }

    @Test
    func `Grouped summary works with cached results`() {
        let declarations = Self.sampleDeclarations()
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/periphery-abc123.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/periphery-abc123.json",
            checklistPath: "/tmp/periphery-abc123-checklist.json",
            state: state, groupBy: "target",
        )

        #expect(output.contains("Results cached: /tmp/periphery-abc123.json"))
    }

    @Test
    func `directoryGroup extracts last two components`() {
        #expect(
            DetectUnusedCodeTool.directoryGroup("/Users/x/Dev/proj/Core/Sources/Foo.swift")
                == "Core/Sources",
        )
        #expect(
            DetectUnusedCodeTool.directoryGroup("/a/b/File.swift")
                == "a/b",
        )
    }

    @Test
    func `Grouped summary by target handles empty module`() {
        let declarations = [
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "orphan()", kind: "function.free",
                hints: ["unused"], accessibility: "internal",
                module: "",
                file: "/path/to/Orphan.swift", line: 1, column: 1,
            ),
        ]
        let state = DetectUnusedCodeTool.createChecklist(
            from: declarations, cachePath: "/tmp/test.json",
        )
        let output = DetectUnusedCodeTool.formatGroupedSummary(
            declarations, totalUnfiltered: declarations.count,
            cachePath: "/tmp/test.json", checklistPath: "/tmp/test-checklist.json",
            state: state, groupBy: "target",
        )

        #expect(output.contains("(unknown)"))
    }

    @Test
    func `parseJSONOutput extracts module from modules array`() {
        let json = """
        [
          {
            "name": "foo()",
            "kind": "function.free",
            "hints": ["unused"],
            "accessibility": "internal",
            "location": "/path/to/Foo.swift:1:1",
            "modules": ["CoreModule"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          }
        ]
        """
        let results = DetectUnusedCodeTool.parseJSONOutput(json)
        #expect(results.count == 1)
        #expect(results[0].module == "CoreModule")
    }

    @Test
    func `parseJSONOutput uses empty string when modules missing`() {
        let json = """
        [
          {
            "name": "foo()",
            "kind": "function.free",
            "hints": ["unused"],
            "accessibility": "internal",
            "location": "/path/to/Foo.swift:1:1"
          }
        ]
        """
        let results = DetectUnusedCodeTool.parseJSONOutput(json)
        #expect(results.count == 1)
        #expect(results[0].module == "")
    }

    // MARK: - Superfluous ignore comment filtering

    @Test
    func `filterSuperfluousIgnoreComments removes superfluous entries`() {
        let declarations = [
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "unusedFunc()", kind: "function.free",
                hints: ["unused"], accessibility: "internal",
                module: "Core",
                file: "/path/to/Foo.swift", line: 12, column: 6,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "decodedProp", kind: "var.instance",
                hints: ["superfluousIgnoreComment"], accessibility: "internal",
                module: "Core",
                file: "/path/to/Foo.swift", line: 20, column: 9,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "anotherProp", kind: "var.instance",
                hints: ["superfluousIgnoreComment"], accessibility: "internal",
                module: "Core",
                file: "/path/to/Bar.swift", line: 5, column: 9,
            ),
        ]

        let (filtered, removedCount) = DetectUnusedCodeTool
            .filterSuperfluousIgnoreComments(declarations)
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "unusedFunc()")
        #expect(removedCount == 2)
    }

    @Test
    func `filterSuperfluousIgnoreComments keeps all when none superfluous`() {
        let declarations = Self.sampleDeclarations()
        let (filtered, removedCount) = DetectUnusedCodeTool
            .filterSuperfluousIgnoreComments(declarations)
        #expect(filtered.count == declarations.count)
        #expect(removedCount == 0)
    }

    @Test
    func `parseJSONOutput includes superfluous hints for filtering`() {
        let json = """
        [
          {
            "name": "ignoredProp",
            "kind": "var.instance",
            "hints": ["superfluousIgnoreComment"],
            "accessibility": "internal",
            "location": "/path/to/Foo.swift:10:9",
            "modules": ["M"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          },
          {
            "name": "reallyUnused()",
            "kind": "function.free",
            "hints": ["unused"],
            "accessibility": "internal",
            "location": "/path/to/Foo.swift:20:5",
            "modules": ["M"],
            "ids": [],
            "attributes": [],
            "modifiers": []
          }
        ]
        """
        let all = DetectUnusedCodeTool.parseJSONOutput(json)
        #expect(all.count == 2)

        let (filtered, removedCount) = DetectUnusedCodeTool.filterSuperfluousIgnoreComments(all)
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "reallyUnused()")
        #expect(removedCount == 1)
    }

    // MARK: - Helpers

    static func sampleDeclarations() -> [DetectUnusedCodeTool.UnusedDeclaration] {
        [
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "unusedFunc()", kind: "function.free",
                hints: ["unused"], accessibility: "internal",
                module: "Core",
                file: "/path/to/Foo.swift", line: 12, column: 6,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "oldProperty", kind: "var.instance",
                hints: ["unused"], accessibility: "internal",
                module: "Core",
                file: "/path/to/Foo.swift", line: 45, column: 8,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "Foundation", kind: "import",
                hints: ["unusedImport"], accessibility: "internal",
                module: "Tests",
                file: "/path/to/Bar.swift", line: 1, column: 1,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "helperMethod()", kind: "function.method.instance",
                hints: ["unused"], accessibility: "public",
                module: "Tests",
                file: "/path/to/Baz.swift", line: 20, column: 5,
            ),
            DetectUnusedCodeTool.UnusedDeclaration(
                name: "debugFlag", kind: "var.instance",
                hints: ["assignOnlyProperty"], accessibility: "internal",
                module: "DocX",
                file: "/path/to/Baz.swift", line: 10, column: 9,
            ),
        ]
    }
}

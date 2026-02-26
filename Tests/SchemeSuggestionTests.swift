import Testing
@testable import XCMCPCore
import Foundation

@Suite("Scheme Suggestion Tests")
struct SchemeSuggestionTests {
    /// Creates a temporary directory with an `.xcodeproj` containing scheme files.
    /// Returns `(projectRoot, projectPath)`.
    private func createFixture(
        schemes: [String: String],
    ) throws -> (projectRoot: String, projectPath: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scheme-suggestion-\(UUID().uuidString)")
        let projectPath = tempDir.appendingPathComponent("App.xcodeproj").path
        let schemesDir = "\(projectPath)/xcshareddata/xcschemes"

        try FileManager.default.createDirectory(
            atPath: schemesDir, withIntermediateDirectories: true,
        )

        for (name, xml) in schemes {
            let path = "\(schemesDir)/\(name).xcscheme"
            try xml.write(toFile: path, atomically: true, encoding: .utf8)
        }

        return (tempDir.path, projectPath)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func schemeXML(testTargets: [String]) -> String {
        let testables = testTargets.map { target in
            """
                     <TestableReference
                        skipped = "NO">
                        <BuildableReference
                           BuildableIdentifier = "primary"
                           BlueprintIdentifier = "ABC123"
                           BuildableName = "\(target).xctest"
                           BlueprintName = "\(target)"
                           ReferencedContainer = "container:App.xcodeproj">
                        </BuildableReference>
                     </TestableReference>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme version = "1.3">
           <BuildAction>
           </BuildAction>
           <TestAction buildConfiguration = "Debug">
              <Testables>
        \(testables)
              </Testables>
           </TestAction>
        </Scheme>
        """
    }

    @Test("Suggests correct scheme when target not in current scheme")
    func suggestsCorrectScheme() async throws {
        let (root, projectPath) = try createFixture(schemes: [
            "Standard": schemeXML(testTargets: []),
            "TestApp": schemeXML(testTargets: ["TestAppUITests"]),
        ])
        defer { cleanup(root) }

        let output = """
        Testing failed:
            "TestAppUITests" isn't a member of the specified test plan or scheme.
        """

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output, succeeded: false,
                context: "scheme 'Standard' on macOS",
                projectRoot: root,
                projectPath: projectPath,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("TestAppUITests"))
            #expect(message.contains("Did you mean a different scheme?"))
            #expect(message.contains("'TestApp'"))
        }
    }

    @Test("No suggestion when no schemes contain the target")
    func noSuggestionWhenTargetNotFound() async throws {
        let (root, projectPath) = try createFixture(schemes: [
            "Standard": schemeXML(testTargets: []),
            "OtherScheme": schemeXML(testTargets: ["OtherTests"]),
        ])
        defer { cleanup(root) }

        let output = """
        Testing failed:
            "MissingTests" isn't a member of the specified test plan or scheme.
        """

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output, succeeded: false,
                context: "scheme 'Standard' on macOS",
                projectRoot: root,
                projectPath: projectPath,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("MissingTests"))
            #expect(!message.contains("Did you mean a different scheme?"))
        }
    }

    @Test("Suggests multiple schemes when target appears in several")
    func suggestsMultipleSchemes() async throws {
        let (root, projectPath) = try createFixture(schemes: [
            "Alpha": schemeXML(testTargets: ["SharedTests"]),
            "Beta": schemeXML(testTargets: ["SharedTests", "BetaTests"]),
        ])
        defer { cleanup(root) }

        let output = """
        Testing failed:
            "SharedTests" isn't a member of the specified test plan or scheme.
        """

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output, succeeded: false,
                context: "scheme 'Other' on macOS",
                projectRoot: root,
                projectPath: projectPath,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Did you mean a different scheme?"))
            #expect(message.contains("'Alpha'"))
            #expect(message.contains("'Beta'"))
        }
    }

    @Test("Handles slash-separated identifiers by extracting target name")
    func handlesSlashIdentifiers() async throws {
        let (root, projectPath) = try createFixture(schemes: [
            "TestScheme": schemeXML(testTargets: ["MyUITests"]),
        ])
        defer { cleanup(root) }

        let output = """
        Testing failed:
            "MyUITests/LoginTest" isn't a member of the specified test plan or scheme.
        """

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output, succeeded: false,
                context: "scheme 'Standard' on macOS",
                projectRoot: root,
                projectPath: projectPath,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Did you mean a different scheme?"))
            #expect(message.contains("'TestScheme'"))
        }
    }

    @Test("No enhancement when error is not about test plan membership")
    func noEnhancementForOtherErrors() async throws {
        let (root, projectPath) = try createFixture(schemes: [
            "TestScheme": schemeXML(testTargets: ["MyTests"]),
        ])
        defer { cleanup(root) }

        let output = """
        Testing failed:
            Build input file cannot be found: 'missing.swift'
        """

        do {
            _ = try await ErrorExtractor.formatTestToolResult(
                output: output, succeeded: false,
                context: "scheme 'TestScheme' on macOS",
                projectRoot: root,
                projectPath: projectPath,
            )
            Issue.record("Expected error to be thrown")
        } catch {
            let message = "\(error)"
            #expect(!message.contains("Did you mean a different scheme?"))
        }
    }
}

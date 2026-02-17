import Testing
import XCMCPCore

@Suite("PreviewExtractor Tests")
struct PreviewExtractorTests {

    @Test("Single simple preview")
    func singleSimplePreview() {
        let source = """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    Text("Hello")
                }
            }

            #Preview {
                ContentView()
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].name == nil)
        #expect(previews[0].body.contains("ContentView()"))
    }

    @Test("Multiple previews in one file")
    func multiplePreviews() {
        let source = """
            #Preview {
                Text("First")
            }

            #Preview {
                Text("Second")
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 2)
        #expect(previews[0].body.contains("First"))
        #expect(previews[1].body.contains("Second"))
    }

    @Test("Named preview")
    func namedPreview() {
        let source = """
            #Preview("Dark Mode") {
                ContentView()
                    .preferredColorScheme(.dark)
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].name == "Dark Mode")
        #expect(previews[0].body.contains("ContentView()"))
        #expect(previews[0].body.contains(".preferredColorScheme(.dark)"))
    }

    @Test("Nested braces")
    func nestedBraces() {
        let source = """
            #Preview {
                VStack {
                    ForEach(0..<5) { index in
                        Text("Item \\(index)")
                    }
                }
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("VStack"))
        #expect(previews[0].body.contains("ForEach"))
        #expect(previews[0].body.contains("Text"))
    }

    @Test("String literals containing braces")
    func stringLiteralsWithBraces() {
        let source = """
            #Preview {
                Text("Hello { world }")
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("Hello { world }"))
    }

    @Test("Comments containing braces")
    func commentsWithBraces() {
        let source = """
            #Preview {
                // This { brace should be ignored }
                /* And this { one too } */
                Text("Hello")
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("Text(\"Hello\")"))
    }

    @Test("No preview returns empty array")
    func noPreview() {
        let source = """
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    Text("Hello")
                }
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.isEmpty)
    }

    @Test("Preview with attributes before it")
    func previewWithAttributesBefore() {
        let source = """
            @available(iOS 17, *)
            #Preview {
                ContentView()
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("ContentView()"))
    }

    @Test("Multiline string literal with braces inside preview")
    func multilineStringLiteral() {
        let source = ##"""
            #Preview {
                Text("""
                    { some braces }
                    """)
            }
            """##
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
    }

    @Test("Named previews with mixed unnamed")
    func mixedNamedAndUnnamed() {
        let source = """
            #Preview("Light") {
                ContentView()
            }

            #Preview {
                ContentView()
                    .preferredColorScheme(.dark)
            }

            #Preview("Landscape") {
                ContentView()
                    .previewInterfaceOrientation(.landscapeLeft)
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 3)
        #expect(previews[0].name == "Light")
        #expect(previews[1].name == nil)
        #expect(previews[2].name == "Landscape")
    }

    @Test("Does not match #PreviewFoo")
    func doesNotMatchSimilarMacro() {
        let source = """
            #PreviewLayout(.sizeThatFits)
            #Preview {
                Text("Real preview")
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("Real preview"))
    }

    @Test("Preview body extraction trims correctly")
    func bodyExtractionContent() {
        let source = """
            #Preview {
                Text("Hello")
            }
            """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        // Body should contain the content between { and }
        let body = previews[0].body
        #expect(!body.contains("#Preview"))
        #expect(body.contains("Text(\"Hello\")"))
    }
}

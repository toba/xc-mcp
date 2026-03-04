import Testing
import XCMCPCore

struct PreviewExtractorTests {
    @Test
    func `Single simple preview`() {
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

    @Test
    func `Multiple previews in one file`() {
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

    @Test
    func `Named preview`() {
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

    @Test
    func `Nested braces`() {
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

    @Test
    func `String literals containing braces`() {
        let source = """
        #Preview {
            Text("Hello { world }")
        }
        """
        let previews = PreviewExtractor.extractPreviewBodies(from: source)
        #expect(previews.count == 1)
        #expect(previews[0].body.contains("Hello { world }"))
    }

    @Test
    func `Comments containing braces`() {
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

    @Test
    func `No preview returns empty array`() {
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

    @Test
    func `Preview with attributes before it`() {
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

    @Test
    func `Multiline string literal with braces inside preview`() {
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

    @Test
    func `Named previews with mixed unnamed`() {
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

    @Test
    func `Does not match #PreviewFoo`() {
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

    @Test
    func `Preview body extraction trims correctly`() {
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

    // MARK: - stripPreviewBlocks Tests

    @Test
    func `Strip single preview block`() {
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
        let stripped = PreviewExtractor.stripPreviewBlocks(from: source)
        #expect(!stripped.contains("#Preview"))
        #expect(!stripped.contains("ContentView()"))
        #expect(stripped.contains("struct ContentView"))
        #expect(stripped.contains("Text(\"Hello\")"))
    }

    @Test
    func `Strip multiple preview blocks`() {
        let source = """
        struct A: View { var body: some View { Text("A") } }

        #Preview("First") {
            A()
        }

        struct B: View { var body: some View { Text("B") } }

        #Preview {
            B()
        }
        """
        let stripped = PreviewExtractor.stripPreviewBlocks(from: source)
        #expect(!stripped.contains("#Preview"))
        #expect(stripped.contains("struct A"))
        #expect(stripped.contains("struct B"))
    }

    @Test
    func `Strip preview with nested braces`() {
        let source = """
        #Preview {
            struct Nested: View {
                var body: some View { Text("nested") }
            }
            return Nested()
        }

        func keepMe() { }
        """
        let stripped = PreviewExtractor.stripPreviewBlocks(from: source)
        #expect(!stripped.contains("#Preview"))
        #expect(!stripped.contains("Nested"))
        #expect(stripped.contains("func keepMe()"))
    }

    @Test
    func `Strip preserves non-preview code intact`() {
        let source = "let x = 1\nlet y = 2\n"
        let stripped = PreviewExtractor.stripPreviewBlocks(from: source)
        #expect(stripped == source)
    }
}

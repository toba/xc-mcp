import Testing
import Foundation
@testable import XCMCPCore

struct IconManifestTests {
    @Test
    func `Hex to sRGB converts correctly`() {
        #expect(IconManifest.hexToSRGB("#FF0000") == "srgb:1.00000,0.00000,0.00000,1.00000")
        #expect(IconManifest.hexToSRGB("00FF00") == "srgb:0.00000,1.00000,0.00000,1.00000")
        #expect(IconManifest.hexToSRGB("#0000FF") == "srgb:0.00000,0.00000,1.00000,1.00000")
        #expect(IconManifest.hexToSRGB("#808080") == "srgb:0.50196,0.50196,0.50196,1.00000")
    }

    @Test
    func `Hex to sRGB passes through invalid input`() {
        #expect(IconManifest.hexToSRGB("not-a-color") == "not-a-color")
        #expect(IconManifest.hexToSRGB("") == "")
    }

    @Test
    func `Roundtrip encode and decode`() throws {
        let manifest = IconManifest(
            groups: [
                IconManifest.Group(
                    layers: [
                        IconManifest.Layer(
                            imageName: "logo.png",
                            name: "Logo",
                            glass: false,
                            position: IconManifest.Position(scale: 0.8)
                        ),
                    ],
                    shadow: IconManifest.Shadow(kind: "neutral", opacity: 0.5),
                    specular: true,
                    translucency: IconManifest.Translucency(enabled: true, value: 0.4)
                ),
            ],
            fill: .automaticGradient("srgb:0.00000,0.53333,1.00000,1.00000"),
            fillSpecializations: [
                IconManifest.Specialization(
                    appearance: "dark",
                    value: .solid("srgb:0.10000,0.10000,0.10000,1.00000")
                ),
            ]
        )

        let data = try manifest.jsonData()
        let decoded = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(decoded.groups.count == 1)
        #expect(decoded.groups[0].layers[0].imageName == "logo.png")
        #expect(decoded.groups[0].layers[0].name == "Logo")
        #expect(decoded.groups[0].layers[0].glass == false)
        #expect(decoded.groups[0].layers[0].position?.scale == 0.8)
        #expect(decoded.groups[0].shadow?.kind == "neutral")
        #expect(decoded.groups[0].specular == true)
        #expect(decoded.groups[0].translucency?.enabled == true)
        #expect(decoded.groups[0].translucency?.value == 0.4)

        if case let .automaticGradient(color) = decoded.fill {
            #expect(color.contains("0.53333"))
        } else {
            Issue.record("Expected automatic-gradient fill")
        }

        #expect(decoded.fillSpecializations?.count == 1)
        #expect(decoded.fillSpecializations?[0].appearance == "dark")
        if case let .solid(color) = decoded.fillSpecializations?[0].value {
            #expect(color.contains("0.10000"))
        } else {
            Issue.record("Expected solid fill specialization")
        }
    }

    @Test
    func `Supported platforms default`() throws {
        let manifest = IconManifest(groups: [])
        let data = try manifest.jsonData()
        let decoded = try JSONDecoder().decode(IconManifest.self, from: data)

        if case .shared = decoded.supportedPlatforms.squares {
            // pass
        } else {
            Issue.record("Expected squares = shared")
        }
        #expect(decoded.supportedPlatforms.circles == ["watchOS"])
    }

    @Test
    func `Decodes swiftiomatic icon json`() throws {
        let json = """
        {
          "fill" : {
            "automatic-gradient" : "extended-srgb:0.00000,0.53333,1.00000,1.00000"
          },
          "groups" : [
            {
              "layers" : [
                {
                  "glass" : false,
                  "image-name" : "logo.png",
                  "name" : "logo"
                }
              ],
              "shadow" : {
                "kind" : "neutral",
                "opacity" : 0.5
              },
              "translucency" : {
                "enabled" : true,
                "value" : 0.5
              }
            }
          ],
          "supported-platforms" : {
            "circles" : [
              "watchOS"
            ],
            "squares" : "shared"
          }
        }
        """
        let data = Data(json.utf8)
        let manifest = try JSONDecoder().decode(IconManifest.self, from: data)

        #expect(manifest.groups.count == 1)
        #expect(manifest.groups[0].layers[0].imageName == "logo.png")
        #expect(manifest.groups[0].layers[0].name == "logo")
        #expect(manifest.groups[0].layers[0].glass == false)
        #expect(manifest.groups[0].shadow?.kind == "neutral")
        #expect(manifest.groups[0].shadow?.opacity == 0.5)
        #expect(manifest.groups[0].translucency?.enabled == true)
        #expect(manifest.groups[0].translucency?.value == 0.5)

        if case let .automaticGradient(color) = manifest.fill {
            #expect(color == "extended-srgb:0.00000,0.53333,1.00000,1.00000")
        } else {
            Issue.record("Expected automatic-gradient fill")
        }
    }

    @Test
    func `Write creates icon json file`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let bundlePath = tempDir.appendingPathComponent("Test.icon")
        try FileManager.default.createDirectory(
            at: bundlePath, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifest = IconManifest(
            groups: [
                IconManifest.Group(
                    layers: [IconManifest.Layer(imageName: "test.png", name: "test")]
                ),
            ]
        )
        try manifest.write(to: bundlePath.path)

        let jsonPath = bundlePath.appendingPathComponent("icon.json")
        #expect(FileManager.default.fileExists(atPath: jsonPath.path))

        let data = try Data(contentsOf: jsonPath)
        let decoded = try JSONDecoder().decode(IconManifest.self, from: data)
        #expect(decoded.groups[0].layers[0].imageName == "test.png")
    }
}

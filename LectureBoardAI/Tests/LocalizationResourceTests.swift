import Foundation
import Testing

@Suite("Localization resources")
struct LocalizationResourceTests {
  @Test("English and Japanese localization files contain the app title")
  func localizationFilesContainAppTitle() throws {
    let expectedTitles = [
      "en": "LectureBoard AI",
      "ja": "LectureBoard AI",
    ]

    for (localization, expectedTitle) in expectedTitles {
      let localizationURL = try #require(
        Bundle.main.url(forResource: localization, withExtension: "lproj")
      )
      let localizationBundle = try #require(Bundle(url: localizationURL))
      let stringsURL = try #require(
        localizationBundle.url(forResource: "Localizable", withExtension: "strings")
      )
      let stringsData = try Data(contentsOf: stringsURL)
      let strings = try #require(
        PropertyListSerialization.propertyList(from: stringsData, format: nil)
          as? [String: String]
      )

      #expect(strings["app.title"] == expectedTitle)
    }
  }
}

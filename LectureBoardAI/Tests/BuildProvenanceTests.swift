import Foundation
import Testing

@Suite
struct BuildProvenanceTests {
  @Test
  func reportsEmbeddedSourceCommitForEvidenceBinding() throws {
    let commit = try #require(
      Bundle.main.object(forInfoDictionaryKey: "LectureBoardReleaseCommit") as? String
    )
    let isUnboundDevelopmentBuild = commit == "UNBOUND"
    let isFullObjectIdentifier =
      commit.wholeMatch(of: /[0-9a-f]{40}/) != nil
      || commit.wholeMatch(of: /[0-9a-f]{64}/) != nil

    #expect(isUnboundDevelopmentBuild || isFullObjectIdentifier)
    print("LectureBoard native-test embedded source commit: \(commit)")
  }
}

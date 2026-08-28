import Foundation
import Testing
@testable import Manga_Reader

@Suite("Chapter frontier")
struct ChapterFrontierTests {
    @Test("A chapter above the maximum is a release")
    func chapterAboveMaximumIsRelease() {
        var frontier = ChapterFrontier()
        frontier.seed(["7"])

        #expect(frontier.absorb(["8"]) == [ordinal("8")])
    }

    @Test("A decimal chapter above the maximum is a release")
    func decimalAboveMaximumIsRelease() {
        var frontier = ChapterFrontier()
        frontier.seed(["7"])

        #expect(frontier.absorb(["7.5"]) == [ordinal("7.5")])
    }

    @Test("A decimal chapter below the maximum is silent backfill")
    func decimalBelowMaximumIsBackfill() {
        var frontier = ChapterFrontier()
        frontier.seed(["8"])

        #expect(frontier.absorb(["7.5"]).isEmpty)
        #expect(frontier.known.contains(ordinal("7.5")))
        #expect(frontier.max == ordinal("8"))
    }

    @Test("Zero padding is the same chapter")
    func zeroPaddingIsSameChapter() {
        var frontier = ChapterFrontier()
        frontier.seed(["7"])

        #expect(frontier.absorb(["07"]).isEmpty)
        #expect(frontier.known.count == 1)
    }

    @Test("Version and range suffixes use their leading chapter number")
    func suffixesUseLeadingNumber() {
        #expect(ChapterOrdinal.parse("7v2") == ordinal("7"))
        #expect(ChapterOrdinal.parse("7-8") == ordinal("7"))
    }

    @Test("Unnumbered chapters never advance or emit")
    func unnumberedChaptersAreSilent() {
        var frontier = ChapterFrontier()

        #expect(frontier.absorb(["Extra", "", "Oneshot"]).isEmpty)
        #expect(frontier.max == nil)
        #expect(frontier.known.isEmpty)
        #expect(frontier.unnumbered == ["Extra", "", "Oneshot"])
    }

    @Test("A shrinking source listing never lowers the maximum")
    func shrinkingListingDoesNotLowerMaximum() {
        var frontier = ChapterFrontier()
        frontier.seed(["7", "8"])

        #expect(frontier.absorb(["7"]).isEmpty)
        #expect(frontier.max == ordinal("8"))
        #expect(frontier.known == [ordinal("7"), ordinal("8")])
    }

    @Test("Seeding a large first observation establishes a silent baseline")
    func seedingLargeObservationIsSilent() {
        var frontier = ChapterFrontier()
        let chapters = (1...100).map(String.init)

        frontier.seed(chapters)

        #expect(frontier.known.count == 100)
        #expect(frontier.max == ordinal("100"))
        #expect(frontier.absorb(chapters).isEmpty)
    }

    @Test("Codable round trip preserves the complete frontier")
    func codableRoundTripPreservesFrontier() throws {
        var frontier = ChapterFrontier()
        frontier.seed(["1", "7.5", "Extra", ""])

        let data = try JSONEncoder().encode(frontier)
        let decoded = try JSONDecoder().decode(ChapterFrontier.self, from: data)

        #expect(decoded == frontier)
        #expect(decoded.known == frontier.known)
        #expect(decoded.max == frontier.max)
        #expect(decoded.unnumbered == frontier.unnumbered)
    }

    private func ordinal(_ raw: String) -> ChapterOrdinal {
        guard let parsed = ChapterOrdinal.parse(raw) else {
            Issue.record("Expected \(raw) to parse as a chapter ordinal")
            return ChapterOrdinal(value: 0)
        }
        return parsed
    }
}

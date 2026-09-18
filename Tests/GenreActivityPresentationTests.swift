import Foundation
import XCTest

@testable import Brainz

final class GenreActivityPresentationTests: XCTestCase {
    func testPresentationGroupsAndRanksGenresAcrossFourUTCWholeDayparts() throws {
        let activity = GenreActivity(
            period: .thisMonth,
            from: .distantPast,
            to: try XCTUnwrap(utcDate(year: 2025, month: 1, day: 15)),
            lastUpdated: .distantPast,
            rows: [
                .init(genre: "Electronic", hour: 0, listenCount: 5),
                .init(genre: "Electronic", hour: 5, listenCount: 2),
                .init(genre: "Ambient", hour: 0, listenCount: 8),
                .init(genre: "Indie Pop", hour: 6, listenCount: 4),
                .init(genre: "Art Pop", hour: 12, listenCount: 6),
                .init(genre: "Dream Pop", hour: 18, listenCount: 7),
            ]
        )

        let presentation = GenreActivityPresentation(
            activity: activity,
            timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        )

        XCTAssertEqual(presentation.dayparts.map(\.daypart), GenreDaypart.allCases)
        XCTAssertEqual(presentation.daypart(.night)?.genres.map(\.name), ["Ambient", "Electronic"])
        XCTAssertEqual(presentation.daypart(.night)?.genres.map(\.listenCount), [8, 7])
        XCTAssertEqual(presentation.daypart(.morning)?.leadingGenre?.name, "Indie Pop")
        XCTAssertEqual(presentation.daypart(.afternoon)?.leadingGenre?.name, "Art Pop")
        XCTAssertEqual(presentation.daypart(.evening)?.leadingGenre?.name, "Dream Pop")
        XCTAssertEqual(presentation.busiestDaypart?.daypart, .night)
    }

    func testPresentationUsesBucketMidpointsForFractionalOffsetTimeZones() throws {
        let referenceDate = try XCTUnwrap(utcDate(year: 2025, month: 1, day: 15))
        let activity = GenreActivity(
            period: .thisMonth,
            from: .distantPast,
            to: referenceDate,
            lastUpdated: .distantPast,
            rows: [
                .init(genre: "Morning", hour: 0, listenCount: 3),
                .init(genre: "Evening", hour: 17, listenCount: 4),
                .init(genre: "Night", hour: 18, listenCount: 5),
            ]
        )

        let presentation = GenreActivityPresentation(
            activity: activity,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu")),
            referenceDate: referenceDate
        )

        // UTC 00:00–00:59 centers at 06:15 local, UTC 17 centers at
        // 23:15, and UTC 18 centers at 00:15 the following day.
        XCTAssertEqual(presentation.daypart(.morning)?.leadingGenre?.name, "Morning")
        XCTAssertEqual(presentation.daypart(.evening)?.leadingGenre?.name, "Evening")
        XCTAssertEqual(presentation.daypart(.night)?.leadingGenre?.name, "Night")
    }

    func testPresentationUsesReportEndDaylightSavingOffset() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Edmonton"))
        let winter = try XCTUnwrap(utcDate(year: 2025, month: 1, day: 15))
        let summer = try XCTUnwrap(utcDate(year: 2025, month: 7, day: 15))

        func activity(endingAt date: Date) -> GenreActivity {
            GenreActivity(
                period: .thisYear,
                from: .distantPast,
                to: date,
                lastUpdated: .distantPast,
                rows: [.init(genre: "Boundary", hour: 12, listenCount: 1)]
            )
        }

        let winterPresentation = GenreActivityPresentation(
            activity: activity(endingAt: winter),
            timeZone: timeZone
        )
        let summerPresentation = GenreActivityPresentation(
            activity: activity(endingAt: summer),
            timeZone: timeZone
        )

        // The 12:00 UTC bucket centers at 05:30 MST but 06:30 MDT.
        XCTAssertEqual(winterPresentation.daypart(.night)?.leadingGenre?.name, "Boundary")
        XCTAssertEqual(summerPresentation.daypart(.morning)?.leadingGenre?.name, "Boundary")
    }

    func testDateRangeUsesTheExplicitUserTimeZone() throws {
        let activity = GenreActivity(
            period: .thisWeek,
            from: Date(timeIntervalSince1970: 1_735_693_200), // 2025-01-01 01:00 UTC
            to: Date(timeIntervalSince1970: 1_735_779_600),   // 2025-01-02 01:00 UTC
            lastUpdated: .distantPast,
            rows: []
        )

        XCTAssertEqual(
            GenreActivityPresentation.dateRange(
                activity,
                timeZone: try XCTUnwrap(TimeZone(identifier: "America/Edmonton")),
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Dec 31, 2024 – Jan 1, 2025 · calculated by ListenBrainz"
        )
    }

    private func utcDate(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

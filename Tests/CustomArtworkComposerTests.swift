import Foundation
import ListenBrainzKit
import XCTest

@testable import Brainz

final class CustomArtworkComposerTests: XCTestCase {
    func testCandidatesKeepCanonicalReleaseOrderAndRemoveDuplicates() {
        let first = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let second = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let releases = [
            release(id: first, title: "First"),
            release(id: nil, title: "Unmapped"),
            release(id: first, title: "Duplicate"),
            release(id: second, title: "Second"),
        ]

        let candidates = CustomArtworkAlbum.candidates(from: releases)

        XCTAssertEqual(candidates.map(\.releaseMBID), [first, second])
        XCTAssertEqual(candidates.map(\.title), ["First", "Second"])
    }

    func testAvailableLayoutsReflectTheAlbumsAlreadyLoaded() {
        XCTAssertEqual(CustomArtworkLayoutPreset.available(for: 0), [])
        XCTAssertEqual(
            CustomArtworkLayoutPreset.available(for: 4),
            [.single, .grid2]
        )
        XCTAssertEqual(
            CustomArtworkLayoutPreset.available(for: 6),
            [.single, .grid2, .spotlightLeft3, .spotlightRight3]
        )
        XCTAssertEqual(
            CustomArtworkLayoutPreset.available(for: 20),
            CustomArtworkLayoutPreset.allCases
        )
    }

    func testDraftSeedsTopAlbumsAndLayoutChangesStayComplete() {
        let ids = (0 ..< 10).map { fixtureUUID($0) }
        var draft = CustomArtworkDraft(albumIDs: ids + [ids[0]])

        XCTAssertEqual(draft.layout, .spotlightLeft3)
        XCTAssertEqual(draft.selectedReleaseMBIDs, Array(ids.prefix(6)))
        XCTAssertTrue(draft.canGenerate)

        draft.selectLayout(.feature4)
        XCTAssertEqual(draft.selectedReleaseMBIDs, Array(ids.prefix(8)))
        XCTAssertTrue(draft.canGenerate)

        draft.selectLayout(.grid2)
        XCTAssertEqual(draft.selectedReleaseMBIDs, Array(ids.prefix(4)))
        XCTAssertTrue(draft.canGenerate)
    }

    func testSelectionHonorsTheLayoutLimitAndPreservesTapOrder() {
        let ids = (0 ..< 7).map { fixtureUUID($0) }
        var draft = CustomArtworkDraft(albumIDs: ids)
        let removed = ids[2]
        let replacement = ids[6]

        draft.toggle(removed)
        XCTAssertFalse(draft.canGenerate)
        XCTAssertEqual(draft.remainingCoverCount, 1)

        draft.toggle(replacement)
        XCTAssertTrue(draft.canGenerate)
        XCTAssertEqual(draft.selectedReleaseMBIDs.last, replacement)

        draft.toggle(removed)
        XCTAssertFalse(draft.selectedReleaseMBIDs.contains(removed))
        XCTAssertEqual(draft.selectedReleaseMBIDs.count, 6)
    }

    func testCoverOrderCanMoveWithoutChangingSelection() {
        let ids = (0 ..< 6).map { fixtureUUID($0) }
        var draft = CustomArtworkDraft(albumIDs: ids)

        draft.moveSelection(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(
            draft.selectedReleaseMBIDs,
            [ids[1], ids[2], ids[0], ids[3], ids[4], ids[5]]
        )
        XCTAssertTrue(draft.canGenerate)
    }

    func testRequestFreeDraftBuildsOneExactCustomRequest() throws {
        let ids = (0 ..< 6).map { fixtureUUID($0) }
        var draft = CustomArtworkDraft(albumIDs: ids)
        draft.background = .transparent
        draft.captions = true

        let request = try XCTUnwrap(draft.request)

        XCTAssertEqual(
            request,
            .custom(
                releaseMBIDs: ids,
                dimension: 3,
                layout: .one,
                background: .transparent,
                captions: true
            )
        )
    }

    private func release(
        id: UUID?,
        title: String
    ) -> RankedRelease {
        RankedRelease(
            mbid: id,
            name: title,
            artistName: "Artist",
            artistMBIDs: [],
            listenCount: 1
        )
    }

    private func fixtureUUID(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-4000-8000-%012d",
                value
            )
        )!
    }
}

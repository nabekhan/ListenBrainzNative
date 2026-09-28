import Foundation
import XCTest
import Nuke

@testable import Brainz

final class ArtworkPipelineTests: XCTestCase {
    func testOnlyHTTPSRemoteURLsProduceRequests() {
        let secureURL = URL(string: "https://coverartarchive.org/release/123/front-500")!
        XCTAssertEqual(ArtworkPipeline.request(for: secureURL)?.url, secureURL)
        XCTAssertEqual(
            ArtworkPipeline.request(for: secureURL)?.thumbnail,
            ImageRequest.ThumbnailOptions(maxPixelSize: ArtworkPipeline.maximumDecodedPixelSize)
        )
        XCTAssertNotNil(ArtworkPipeline.request(for: URL(string: "https://example.com:443/art.jpg")))
        XCTAssertNil(ArtworkPipeline.request(for: URL(string: "http://example.com/art.jpg")))
        XCTAssertNil(ArtworkPipeline.request(for: URL(string: "https://user@example.com/art.jpg")))
        XCTAssertNil(ArtworkPipeline.request(for: URL(string: "https://example.com:8443/art.jpg")))
        XCTAssertNil(ArtworkPipeline.request(for: URL(string: "file:///tmp/art.jpg")))
        XCTAssertNil(ArtworkPipeline.request(for: URL(string: "https:///art.jpg")))
    }

    func testResponseValidationAcceptsOnlyHTTPS2xxImages() {
        let imageResponse = HTTPURLResponse(
            url: URL(string: "https://archive.org/art.jpg")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        XCTAssertNil(ArtworkPipeline.validate(response: imageResponse))

        let nonImageResponse = HTTPURLResponse(
            url: URL(string: "https://archive.org/art.jpg")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        XCTAssertEqual(
            ArtworkPipeline.validate(response: nonImageResponse) as? ArtworkValidationError,
            .unsupportedContentType("text/html")
        )

        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://archive.org/art.jpg")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        XCTAssertEqual(
            ArtworkPipeline.validate(response: errorResponse) as? ArtworkValidationError,
            .unacceptableStatusCode(404)
        )

        let insecureResponse = HTTPURLResponse(
            url: URL(string: "http://archive.org/art.jpg")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        XCTAssertEqual(
            ArtworkPipeline.validate(response: insecureResponse) as? ArtworkValidationError,
            .insecureResponseURL
        )
    }

    func testRedirectsRemainCredentialFreeHTTPSGets() {
        var allowed = URLRequest(url: URL(string: "https://archive.org/art.jpg")!)
        allowed.httpMethod = "GET"
        allowed.httpShouldHandleCookies = true
        allowed.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        allowed.setValue("session=identifier", forHTTPHeaderField: "Cookie")
        allowed.setValue("Basic secret", forHTTPHeaderField: "Proxy-Authorization")

        let admitted = ArtworkRedirectDelegate.admittedRedirect(allowed)
        XCTAssertEqual(admitted?.url, allowed.url)
        XCTAssertEqual(admitted?.httpMethod, "GET")
        XCTAssertEqual(admitted?.httpShouldHandleCookies, false)
        XCTAssertNil(admitted?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(admitted?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(admitted?.value(forHTTPHeaderField: "Proxy-Authorization"))

        var insecure = allowed
        insecure.url = URL(string: "http://archive.org/art.jpg")!
        XCTAssertNil(ArtworkRedirectDelegate.admittedRedirect(insecure))

        var nonstandardPort = allowed
        nonstandardPort.url = URL(string: "https://archive.org:8443/art.jpg")!
        XCTAssertNil(ArtworkRedirectDelegate.admittedRedirect(nonstandardPort))

        var post = allowed
        post.httpMethod = "POST"
        XCTAssertNil(ArtworkRedirectDelegate.admittedRedirect(post))
    }

    func testPipelineUsesConfiguredCachesAndBoundedLoads() throws {
        let cacheDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let pipeline = ArtworkPipeline.makePipeline(cacheDirectory: cacheDirectory)

        XCTAssertEqual(
            pipeline.configuration.dataLoadingQueue.maxConcurrentOperationCount,
            ArtworkPipeline.maxConcurrentDataLoads
        )
        XCTAssertEqual(
            pipeline.configuration.maximumResponseDataSize,
            ArtworkPipeline.maximumResponseDataSize
        )
        XCTAssertTrue(pipeline.configuration.isTaskCoalescingEnabled)
        XCTAssertTrue(pipeline.configuration.isDecompressionEnabled)
        let dataLoader = try XCTUnwrap(pipeline.configuration.dataLoader as? DataLoader)
        XCTAssertNotNil(dataLoader.delegate as? ArtworkRedirectDelegate)
        XCTAssertFalse(dataLoader.session.configuration.httpShouldSetCookies)
        XCTAssertEqual(dataLoader.session.configuration.httpCookieAcceptPolicy, .never)
        XCTAssertNil(dataLoader.session.configuration.httpCookieStorage)
        XCTAssertNil(dataLoader.session.configuration.urlCredentialStorage)
        XCTAssertEqual(
            (pipeline.configuration.imageCache as? ImageCache)?.costLimit,
            ArtworkPipeline.memoryCacheCostLimit
        )
        XCTAssertEqual(
            (pipeline.configuration.imageCache as? ImageCache)?.countLimit,
            ArtworkPipeline.memoryCacheCountLimit
        )
        XCTAssertEqual((pipeline.configuration.dataCache as? DataCache)?.sizeLimit, ArtworkPipeline.diskCacheSizeLimit)
        XCTAssertEqual((pipeline.configuration.dataCache as? DataCache)?.path, cacheDirectory)
    }
}

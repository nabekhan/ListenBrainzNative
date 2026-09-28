import Foundation
import Nuke

enum ArtworkPipeline {
    static let maxConcurrentDataLoads = 2
    static let maximumResponseDataSize = 8 * 1_024 * 1_024
    static let maximumDecodedPixelSize: Float = 1_024
    static let diskCacheSizeLimit = 128 * 1_024 * 1_024
    static let memoryCacheCostLimit = 32 * 1_024 * 1_024
    static let memoryCacheCountLimit = 120

    static let shared = makePipeline()

    static func request(for url: URL?) -> ImageRequest? {
        guard let url, isAllowedRemoteURL(url) else { return nil }
        var request = ImageRequest(url: url)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            maxPixelSize: maximumDecodedPixelSize
        )
        return request
    }

    static func isAllowedRemoteURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
            && (url.port == nil || url.port == 443)
    }

    static func validate(response: URLResponse) -> (any Error)? {
        guard let response = response as? HTTPURLResponse else {
            return ArtworkValidationError.notHTTP
        }
        guard (200..<300).contains(response.statusCode) else {
            return ArtworkValidationError.unacceptableStatusCode(response.statusCode)
        }
        guard response.url.map(isAllowedRemoteURL) == true else {
            return ArtworkValidationError.insecureResponseURL
        }
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else {
            return ArtworkValidationError.unsupportedContentType(response.mimeType)
        }
        return nil
    }

    static func makePipeline(
        cacheDirectory: URL? = nil
    ) -> ImagePipeline {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.httpCookieAcceptPolicy = .never
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil

        let dataLoader = DataLoader(
            configuration: sessionConfiguration,
            validate: validate(response:)
        )
        dataLoader.delegate = ArtworkRedirectDelegate.shared
        var configuration = ImagePipeline.Configuration(dataLoader: dataLoader)
        configuration.isTaskCoalescingEnabled = true
        configuration.isDecompressionEnabled = true
        configuration.isUsingPrepareForDisplay = true
        configuration.maximumResponseDataSize = maximumResponseDataSize
        configuration.dataLoadingQueue = TaskQueue(
            maxConcurrentOperationCount: maxConcurrentDataLoads
        )
        configuration.dataCachePolicy = .storeOriginalData
        configuration.imageCache = ImageCache(
            costLimit: memoryCacheCostLimit,
            countLimit: memoryCacheCountLimit
        )
        configuration.dataCache = makeDataCache(at: cacheDirectory)
        return ImagePipeline(configuration: configuration)
    }

    private static func makeDataCache(at directory: URL?) -> (any DataCaching)? {
        do {
            if let directory {
                let cache = try DataCache(path: directory)
                cache.sizeLimit = diskCacheSizeLimit
                return cache
            }
            let cache = try DataCache(name: "dev.nabekhan.listenbrainznative.artwork")
            cache.sizeLimit = diskCacheSizeLimit
            return cache
        } catch {
            return nil
        }
    }
}

enum ArtworkValidationError: Error, Equatable {
    case notHTTP
    case unacceptableStatusCode(Int)
    case insecureResponseURL
    case unsupportedContentType(String?)
}

final class ArtworkRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = ArtworkRedirectDelegate()

    static func admittedRedirect(_ proposedRequest: URLRequest) -> URLRequest? {
        guard
            proposedRequest.httpMethod?.uppercased() == "GET",
            proposedRequest.url.map(ArtworkPipeline.isAllowedRemoteURL) == true
        else {
            return nil
        }

        var request = proposedRequest
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue(nil, forHTTPHeaderField: "Proxy-Authorization")
        return request
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.admittedRedirect(request))
    }
}

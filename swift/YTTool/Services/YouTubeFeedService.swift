import Foundation

/// Fetches and parses YouTube channel RSS feeds.
///
/// Feed URL format: `https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID`
/// Returns the 15 most recent uploads (includes Shorts and live streams).
struct YouTubeFeedService {
    private static let feedBaseURL = "https://www.youtube.com/feeds/videos.xml?channel_id="

    // MARK: - Channel ID resolution

    /// Resolves a YouTube channel ID from an arbitrary channel/video URL using yt-dlp.
    func resolveChannelID(
        from url: String,
        locator: BundledToolLocator = BundledToolLocator()
    ) async throws -> (channelID: String, channelName: String) {
        let ytDlp: URL
        do {
            ytDlp = try locator.locate(.ytDlp)
        } catch {
            throw FeedError.ytDlpNotFound
        }

        let process = Process()
        process.executableURL = ytDlp
        process.arguments = [
            "--print", "channel_id",
            "--print", "channel",
            "--playlist-items", "1",
            "--no-warnings",
            url,
        ]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let output: String = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: FeedError.channelIDResolutionFailed)
                    return
                }
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: text)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FeedError.channelIDResolutionFailed)
            }
        }

        let lines = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard lines.count >= 2, !lines[0].isEmpty else {
            throw FeedError.channelIDResolutionFailed
        }

        return (channelID: lines[0], channelName: lines[1])
    }

    // MARK: - Feed fetching

    /// Fetches the RSS feed for a channel and returns parsed video entries.
    func fetchFeed(channelID: String) async throws -> [FeedVideo] {
        let urlString = Self.feedBaseURL + channelID
        guard let url = URL(string: urlString) else {
            throw FeedError.invalidFeedURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw FeedError.feedFetchFailed
        }

        return parseFeed(data: data)
    }

    // MARK: - XML parsing

    func parseFeed(data: Data) -> [FeedVideo] {
        let parser = FeedXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - Errors

enum FeedError: LocalizedError {
    case ytDlpNotFound
    case channelIDResolutionFailed
    case invalidFeedURL
    case feedFetchFailed

    var errorDescription: String? {
        switch self {
        case .ytDlpNotFound:
            "yt-dlp not found in bundle."
        case .channelIDResolutionFailed:
            "Could not resolve channel ID from the provided URL."
        case .invalidFeedURL:
            "Invalid feed URL."
        case .feedFetchFailed:
            "Failed to fetch the RSS feed."
        }
    }
}

// MARK: - XML Parser

/// Minimal XML parser for YouTube Atom feeds.
///
/// Feed structure:
/// ```xml
/// <feed>
///   <entry>
///     <yt:videoId>xxx</yt:videoId>
///     <title>Video Title</title>
///     <author><name>Channel Name</name></author>
///     <published>2026-05-29T12:00:00+00:00</published>
///     <link rel="alternate" href="https://www.youtube.com/watch?v=xxx"/>
///   </entry>
/// </feed>
/// ```
final class FeedXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var videos: [FeedVideo] = []

    private var inEntry = false
    private var inAuthor = false
    private var currentElement = ""
    private var currentVideoID = ""
    private var currentTitle = ""
    private var currentAuthorName = ""
    private var currentPublished = ""
    private var currentLink = ""

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(data: Data) {
        self.data = data
    }

    func parse() -> [FeedVideo] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return videos
    }

    // MARK: - XMLParserDelegate

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?,
                qualifiedName _: String?, attributes attributeDict: [String: String] = [:])
    {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true
            currentVideoID = ""
            currentTitle = ""
            currentAuthorName = ""
            currentPublished = ""
            currentLink = ""
        } else if elementName == "author" {
            inAuthor = true
        } else if inEntry, elementName == "link",
                  attributeDict["rel"] == "alternate",
                  let href = attributeDict["href"]
        {
            currentLink = href
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch currentElement {
        case "yt:videoId":
            currentVideoID += string
        case "title":
            currentTitle += string
        case "name" where inAuthor:
            currentAuthorName += string
        case "published":
            currentPublished += string
        default:
            break
        }
    }

    func parser(_: XMLParser, didEndElement elementName: String,
                namespaceURI _: String?, qualifiedName _: String?)
    {
        if elementName == "entry" {
            inEntry = false
            let videoID = currentVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !videoID.isEmpty else { return }
            let video = FeedVideo(
                videoID: videoID,
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                channelName: currentAuthorName.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedDate: Self.iso8601.date(from: currentPublished.trimmingCharacters(in: .whitespacesAndNewlines)),
                url: currentLink.isEmpty
                    ? "https://www.youtube.com/watch?v=\(videoID)"
                    : currentLink,
                thumbnailURL: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
            )
            videos.append(video)
        } else if elementName == "author" {
            inAuthor = false
        }
        currentElement = ""
    }
}

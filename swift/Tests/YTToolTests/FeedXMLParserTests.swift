import XCTest
@testable import YTTool

final class FeedXMLParserTests: XCTestCase {
    // MARK: - Normal feed

    func testParsesTypicalAtomFeed() {
        let videos = YouTubeFeedService().parseFeed(data: Data(Self.typicalFeed.utf8))

        XCTAssertEqual(videos.count, 2)

        let first = videos[0]
        XCTAssertEqual(first.videoID, "abc123")
        XCTAssertEqual(first.title, "First Video Title")
        XCTAssertEqual(first.channelName, "Test Channel")
        XCTAssertEqual(first.url, "https://www.youtube.com/watch?v=abc123")
        XCTAssertNotNil(first.publishedDate)

        let second = videos[1]
        XCTAssertEqual(second.videoID, "def456")
        XCTAssertEqual(second.title, "Second Video")
        XCTAssertEqual(second.channelName, "Test Channel")
    }

    func testParsesPublishedDateAsISO8601() throws {
        let videos = YouTubeFeedService().parseFeed(data: Data(Self.typicalFeed.utf8))

        let date = try XCTUnwrap(videos[0].publishedDate)
        let calendar = Calendar(identifier: .gregorian)
        let components = try calendar.dateComponents(in: XCTUnwrap(TimeZone(identifier: "UTC")), from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 28)
    }

    // MARK: - Edge cases

    func testEmptyFeedReturnsEmptyArray() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <title>Empty Channel</title>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        XCTAssertTrue(videos.isEmpty)
    }

    func testSkipsEntryWithEmptyVideoID() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <yt:videoId>  </yt:videoId>
            <title>No ID Video</title>
          </entry>
          <entry>
            <yt:videoId>valid123</yt:videoId>
            <title>Valid Video</title>
          </entry>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos[0].videoID, "valid123")
    }

    func testMissingOptionalFieldsDefaultGracefully() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <yt:videoId>xyz789</yt:videoId>
          </entry>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        XCTAssertEqual(videos.count, 1)
        let video = videos[0]
        XCTAssertEqual(video.videoID, "xyz789")
        XCTAssertEqual(video.title, "")
        XCTAssertEqual(video.channelName, "")
        XCTAssertNil(video.publishedDate)
        // Falls back to constructed URL when link element is absent.
        XCTAssertEqual(video.url, "https://www.youtube.com/watch?v=xyz789")
    }

    func testLinkAlternateOverridesConstructedURL() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <yt:videoId>custom1</yt:videoId>
            <title>Custom Link</title>
            <link rel="alternate" href="https://example.com/custom"/>
          </entry>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        XCTAssertEqual(videos[0].url, "https://example.com/custom")
    }

    func testIgnoresNonAlternateLinks() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <yt:videoId>linktest</yt:videoId>
            <link rel="self" href="https://example.com/self"/>
          </entry>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        // No alternate link → falls back to constructed URL.
        XCTAssertEqual(videos[0].url, "https://www.youtube.com/watch?v=linktest")
    }

    func testInvalidXMLReturnsEmptyArray() {
        let videos = YouTubeFeedService().parseFeed(data: Data("not xml at all".utf8))
        XCTAssertTrue(videos.isEmpty)
    }

    func testMultipleEntriesPreserveOrder() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
              xmlns="http://www.w3.org/2005/Atom">
          <entry><yt:videoId>v1</yt:videoId><title>First</title></entry>
          <entry><yt:videoId>v2</yt:videoId><title>Second</title></entry>
          <entry><yt:videoId>v3</yt:videoId><title>Third</title></entry>
        </feed>
        """
        let videos = YouTubeFeedService().parseFeed(data: Data(xml.utf8))
        XCTAssertEqual(videos.map(\.videoID), ["v1", "v2", "v3"])
    }

    // MARK: - Fixtures

    private static let typicalFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
          xmlns:media="http://search.yahoo.com/mrss/"
          xmlns="http://www.w3.org/2005/Atom">
      <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=UC123"/>
      <title>Test Channel</title>
      <entry>
        <yt:videoId>abc123</yt:videoId>
        <yt:channelId>UC123</yt:channelId>
        <title>First Video Title</title>
        <link rel="alternate" href="https://www.youtube.com/watch?v=abc123"/>
        <author>
          <name>Test Channel</name>
          <uri>https://www.youtube.com/channel/UC123</uri>
        </author>
        <published>2026-05-28T12:00:00+00:00</published>
        <media:group>
          <media:title>First Video Title</media:title>
          <media:description>Description here</media:description>
        </media:group>
      </entry>
      <entry>
        <yt:videoId>def456</yt:videoId>
        <yt:channelId>UC123</yt:channelId>
        <title>Second Video</title>
        <link rel="alternate" href="https://www.youtube.com/watch?v=def456"/>
        <author>
          <name>Test Channel</name>
        </author>
        <published>2026-05-27T08:30:00+00:00</published>
      </entry>
    </feed>
    """
}

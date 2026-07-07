//
//  MediaPlaybackResolverTests.swift
//  PatreonTVTests
//
//  Scoring behavior of MediaPlaybackResolver: prefer Mux HLS display URLs,
//  reject images, fall back to Patreon-hosted downloads.
//

import XCTest
@testable import PatreonTV

final class MediaPlaybackResolverTests: XCTestCase {

    /// Builds a minimal post document with the given media includes.
    private func document(mediaJSON: String) throws -> SingleResource<Post> {
        let json = """
        {
          "data": {
            "type": "post",
            "id": "1",
            "attributes": { "title": "T", "post_type": "video_external_file" }
          },
          "included": [\(mediaJSON)]
        }
        """.data(using: .utf8)!
        return try JSONAPIDecoder.decode(SingleResource<Post>.self, from: json)
    }

    func test_prefers_mux_display_over_download() throws {
        let doc = try document(mediaJSON: """
          {
            "type": "media", "id": "m1",
            "attributes": {
              "mimetype": "application/x-mpegURL",
              "download_url": "https://c10.patreonusercontent.com/file.mp4",
              "display": { "url": "https://stream.mux.com/abc.m3u8?token=t" }
            }
          }
        """)

        let source = MediaPlaybackResolver.resolve(from: doc)
        XCTAssertEqual(source?.url.host(), "stream.mux.com")
    }

    func test_rejects_images() throws {
        let doc = try document(mediaJSON: """
          {
            "type": "media", "id": "m1",
            "attributes": {
              "mimetype": "image/jpeg",
              "download_url": "https://c10.patreonusercontent.com/poster.jpg"
            }
          }
        """)

        XCTAssertNil(MediaPlaybackResolver.resolve(from: doc))
    }

    func test_falls_back_to_patreon_hosted_video_download() throws {
        let doc = try document(mediaJSON: """
          {
            "type": "media", "id": "m1",
            "attributes": {
              "mimetype": "video/mp4",
              "download_url": "https://c10.patreonusercontent.com/file.mp4"
            }
          }
        """)

        let source = MediaPlaybackResolver.resolve(from: doc)
        XCTAssertEqual(source?.url.host(), "c10.patreonusercontent.com")
    }

    func test_picks_best_across_multiple_media() throws {
        let doc = try document(mediaJSON: """
          {
            "type": "media", "id": "poster",
            "attributes": {
              "mimetype": "image/png",
              "download_url": "https://c10.patreonusercontent.com/poster.png"
            }
          },
          {
            "type": "media", "id": "video",
            "attributes": {
              "mimetype": "application/vnd.apple.mpegurl",
              "display": { "url": "https://stream.mux.com/best.m3u8" }
            }
          },
          {
            "type": "media", "id": "mp4",
            "attributes": {
              "mimetype": "video/mp4",
              "download_url": "https://c10.patreonusercontent.com/alt.mp4"
            }
          }
        """)

        let source = MediaPlaybackResolver.resolve(from: doc)
        XCTAssertEqual(source?.url.lastPathComponent, "best.m3u8")
    }

    func test_no_media_returns_nil() throws {
        let json = """
        { "data": { "type": "post", "id": "1", "attributes": { "title": "T" } } }
        """.data(using: .utf8)!
        let doc = try JSONAPIDecoder.decode(SingleResource<Post>.self, from: json)
        XCTAssertNil(MediaPlaybackResolver.resolve(from: doc))
    }
}

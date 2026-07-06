//
//  ModelsDecodingTests.swift
//  PatreonTVTests
//
//  Smoke-test JSON:API decoding against real Patreon API responses captured
//  in live-tests/. These fixtures should live in the test bundle later, but
//  for now we inline a minimum representative fragment.
//

import XCTest
@testable import PatreonTV

final class ModelsDecodingTests: XCTestCase {

    func test_decode_identity_response() throws {
        let json = """
        {
          "data": {
            "type": "user",
            "id": "8462900",
            "attributes": {
              "full_name": "Test User",
              "email": "[email protected]",
              "image_url": "https://c10.patreonusercontent.com/x.png",
              "vanity": "testuser"
            }
          }
        }
        """.data(using: .utf8)!

        let doc = try JSONAPIDecoder.decode(SingleResource<PatreonUser>.self, from: json)
        XCTAssertEqual(doc.data.id, "8462900")
        XCTAssertEqual(doc.data.attributes.fullName, "Test User")
        XCTAssertEqual(doc.data.attributes.vanity, "testuser")
    }

    func test_decode_post_with_media_include() throws {
        let json = """
        {
          "data": {
            "type": "post",
            "id": "12345",
            "attributes": {
              "title": "Test Video",
              "post_type": "video_external_file",
              "current_user_can_view": true,
              "is_paid": true
            }
          },
          "included": [
            {
              "type": "media",
              "id": "999",
              "attributes": {
                "mimetype": "application/x-mpegURL",
                "state": "ready",
                "display": {
                  "url": "https://stream.mux.com/abc123.m3u8?token=xyz",
                  "duration": 1653.85,
                  "width": 1920,
                  "height": 1080,
                  "expires_at": "2026-07-07T04:00:00.000+00:00"
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let doc = try JSONAPIDecoder.decode(SingleResource<Post>.self, from: json)
        XCTAssertEqual(doc.data.attributes.title, "Test Video")
        XCTAssertEqual(doc.data.attributes.postType, .videoExternalFile)
        XCTAssertEqual(doc.data.attributes.currentUserCanView, true)

        // Find the media include and verify the Mux URL round-trips
        var muxURL: URL?
        for inc in doc.included ?? [] {
            if case .media(let media) = inc {
                muxURL = media.attributes.display?.url
            }
        }
        XCTAssertEqual(muxURL?.absoluteString, "https://stream.mux.com/abc123.m3u8?token=xyz")
    }

    func test_post_type_falls_back_to_other_for_unknown() throws {
        let json = """
        {
          "data": {
            "type": "post", "id": "1",
            "attributes": { "title": "x", "post_type": "future_unknown_type" }
          }
        }
        """.data(using: .utf8)!

        let doc = try JSONAPIDecoder.decode(SingleResource<Post>.self, from: json)
        XCTAssertEqual(doc.data.attributes.postType, .other)
    }
}

//
//  FixtureDecodingTests.swift
//  PatreonTVTests
//
//  Decodes real Patreon API responses from the live-tests/ fixtures to make
//  sure our model layer stays in sync with what the API actually returns.
//
//  Fixture files are inlined here as string literals rather than as bundle
//  resources, so the test target has zero resource-copying setup and the
//  fixtures travel with source control (redacted).
//

import XCTest
@testable import PatreonTV

final class FixtureDecodingTests: XCTestCase {

    /// Real identity response, redacted. Shape verified from
    /// .internal/live-tests/02-identity-full-body.json.
    func test_decode_real_identity_shape() throws {
        let json = """
        {
          "data": {
            "id": "8462900",
            "type": "user",
            "attributes": {
              "full_name": "Redacted User",
              "email": "[email protected]",
              "image_url": "https://c10.patreonusercontent.com/redacted.png",
              "thumb_url": "https://c10.patreonusercontent.com/redacted-thumb.png",
              "vanity": "redacteduser",
              "url": "https://www.patreon.com/redacteduser",
              "is_creator": false
            },
            "relationships": {
              "memberships": {
                "data": [
                  { "type": "member", "id": "mem-1" }
                ]
              }
            }
          },
          "included": [
            {
              "type": "member",
              "id": "mem-1",
              "attributes": {
                "patron_status": "active_patron",
                "currently_entitled_amount_cents": 500,
                "is_free_trial": false,
                "is_gifted": false,
                "last_charge_status": "Paid",
                "last_charge_date": "2026-06-15T00:00:00.000+00:00"
              },
              "relationships": {
                "campaign": { "data": { "type": "campaign", "id": "camp-1" } }
              }
            },
            {
              "type": "campaign",
              "id": "camp-1",
              "attributes": {
                "name": "Test Creator",
                "vanity": "testcreator",
                "creation_name": "video essays",
                "patron_count": 12345,
                "is_nsfw": false,
                "image_url": "https://c10.patreonusercontent.com/campaign-hero.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let doc = try JSONAPIDecoder.decode(SingleResource<PatreonUser>.self, from: json)
        XCTAssertEqual(doc.data.id, "8462900")
        XCTAssertEqual(doc.data.attributes.fullName, "Redacted User")
        XCTAssertFalse(doc.data.attributes.isCreator ?? true)

        // Verify the memberships include decoded correctly
        var foundMember: Membership?
        var foundCampaign: Campaign?
        for inc in doc.included ?? [] {
            if case .member(let m) = inc { foundMember = m }
            if case .campaign(let c) = inc { foundCampaign = c }
        }
        XCTAssertNotNil(foundMember)
        XCTAssertTrue(foundMember?.isActivePatron ?? false)
        XCTAssertEqual(foundMember?.attributes.currentlyEntitledAmountCents, 500)
        XCTAssertEqual(foundCampaign?.attributes.name, "Test Creator")
        XCTAssertEqual(foundCampaign?.attributes.creationName, "video essays")
    }

    /// A real Mux HLS URL structure from a video_external_file post.
    /// Shape verified from .internal/live-tests/17-internal-full.json §14.
    func test_decode_video_post_with_mux_hls() throws {
        let json = """
        {
          "data": {
            "type": "post",
            "id": "86262355",
            "attributes": {
              "title": "Real Video Post",
              "post_type": "video_external_file",
              "current_user_can_view": true,
              "is_paid": true,
              "published_at": "2026-05-01T18:30:00.000+00:00"
            },
            "relationships": {
              "media": { "data": [{ "type": "media", "id": "216581623" }] },
              "campaign": { "data": { "type": "campaign", "id": "camp-2" } }
            }
          },
          "included": [
            {
              "type": "media",
              "id": "216581623",
              "attributes": {
                "mimetype": "application/x-mpegURL",
                "state": "ready",
                "file_name": "video.m3u8",
                "download_url": "https://c10.patreonusercontent.com/download-redacted",
                "display": {
                  "url": "https://stream.mux.com/redacted-playback.m3u8?token=eyJ0oken",
                  "duration": 1653.8522,
                  "width": 1920,
                  "height": 1080,
                  "expires_at": "2026-07-07T04:00:00.000+00:00",
                  "closed_captions_enabled": true,
                  "default_thumbnail": {
                    "url": "https://image.mux.com/redacted-thumb.jpg?token=x",
                    "position": 3.0
                  }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let doc = try JSONAPIDecoder.decode(SingleResource<Post>.self, from: json)
        XCTAssertEqual(doc.data.attributes.postType, .videoExternalFile)
        XCTAssertEqual(doc.data.attributes.currentUserCanView, true)

        var muxURL: URL?
        var duration: Double?
        var width: Int?
        for inc in doc.included ?? [] {
            if case .media(let m) = inc {
                muxURL = m.attributes.display?.url
                duration = m.attributes.display?.duration
                width = m.attributes.display?.width
            }
        }
        XCTAssertEqual(muxURL?.host(), "stream.mux.com")
        XCTAssertEqual(muxURL?.pathExtension, "m3u8")
        XCTAssertEqual(duration, 1653.8522)
        XCTAssertEqual(width, 1920)

        let source = MediaPlaybackResolver.resolve(from: doc)
        XCTAssertEqual(source?.url.host(), "stream.mux.com")
        XCTAssertEqual(source?.kind, .video)
    }

    /// A locked post — the OAuth Bearer case from live-probe 17.
    /// display.url is omitted; current_user_can_view is false.
    func test_decode_locked_post_omits_playback_url() throws {
        let json = """
        {
          "data": {
            "type": "post",
            "id": "162743341",
            "attributes": {
              "title": "Locked Post",
              "post_type": "video_external_file",
              "current_user_can_view": false,
              "is_paid": true,
              "content": null,
              "teaser": null
            },
            "relationships": {
              "media": { "data": [{ "type": "media", "id": "999" }] }
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
                  "duration": 344.510833,
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
        XCTAssertEqual(doc.data.attributes.currentUserCanView, false)

        var muxURL: URL?
        for inc in doc.included ?? [] {
            if case .media(let m) = inc { muxURL = m.attributes.display?.url }
        }
        XCTAssertNil(muxURL, "display.url should be absent for gated content")
    }

    /// A stream feed page — Page<Post> with next-cursor pagination.
    func test_decode_paginated_stream() throws {
        let json = """
        {
          "data": [
            { "type": "post", "id": "1", "attributes": { "title": "One", "post_type": "video_external_file" } },
            { "type": "post", "id": "2", "attributes": { "title": "Two", "post_type": "text_only" } }
          ],
          "meta": {
            "pagination": {
              "cursors": { "next": "cursor-xyz" },
              "total": 42
            }
          }
        }
        """.data(using: .utf8)!

        let page = try JSONAPIDecoder.decode(Page<Post>.self, from: json)
        XCTAssertEqual(page.data.count, 2)
        XCTAssertEqual(page.nextCursor, "cursor-xyz")
        XCTAssertEqual(page.meta?.pagination?.total, 42)
    }

    /// Campaign-posts style page — no meta cursor, only `links.next` carrying
    /// the cursor. nextCursor must fall back to it or pagination silently stops.
    func test_decode_page_cursor_fallback_from_links_next() throws {
        let json = """
        {
          "data": [
            { "type": "post", "id": "10", "attributes": { "title": "Ten", "post_type": "video_external_file" } }
          ],
          "links": {
            "next": "https://www.patreon.com/api/campaigns/123/posts?page%5Bcount%5D=30&page%5Bcursor%5D=abc123def"
          }
        }
        """.data(using: .utf8)!

        let page = try JSONAPIDecoder.decode(Page<Post>.self, from: json)
        XCTAssertNil(page.meta?.pagination?.cursors?.next, "this fixture has no meta cursor")
        XCTAssertEqual(page.nextCursor, "abc123def", "should recover the cursor from links.next")
    }

    /// Last page: no meta cursor and no links.next → nextCursor is nil (end).
    func test_decode_page_no_cursor_is_end() throws {
        let json = """
        { "data": [ { "type": "post", "id": "99", "attributes": { "title": "Last" } } ] }
        """.data(using: .utf8)!

        let page = try JSONAPIDecoder.decode(Page<Post>.self, from: json)
        XCTAssertNil(page.nextCursor)
    }
}

//
//  GalleryMockURLProtocol.swift
//  PatreonTV
//
//  DEBUG-only offline stub for the Patreon API. Activated with GALLERY_MOCK=1
//  alongside gallery mode. Lets UI tests and screenshot captures render a
//  fully-populated Home (hero, Continue Watching, creator rows) with no
//  network and no session cookie.
//
//  Routed by URL path; every response is a minimal-but-valid JSON:API
//  document matching the shapes in Models.swift.
//

#if DEBUG
import Foundation

final class GalleryMockURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let body = GalleryMockData.response(forPath: url.path)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

enum GalleryMockData {

    /// Post IDs the mock feed serves — the gallery seeds playback progress for
    /// the first two so the Continue Watching shelf appears.
    static let continueWatchingIDs = ["p-c1-1", "p-c2-1"]

    static func response(forPath path: String) -> Data {
        let json: String
        switch true {
        case path.hasSuffix("/current_user"):
            json = currentUser
        case path.hasSuffix("/members"):
            json = members
        case path.hasSuffix("/stream"):
            json = stream
        case path.contains("/campaigns/") && path.hasSuffix("/posts"):
            let campaignID = path.split(separator: "/").dropLast().last.map(String.init) ?? "c1"
            json = campaignPosts(campaignID: campaignID)
        case path.contains("/posts/"):
            json = singlePost(id: path.split(separator: "/").last.map(String.init) ?? "p-c1-1")
        default:
            json = #"{ "data": [] }"#
        }
        return json.data(using: .utf8)!
    }

    // MARK: - Builders

    private static func campaignJSON(_ id: String, name: String) -> String {
        """
        {
          "type": "campaign", "id": "\(id)",
          "attributes": {
            "name": "\(name)",
            "vanity": "\(id)",
            "creation_name": "mock content",
            "patron_count": 1234,
            "is_nsfw": false,
            "avatar_photo_url": "https://www.patreon.com/mock/\(id)-avatar.jpg",
            "image_url": "https://www.patreon.com/mock/\(id)-image.jpg"
          }
        }
        """
    }

    private static func postJSON(id: String, campaignID: String, title: String, index: Int) -> String {
        """
        {
          "type": "post", "id": "\(id)",
          "attributes": {
            "title": "\(title)",
            "post_type": "video_external_file",
            "published_at": "2026-07-0\(min(index + 1, 9))T12:00:00.000+00:00",
            "thumbnail_url": "https://www.patreon.com/mock/\(id)-thumb.jpg",
            "is_paid": false,
            "current_user_can_view": true
          },
          "relationships": {
            "campaign": { "data": { "type": "campaign", "id": "\(campaignID)" } }
          }
        }
        """
    }

    private static func postsJSON(campaignID: String, name: String, count: Int) -> [String] {
        (1...count).map { i in
            postJSON(
                id: "p-\(campaignID)-\(i)",
                campaignID: campaignID,
                title: "\(name) Episode \(i)",
                index: i
            )
        }
    }

    // MARK: - Documents

    private static let currentUser = """
    {
      "data": {
        "type": "user", "id": "u1",
        "attributes": { "full_name": "Mock Viewer" }
      }
    }
    """

    private static let members = """
    {
      "data": [
        {
          "type": "member", "id": "m1",
          "attributes": { "patron_status": "active_patron" },
          "relationships": { "campaign": { "data": { "type": "campaign", "id": "c1" } } }
        },
        {
          "type": "member", "id": "m2",
          "attributes": { "patron_status": "active_patron" },
          "relationships": { "campaign": { "data": { "type": "campaign", "id": "c2" } } }
        }
      ],
      "included": [
        \(campaignJSON("c1", name: "Astro Lab")),
        \(campaignJSON("c2", name: "Kitchen Physics"))
      ]
    }
    """

    private static let stream = """
    {
      "data": [
        \((postsJSON(campaignID: "c1", name: "Astro Lab", count: 5)
            + postsJSON(campaignID: "c2", name: "Kitchen Physics", count: 5))
            .joined(separator: ",\n"))
      ],
      "included": [
        \(campaignJSON("c1", name: "Astro Lab")),
        \(campaignJSON("c2", name: "Kitchen Physics"))
      ],
      "meta": { "pagination": { "cursors": { "next": null } } }
    }
    """

    private static func campaignPosts(campaignID: String) -> String {
        let name = campaignID == "c1" ? "Astro Lab" : "Kitchen Physics"
        return """
        {
          "data": [
            \(postsJSON(campaignID: campaignID, name: name, count: 8).joined(separator: ",\n"))
          ],
          "meta": { "pagination": { "cursors": { "next": null } } }
        }
        """
    }

    private static func singlePost(id: String) -> String {
        """
        {
          "data": \(postJSON(id: id, campaignID: "c1", title: "Mock Post", index: 1)),
          "included": [ \(campaignJSON("c1", name: "Astro Lab")) ]
        }
        """
    }
}
#endif

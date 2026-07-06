//
//  PatreonClient.swift
//  PatreonTV
//
//  HTTP client for Patreon's internal web API (`https://www.patreon.com/api/*`).
//  Authenticates via the `session_id` cookie captured from PatreonLoginWebView.
//
//  API endpoint reference: docs/patreon-internal-api-openapi.yaml
//  Live-probe evidence:    docs/patreon-research.md §14
//  Sample responses:       live-tests/*.json
//
//  Design: every method returns the full JSON:API document envelope
//  (SingleResource / MultiResource / Page). Callers walk `.included` when they
//  need related resources. This keeps decoding and joining logic uniform.
//
//  This is the internal (undocumented) API. Patreon staff have discouraged
//  third-party use of it — see docs/patreon-research.md §0. Endpoints may
//  change without notice. We handle every request defensively.
//

import Foundation
import os.log

@MainActor
final class PatreonClient {

    static let shared = PatreonClient()
    private init() {}

    private let baseURL = URL(string: "https://www.patreon.com/api")!
    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "API")

    /// The Patreon session cookie. Set by AuthStore after sign-in.
    var sessionID: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": Self.userAgent,
        ]
        config.httpCookieAcceptPolicy = .never   // We inject cookies manually.
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) PatreonTV/0.1"

    // MARK: - Endpoints

    /// GET /api/current_user — the identity + campaigns bootstrap.
    func currentUser() async throws -> PatreonUser {
        let url = baseURL.appending(path: "current_user")
            .appending(queryItems: [
                URLQueryItem(name: "include", value: "memberships.campaign"),
                URLQueryItem(name: "fields[user]", value: "full_name,email,image_url,thumb_url,is_creator,vanity,url"),
                URLQueryItem(name: "fields[campaign]", value: "name,vanity,url,image_url,image_small_url,cover_photo_url,summary,creation_name,patron_count,is_nsfw"),
                URLQueryItem(name: "fields[member]", value: "patron_status,currently_entitled_amount_cents,is_free_trial,is_gifted"),
            ])
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(SingleResource<PatreonUser>.self, from: data).data
    }

    /// GET /api/stream — the fan's home feed of posts from creators they follow.
    /// Requires a session_id cookie; returns empty with OAuth Bearer alone.
    func homeFeed(cursor: String? = nil, limit: Int = 20) async throws -> Page<Post> {
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "include", value: "user,campaign,attachments_media,post_file,media,audio,images"),
            URLQueryItem(name: "fields[post]", value: PostFields.default),
            URLQueryItem(name: "fields[campaign]", value: "name,vanity,image_url,image_small_url,url"),
            URLQueryItem(name: "fields[media]", value: MediaFields.default),
            URLQueryItem(name: "page[count]", value: String(limit)),
        ]
        if let cursor {
            qi.append(URLQueryItem(name: "page[cursor]", value: cursor))
        }
        let url = baseURL.appending(path: "stream").appending(queryItems: qi)
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(Page<Post>.self, from: data)
    }

    /// GET /api/current_user/memberships — creators the user supports.
    /// Returns the full document so callers can join member → campaign.
    func memberships() async throws -> MultiResource<Membership> {
        let url = baseURL.appending(path: "current_user/memberships")
            .appending(queryItems: [
                URLQueryItem(name: "include", value: "campaign"),
                URLQueryItem(name: "fields[campaign]", value: "name,vanity,creation_name,summary,patron_count,is_nsfw,image_url,image_small_url,cover_photo_url,url"),
                URLQueryItem(name: "fields[member]", value: "patron_status,currently_entitled_amount_cents,is_gifted,is_free_trial,last_charge_status,last_charge_date,lifetime_support_cents"),
            ])
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(MultiResource<Membership>.self, from: data)
    }

    /// GET /api/campaigns/{id} — one campaign's public info.
    func campaign(id: String) async throws -> SingleResource<Campaign> {
        let url = baseURL.appending(path: "campaigns/\(id)")
            .appending(queryItems: [
                URLQueryItem(name: "fields[campaign]", value: [
                    "name", "vanity", "url", "summary", "creation_name",
                    "patron_count", "is_nsfw", "image_url", "image_small_url",
                    "cover_photo_url", "main_video_url", "main_video_embed",
                    "has_rss", "rss_feed_title",
                ].joined(separator: ",")),
            ])
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(SingleResource<Campaign>.self, from: data)
    }

    /// GET /api/campaigns/{id}/posts — posts on one campaign.
    func campaignPosts(campaignID: String, cursor: String? = nil, limit: Int = 20) async throws -> Page<Post> {
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "include", value: "attachments_media,post_file,media,audio,images"),
            URLQueryItem(name: "fields[post]", value: PostFields.default),
            URLQueryItem(name: "fields[media]", value: MediaFields.default),
            URLQueryItem(name: "page[count]", value: String(limit)),
        ]
        if let cursor {
            qi.append(URLQueryItem(name: "page[cursor]", value: cursor))
        }
        let url = baseURL.appending(path: "campaigns/\(campaignID)/posts").appending(queryItems: qi)
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(Page<Post>.self, from: data)
    }

    /// GET /api/posts/{id} — a single post with media includes.
    /// Returns the full document; callers walk `included` for the Media
    /// resource containing the Mux HLS URL.
    func post(id: String) async throws -> SingleResource<Post> {
        let url = baseURL.appending(path: "posts/\(id)")
            .appending(queryItems: [
                URLQueryItem(name: "include", value: "campaign,user,attachments_media,post_file,audio,media,images"),
                URLQueryItem(name: "fields[post]", value: PostFields.full),
                URLQueryItem(name: "fields[media]", value: MediaFields.full),
                URLQueryItem(name: "fields[campaign]", value: "name,vanity,image_url,image_small_url,url"),
            ])
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(SingleResource<Post>.self, from: data)
    }

    /// GET /api/search — Patreon's search endpoint (internal).
    /// TODO: shape unverified — spec says path is /api/search, need to probe.
    func search(query: String, limit: Int = 20) async throws -> Page<Post> {
        let url = baseURL.appending(path: "search")
            .appending(queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "include", value: "user,campaign"),
                URLQueryItem(name: "fields[post]", value: PostFields.default),
                URLQueryItem(name: "fields[campaign]", value: "name,vanity,image_url,url"),
                URLQueryItem(name: "page[count]", value: String(limit)),
            ])
        let (data, _) = try await get(url)
        return try JSONAPIDecoder.decode(Page<Post>.self, from: data)
    }

    // MARK: - Transport

    private func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("https://www.patreon.com/", forHTTPHeaderField: "Referer")
        if let sessionID {
            req.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PatreonError.badResponse
        }

        log.debug("GET \(url.path()) → \(http.statusCode)")

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            throw PatreonError.unauthorized
        case 403:
            throw PatreonError.forbidden
        case 404:
            throw PatreonError.notFound
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
            throw PatreonError.rateLimited(retryAfterSeconds: retryAfter)
        default:
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw PatreonError.http(status: http.statusCode, body: body)
        }
    }
}

enum PatreonError: Error, LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfterSeconds: Double)
    case http(status: Int, body: String)
    case badResponse
    case decoding(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session has expired. Please sign in again."
        case .forbidden: "You don't have permission to view this content."
        case .notFound: "This post could not be found."
        case .rateLimited(let s): "Patreon is rate-limiting us. Try again in \(Int(s))s."
        case .http(let status, _): "Patreon returned HTTP \(status)."
        case .badResponse: "Unexpected response from Patreon."
        case .decoding(let underlying): "Could not read response: \(underlying)"
        }
    }
}

// MARK: - Field selectors — extracted so it's easy to see exactly what we ask for.

enum PostFields {
    /// The minimum set we need for a shelf card.
    static let `default` = [
        "title", "teaser", "post_type", "published_at",
        "thumbnail", "thumbnail_url", "image", "meta_image_url",
        "url", "is_paid", "current_user_can_view", "content",
        "embed_url", "embed",
    ].joined(separator: ",")

    /// Everything a post detail screen might need.
    static let full = [
        "title", "content", "teaser", "post_type", "published_at",
        "thumbnail", "thumbnail_url", "image", "meta_image_url",
        "url", "is_paid", "current_user_can_view",
        "embed_url", "embed", "post_file", "video_preview",
        "like_count", "comment_count",
    ].joined(separator: ",")
}

enum MediaFields {
    static let `default` = [
        "mimetype", "media_type", "file_name", "download_url",
        "image_urls", "metadata", "duration_sec", "width", "height",
    ].joined(separator: ",")

    static let full = [
        "mimetype", "media_type", "file_name", "download_url",
        "image_urls", "metadata", "duration_sec", "width", "height",
        "display", "state", "closed_captions_enabled",
    ].joined(separator: ",")
}

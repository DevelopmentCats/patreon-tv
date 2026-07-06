//
//  Models.swift
//  PatreonTV
//
//  Domain models for the Patreon internal API. Field names match the observed
//  API responses (see live-tests/*.json). This is NOT the public v2 API shape.
//

import Foundation

// MARK: - JSON:API envelope types

/// A JSON:API document containing a single primary resource plus its includes.
struct SingleResource<T: JSONAPIResource>: Decodable {
    let data: T
    let included: [Included]?
    let links: Links?
}

/// A JSON:API document containing an array of primary resources.
struct MultiResource<T: JSONAPIResource>: Decodable {
    let data: [T]
    let included: [Included]?
    let links: Links?
}

/// A paged list — same as MultiResource but exposes cursor.
struct Page<T: JSONAPIResource>: Decodable {
    let data: [T]
    let included: [Included]?
    let meta: PageMeta?
    let links: Links?

    var nextCursor: String? { meta?.pagination?.cursors?.next }
}

struct PageMeta: Decodable {
    let pagination: PageCursors?
}

struct PageCursors: Decodable {
    let cursors: Cursors?
    let total: Int?
}

struct Cursors: Decodable {
    let next: String?
}

struct Links: Decodable {
    let next: String?
    let previous: String?
    let first: String?
    let last: String?
}

/// Any resource can be a JSON:API resource — has a type + id.
protocol JSONAPIResource: Decodable, Identifiable {
    var id: String { get }
    var type: String { get }
}

// MARK: - Included box

/// Discriminated container for the `included` array. We only bother
/// decoding the types we actually care about.
enum Included: Decodable {
    case campaign(Campaign)
    case media(Media)
    case user(PatreonUser)
    case member(Membership)
    case tier(Tier)
    case unknown(type: String, id: String)

    private enum CodingKeys: String, CodingKey { case type, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let id = try c.decode(String.self, forKey: .id)
        switch type {
        case "campaign":
            self = .campaign(try Campaign(from: decoder))
        case "media":
            self = .media(try Media(from: decoder))
        case "user":
            self = .user(try PatreonUser(from: decoder))
        case "member":
            self = .member(try Membership(from: decoder))
        case "reward", "tier":
            self = .tier(try Tier(from: decoder))
        default:
            self = .unknown(type: type, id: id)
        }
    }

    var id: String {
        switch self {
        case .campaign(let x): x.id
        case .media(let x): x.id
        case .user(let x): x.id
        case .member(let x): x.id
        case .tier(let x): x.id
        case .unknown(_, let id): id
        }
    }
}

// MARK: - User

struct PatreonUser: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable, Hashable {
        let fullName: String?
        let email: String?
        let imageURL: URL?
        let thumbURL: URL?
        let isCreator: Bool?
        let vanity: String?
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case email
            case imageURL = "image_url"
            case thumbURL = "thumb_url"
            case isCreator = "is_creator"
            case vanity
            case url
        }
    }
}

// MARK: - Campaign

struct Campaign: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable, Hashable {
        let name: String?
        let vanity: String?
        let url: URL?
        let creationName: String?
        let summary: String?
        let patronCount: Int?
        let isNSFW: Bool?
        let imageURL: URL?
        let imageSmallURL: URL?
        /// Only present on some endpoints (e.g., campaign detail).
        let coverPhotoURL: URL?
        let hasRSS: Bool?

        enum CodingKeys: String, CodingKey {
            case name, vanity, url, summary
            case creationName = "creation_name"
            case patronCount = "patron_count"
            case isNSFW = "is_nsfw"
            case imageURL = "image_url"
            case imageSmallURL = "image_small_url"
            case coverPhotoURL = "cover_photo_url"
            case hasRSS = "has_rss"
        }
    }
}

// MARK: - Membership

struct Membership: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes
    let relationships: Relationships?

    struct Attributes: Decodable, Hashable {
        let patronStatus: String?
        let currentlyEntitledAmountCents: Int?
        let isGifted: Bool?
        let isFreeTrial: Bool?
        let lastChargeStatus: String?
        let lastChargeDate: String?
        let nextChargeDate: String?
        let lifetimeSupportCents: Int?

        enum CodingKeys: String, CodingKey {
            case patronStatus = "patron_status"
            case currentlyEntitledAmountCents = "currently_entitled_amount_cents"
            case isGifted = "is_gifted"
            case isFreeTrial = "is_free_trial"
            case lastChargeStatus = "last_charge_status"
            case lastChargeDate = "last_charge_date"
            case nextChargeDate = "next_charge_date"
            case lifetimeSupportCents = "lifetime_support_cents"
        }
    }

    struct Relationships: Decodable, Hashable {
        let campaign: RelationRef?
    }

    var isActivePatron: Bool {
        attributes.patronStatus == "active_patron"
    }
}

// MARK: - Tier

struct Tier: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable, Hashable {
        let title: String?
        let description: String?
        let amountCents: Int?
        let url: URL?
        let requiresShipping: Bool?

        enum CodingKeys: String, CodingKey {
            case title, description, url
            case amountCents = "amount_cents"
            case requiresShipping = "requires_shipping"
        }
    }
}

// MARK: - Post

struct Post: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes
    let relationships: Relationships?

    /// The set of post_type values we've observed in the internal API.
    enum PostType: String, Decodable, Hashable {
        case videoExternalFile = "video_external_file"
        case videoEmbed = "video_embed"
        case audioFile = "audio_file"
        case audioEmbed = "audio_embed"
        case imageFile = "image_file"
        case textOnly = "text_only"
        case podcast
        case link
        case poll
        case livestreamYoutube = "livestream_youtube"
        case livestreamCrowdcast = "livestream_crowdcast"
        case other

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            let raw = try c.decode(String.self)
            self = PostType(rawValue: raw) ?? .other
        }
    }

    struct Attributes: Decodable, Hashable {
        let title: String?
        let content: String?              // HTML body (may be null for gated posts)
        let teaser: String?
        let postType: PostType?
        let publishedAt: String?
        let url: URL?
        let isPaid: Bool?
        /// The critical entitlement flag. If false, media URLs are omitted.
        let currentUserCanView: Bool?
        let thumbnailURL: URL?
        let metaImageURL: URL?
        let embedURL: URL?
        let likeCount: Int?
        let commentCount: Int?

        enum CodingKeys: String, CodingKey {
            case title, content, teaser, url
            case postType = "post_type"
            case publishedAt = "published_at"
            case isPaid = "is_paid"
            case currentUserCanView = "current_user_can_view"
            case thumbnailURL = "thumbnail_url"
            case metaImageURL = "meta_image_url"
            case embedURL = "embed_url"
            case likeCount = "like_count"
            case commentCount = "comment_count"
        }
    }

    struct Relationships: Decodable, Hashable {
        let campaign: RelationRef?
        let user: RelationRef?
        let media: RelationList?
        let images: RelationList?
        let audio: RelationRef?
        let attachmentsMedia: RelationList?

        enum CodingKeys: String, CodingKey {
            case campaign, user, media, images, audio
            case attachmentsMedia = "attachments_media"
        }
    }
}

// MARK: - Media (the piece with the Mux HLS URL)

struct Media: JSONAPIResource {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable, Hashable {
        let mimetype: String?
        let state: String?
        let fileName: String?
        let downloadURL: URL?
        let display: Display?

        enum CodingKeys: String, CodingKey {
            case mimetype, state, display
            case fileName = "file_name"
            case downloadURL = "download_url"
        }
    }

    /// The rich video envelope. When `current_user_can_view` is true for the
    /// containing post, `display.url` contains a signed Mux HLS manifest.
    struct Display: Decodable, Hashable {
        let url: URL?
        let duration: Double?
        let width: Int?
        let height: Int?
        let expiresAt: String?
        let closedCaptionsEnabled: Bool?
        let defaultThumbnail: Thumbnail?

        enum CodingKeys: String, CodingKey {
            case url, duration, width, height
            case expiresAt = "expires_at"
            case closedCaptionsEnabled = "closed_captions_enabled"
            case defaultThumbnail = "default_thumbnail"
        }
    }

    struct Thumbnail: Decodable, Hashable {
        let url: URL?
        let position: Double?
    }
}

// MARK: - Relationship references

struct RelationRef: Decodable, Hashable {
    let data: RelationID?
}

struct RelationList: Decodable, Hashable {
    let data: [RelationID]?
}

struct RelationID: Decodable, Hashable {
    let type: String
    let id: String
}

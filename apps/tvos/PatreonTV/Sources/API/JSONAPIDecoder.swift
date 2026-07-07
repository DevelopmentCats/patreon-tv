//
//  JSONAPIDecoder.swift
//  PatreonTV
//
//  Thin convenience over JSONDecoder configured for Patreon's JSON:API responses.
//  Attaches decoding context so error messages tell us which field failed.
//

import Foundation
import os.log

enum JSONAPIDecoder {

    private static let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Decoding")

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // The internal API mostly uses snake_case which we already map field-by-field
        // in the models, so we do NOT enable convertFromSnakeCase here.
        return d
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            log.error("Decode failed for \(String(describing: type), privacy: .public): \(String(describing: error), privacy: .public)")
            #if DEBUG
            // Body previews can contain PII (the user's email on /current_user),
            // so they are debug-build only and never go through release logging.
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            log.debug("Body preview: \(preview, privacy: .private)")
            #endif
            throw PatreonError.decoding(underlying: error)
        }
    }
}

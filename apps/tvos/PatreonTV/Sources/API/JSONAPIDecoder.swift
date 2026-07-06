//
//  JSONAPIDecoder.swift
//  PatreonTV
//
//  Thin convenience over JSONDecoder configured for Patreon's JSON:API responses.
//  Attaches decoding context so error messages tell us which field failed.
//

import Foundation

enum JSONAPIDecoder {

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
            let preview = String(data: data.prefix(2000), encoding: .utf8) ?? ""
            print("[JSONAPIDecoder] decode failed:")
            print("  type: \(type)")
            print("  error: \(error)")
            print("  body preview: \(preview)")
            throw PatreonError.decoding(underlying: error)
        }
    }
}

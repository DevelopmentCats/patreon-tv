//
//  PairingClient.swift
//  PatreonTV
//
//  Creates a pairing code on the portal and polls until the user completes
//  sign-in on their phone or computer.
//

import Foundation
import os.log

struct PairingSession: Sendable {
    let code: String
    let displayCode: String
    let linkURL: URL
    let expiresAt: Date
}

enum PairingPollStatus: Sendable {
    case pending
    case complete(sessionID: String)
    case expired
    case failed(String)
}

actor PairingClient {

    static let shared = PairingClient()

    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Pairing")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func createSession() async throws -> PairingSession {
        var request = URLRequest(url: PairingConfig.baseURL.appending(path: "api/pairing/create"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PairingError.http(status: status)
        }

        let payload = try JSONDecoder().decode(CreateResponse.self, from: data)
        guard let linkURL = URL(string: payload.link_url),
              let expiresAt = Self.parseExpiresAt(payload.expires_at)
        else {
            log.error("Bad create payload: link_url=\(payload.link_url) expires_at=\(payload.expires_at)")
            throw PairingError.badResponse
        }

        log.info("Created pairing code \(payload.display_code)")
        return PairingSession(
            code: payload.code,
            displayCode: payload.display_code,
            linkURL: linkURL,
            expiresAt: expiresAt
        )
    }

    func poll(code: String) async -> PairingPollStatus {
        let url = PairingConfig.baseURL.appending(path: "api/pairing/\(code)")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Unexpected response from pairing service.")
            }

            switch http.statusCode {
            case 200:
                let payload = try JSONDecoder().decode(PollResponse.self, from: data)
                if payload.status == "complete", let sessionID = payload.session_id, !sessionID.isEmpty {
                    return .complete(sessionID: sessionID)
                }
                return .pending
            case 404:
                return .expired
            default:
                return .failed("Pairing service returned HTTP \(http.statusCode).")
            }
        } catch {
            log.error("Poll failed: \(String(describing: error))")
            return .failed(error.localizedDescription)
        }
    }

    func waitForSession(code: String, expiresAt: Date) async -> PairingPollStatus {
        while Date() < expiresAt {
            let status = await poll(code: code)
            switch status {
            case .pending:
                try? await Task.sleep(for: .seconds(2))
            case .complete, .expired, .failed:
                return status
            }
        }
        return .expired
    }

    private struct CreateResponse: Decodable {
        let code: String
        let display_code: String
        let link_url: String
        let expires_at: String
    }

    private struct PollResponse: Decodable {
        let status: String
        let session_id: String?
    }

    /// Server emits ISO-8601 with fractional seconds; default formatter rejects that.
    private static func parseExpiresAt(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

enum PairingError: Error, LocalizedError {
    case http(status: Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let status):
            "Could not reach the pairing service (HTTP \(status)). Is it running?"
        case .badResponse:
            "Unexpected response from the pairing service."
        }
    }
}

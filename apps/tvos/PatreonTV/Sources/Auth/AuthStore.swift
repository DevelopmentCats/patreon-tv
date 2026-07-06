//
//  AuthStore.swift
//  PatreonTV
//
//  Owns the current session state and the persisted session_id cookie.
//  Uses Keychain for storage.
//
//  See docs/patreon-research.md §14 for why we use the session_id cookie
//  rather than OAuth Bearer: OAuth cannot unlock paid content
//  (current_user_can_view returns false for a paying patron via OAuth).
//  Only a real logged-in web session grants entitlement.
//

import Foundation
import Observation
import os.log

@Observable
@MainActor
final class AuthStore {

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(userID: String)
    }

    private(set) var state: State = .unknown
    private(set) var currentUser: PatreonUser?

    private let keychain = KeychainService(service: "com.patreontv.PatreonTV")
    private let sessionKey = "patreon_session_id"
    private let userIDKey = "patreon_user_id"
    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Auth")

    /// Called from `.task` on app launch. Reads the stored session_id and
    /// verifies it against `/api/current_user`. If valid, transitions to
    /// .signedIn; otherwise .signedOut.
    func restoreSession() async {
        guard let sessionID = keychain.string(forKey: sessionKey), !sessionID.isEmpty else {
            log.info("No stored session")
            state = .signedOut
            return
        }

        // Configure the shared API client with the cookie, then verify.
        PatreonClient.shared.sessionID = sessionID
        do {
            let user = try await PatreonClient.shared.currentUser()
            currentUser = user
            state = .signedIn(userID: user.id)
            log.info("Restored session for user \(user.id)")
        } catch {
            log.error("Session restore failed: \(String(describing: error))")
            // Failed — clear and re-auth
            keychain.remove(forKey: sessionKey)
            keychain.remove(forKey: userIDKey)
            PatreonClient.shared.sessionID = nil
            state = .signedOut
        }
    }

    /// Called by SignInView after WKWebView captures a session_id cookie.
    func completeSignIn(sessionID: String) async {
        keychain.set(sessionID, forKey: sessionKey)
        PatreonClient.shared.sessionID = sessionID

        do {
            let user = try await PatreonClient.shared.currentUser()
            currentUser = user
            keychain.set(user.id, forKey: userIDKey)
            state = .signedIn(userID: user.id)
            log.info("Sign-in complete for user \(user.id)")
        } catch {
            log.error("Sign-in verification failed: \(String(describing: error))")
            keychain.remove(forKey: sessionKey)
            PatreonClient.shared.sessionID = nil
            state = .signedOut
        }
    }

    func signOut() {
        keychain.remove(forKey: sessionKey)
        keychain.remove(forKey: userIDKey)
        PatreonClient.shared.sessionID = nil
        currentUser = nil
        state = .signedOut
        log.info("Signed out")
    }
}

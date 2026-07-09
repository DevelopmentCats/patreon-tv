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
        /// The stored session was definitively rejected mid-use (401/403).
        /// Distinct from .signedOut so the sign-in screen can explain why.
        case sessionExpired
        case signedIn(userID: String)
    }

    private(set) var state: State = .unknown
    private(set) var currentUser: PatreonUser?

    private let keychain = KeychainService(service: "com.patreontv.PatreonTV")
    private let sessionKey = "patreon_session_id"
    private let userIDKey = "patreon_user_id"
    private let log = Logger(subsystem: "com.patreontv.PatreonTV", category: "Auth")
    private var isVerifyingAuthFailure = false

    init() {
        // Any 401 from the API layer triggers a re-verification; if the
        // session really is dead we surface the re-pair screen instead of
        // leaving each content screen showing a generic error.
        PatreonClient.shared.authFailureHandler = { [weak self] in
            guard let self else { return }
            Task { await self.handleAuthFailure() }
        }
    }

    /// Called from `.task` on app launch. Reads the stored session_id and
    /// verifies it against `/api/current_user`. If valid, transitions to
    /// .signedIn; otherwise .signedOut.
    ///
    /// Only a definitive rejection (401/403) clears the stored credential.
    /// Transient failures — no network, Patreon outage, rate limiting — keep
    /// the session and enter .signedIn optimistically so an offline launch
    /// doesn't force the user to re-pair.
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
            if Self.shouldClearSession(after: error) {
                // Patreon definitively rejected the session — clear and re-auth.
                expireSession()
            } else if let storedUserID = keychain.string(forKey: userIDKey), !storedUserID.isEmpty {
                // Transient error — keep the credential and proceed. Content
                // screens show their own retryable errors while offline.
                state = .signedIn(userID: storedUserID)
                log.info("Proceeding with stored session despite transient error")
            } else {
                // No cached user id to proceed with; keep the credential in the
                // keychain (a later launch or re-pair will overwrite it).
                state = .signedOut
            }
        }
    }

    /// True only for errors that mean Patreon rejected the credential itself.
    /// Everything else (network failures, 5xx, rate limits, decode errors) is
    /// treated as transient and must NOT destroy the stored session.
    nonisolated static func shouldClearSession(after error: Error) -> Bool {
        switch error {
        case PatreonError.unauthorized, PatreonError.forbidden:
            return true
        default:
            return false
        }
    }

    /// Called by SignInView after the user submits a session_id cookie.
    func completeSignIn(sessionID: String) async {
        if !keychain.set(sessionID, forKey: sessionKey) {
            log.error("Could not persist session to keychain; sign-in will not survive relaunch")
        }
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
            PatreonClient.shared.clearSession()
            state = .signedOut
        }
    }

    func signOut() {
        keychain.remove(forKey: sessionKey)
        keychain.remove(forKey: userIDKey)
        PatreonClient.shared.clearSession()
        currentUser = nil
        state = .signedOut
        log.info("Signed out")
    }

    // MARK: - Mid-session expiry

    /// Called (debounced) by PatreonClient when a request 401s mid-session.
    /// Re-verifies against `/api/current_user`; only a definitive rejection
    /// there tears the session down, so a flaky endpoint can't log us out.
    func handleAuthFailure() async {
        guard case .signedIn = state, !isVerifyingAuthFailure else { return }
        isVerifyingAuthFailure = true
        defer { isVerifyingAuthFailure = false }

        do {
            let user = try await PatreonClient.shared.currentUser()
            // Session is actually fine — the 401 was endpoint-specific noise.
            currentUser = user
            log.info("Auth re-verification passed; keeping session")
        } catch {
            if Self.shouldClearSession(after: error) {
                log.error("Session rejected mid-use — entering re-pair flow")
                expireSession()
            } else {
                log.info("Auth re-verification hit transient error; keeping session")
            }
        }
    }

    private func expireSession() {
        keychain.remove(forKey: sessionKey)
        keychain.remove(forKey: userIDKey)
        PatreonClient.shared.clearSession()
        currentUser = nil
        state = .sessionExpired
    }
}

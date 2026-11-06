//
//  AuthRefreshPolicy.swift
//  Kinematic
//
//  The rules that decide whether a phone stays signed in. Kept free of networking / Keychain / UI so they are unit
//  tested (`AuthRefreshPolicyTests`); `KinematicRepository.refreshAccessToken` and `KeychainTokenStore` only apply them.
//
//  Each rule is a way the app used to sign people out without anyone asking:
//
//   * A refresh answer of ANY 4xx — including 429 (rate limited), 403 / 404 from a proxy, 408 — was "the refresh token
//     was rejected" and tore the session down. Only 400 / 401 from /auth/refresh says the token itself is dead.
//   * A refresh that returned 200 but whose body we could not decode / that said `success:false` was also "dead".
//     A reply we cannot read is not a verdict.
//   * Every 401 that arrived after somebody else had just refreshed spent another refresh (another rotation, another
//     chance to lose a response and keep a token the server already rotated away).
//   * The Keychain cache remembered "absent" for ANY failed read — including errSecInteractionNotAllowed (device not
//     yet unlocked since boot, e.g. a background launch for location). The process then believed it was signed out
//     until it was killed.
//

import Foundation
import Security

enum AuthRefreshPolicy {

    /// The refresh endpoint answered that the refresh token ITSELF is no good (unknown / expired / already used /
    /// revoked). The backend sends 401 for this (a 400 from GoTrue is mapped to 401 too); both mean "sign in again".
    /// Nothing else does: 403 / 404 / 408 / 429 / 5xx / a network error are "could not find out" -> keep the session.
    static func isDefinitiveRejection(status: Int) -> Bool {
        status == 400 || status == 401
    }

    /// Seconds during which a successful refresh is reused by callers that failed with a 401 just before it
    /// finished. Their request went out with the OLD access token; replaying it with the current one is enough.
    static let recentRefreshWindow: TimeInterval = 5

    /// Whether a caller that just got a 401 should skip refreshing because a refresh completed moments ago.
    static func shouldReuseRecentRefresh(lastSuccess: Date?, now: Date = Date(), window: TimeInterval = recentRefreshWindow) -> Bool {
        guard let last = lastSuccess else { return false }
        let age = now.timeIntervalSince(last)
        return age >= 0 && age < window
    }

    /// What a finished refresh round-trip means for the session.
    enum Outcome: Equatable {
        case refreshed(accessToken: String, refreshToken: String?)
        case rejected      // refresh token definitively dead -> sign out
        case transient     // keep the session, try again later
    }

    /// Classifies the HTTP status + body of POST /auth/refresh.
    static func outcome(status: Int, body: Data) -> Outcome {
        if isDefinitiveRejection(status: status) { return .rejected }
        guard status == 200 else { return .transient }
        struct Payload: Decodable {
            let success: Bool?
            let data: Inner?
            struct Inner: Decodable {
                let accessToken: String?
                let refreshToken: String?
                enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token" }
            }
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: body),
              p.success == true,
              let access = p.data?.accessToken, !access.isEmpty
        else { return .transient }
        let refresh = (p.data?.refreshToken).flatMap { $0.isEmpty ? nil : $0 }
        return .refreshed(accessToken: access, refreshToken: refresh)
    }
}

enum KeychainReadPolicy {
    /// May a failed Keychain read be remembered as "this item does not exist"?
    /// Only when the Keychain says so. Anything else (locked before first unlock, interaction not allowed, a
    /// transient service error) says nothing about whether the item exists; remembering it as absent would keep a
    /// signed-in user "logged out" for the rest of the process.
    static func shouldCacheAbsence(status: OSStatus) -> Bool {
        status == errSecItemNotFound
    }
}

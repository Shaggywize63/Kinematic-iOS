//
//  AttendanceRules.swift
//  Kinematic
//
//  The per-client attendance rules the server resolves for the signed-in user (`GET /attendance/rules`):
//  whether a selfie is demanded at check-in / check-out, whether every form is filled between a check-in and a
//  check-out, whether Clock-In first asks "How are you travelling today?" (and the choices), whether offline
//  check-in is allowed, and the shift times.
//
//  Opt-in per client BY DATA. A client that configured nothing (or a phone that never reached the server) reads as
//  `AttendanceRules()` — selfie REQUIRED, no form check-in, no travel question, no offline capture — which is exactly
//  the app as it was before these rules existed. Only an explicit `selfie_required: false` turns the selfie off,
//  only an explicit `true` turns the others on.
//
//  Pieces (all pure Foundation except the store, so the rules are unit-tested — see KinematicTests/AttendanceRulesTests,
//  TransportModeTests):
//    • TransportOption / AttendanceRules / AttendanceRulesInfo — the model, with a tolerant decoder (unknown, missing,
//      mistyped keys never fail the load; a bad value reads as its default).
//    • AttendanceRulesParser — the tolerant reader over the reply's JSON tree.
//    • AttendanceRulesCache — the last answer for THIS user, kept on the phone so an offline start keeps the behaviour
//      the server last told this person. Keyed by user id, wiped at sign-out (SessionCleanup).
//    • AttendanceRulesRefresh — when a Home load asks the server again.
//    • AttendanceRulesStore — the observable holder the screens read (`AttendanceRulesStore.shared.rules`).
//    • TransportMode — the small pure rules of the mode of transport (sanitize, isActive, modeToSend, labelFor,
//      preselectVehicle, chip, needsRepair, applyChange ...).
//

import Foundation
import Combine

// MARK: - A choice of "How are you travelling today?"

/// One answer to "How are you travelling today?" (`transport_modes` of `GET /attendance/rules`). `id` is what is sent
/// (`[a-z0-9_]`, at most 40 characters), `label` what the rep reads, `vehicle` = it is a vehicle of the rep's expense
/// policy (so the post-checkout travel claim can pre-select it); `public_transport` / `other` are not.
struct TransportOption: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var label: String
    var vehicle: Bool

    init(id: String, label: String, vehicle: Bool = false) {
        self.id = id
        self.label = label
        self.vehicle = vehicle
    }

    private enum CodingKeys: String, CodingKey { case id, label, vehicle }

    /// Tolerant: a missing label reads as empty (`TransportMode.sanitize` then makes it readable), a missing or
    /// mistyped `vehicle` is false. A row with no `id` cannot be used; it decodes to an empty id and is dropped by
    /// `TransportMode.sanitize`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId: String? = try? c.decodeIfPresent(String.self, forKey: .id)
        let rawLabel: String? = try? c.decodeIfPresent(String.self, forKey: .label)
        let rawVehicle: Bool? = try? c.decodeIfPresent(Bool.self, forKey: .vehicle)
        self.id = rawId ?? ""
        self.label = rawLabel ?? ""
        self.vehicle = rawVehicle ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(vehicle, forKey: .vehicle)
    }
}

// MARK: - The rules

/// The resolved attendance rules for the signed-in user. The defaults ARE today's behaviour.
struct AttendanceRules: Equatable {
    /// A selfie is demanded at check-in / check-out. Absent reads as REQUIRED.
    var selfieRequired: Bool = true
    /// Every form is filled between a check-in and a check-out (time + GPS, no photo). Absent reads as NOT required.
    var formCheckinRequired: Bool = false
    /// Clock-In first asks "How are you travelling today?" and the answer is stored on the day's attendance.
    var trackTransportMode: Bool = false
    /// The choices behind that question, as the server resolved them for THIS user (already `TransportMode.sanitize`d
    /// when read from a reply). Only meaningful while `trackTransportMode` is on.
    var transportModes: [TransportOption] = []
    /// A check-in / check-out made without a connection is kept with its real capture time and sent later.
    var allowOfflineCheckin: Bool = false
    /// Shift start / end as "HH:MM" (24 h) and the late grace, when the reply carried them. Nil = not sent.
    var shiftStart: String? = nil
    var shiftEnd: String? = nil
    var graceMinutes: Int? = nil
    /// Weekly-off weekdays, 0 = Sunday ... 6 = Saturday, when the reply carried them.
    var weeklyOff: [Int]? = nil

    /// Documented server defaults for the shift values (used only where a screen needs a number and the reply had none).
    static let defaultShiftStart = "09:30"
    static let defaultShiftEnd = "18:00"
    static let defaultGraceMinutes = 15
    static let defaultWeeklyOff: [Int] = [0]

    /// Ask the question at Clock-In? Only when the rule is on AND there is something to choose from; an unknown /
    /// never-loaded answer, or a rule that is on with no choices, asks nothing (today's flow).
    var transportPromptActive: Bool {
        TransportMode.isActive(trackTransportMode: trackTransportMode, options: transportModes)
    }

    /// Does a punch open the camera? True unless the client turned the selfie off.
    var needsCamera: Bool { selfieRequired }
}

/// `GET /attendance/rules` → `{ configured, rules, transport_modes }`. `configured` is true only when the client has
/// an `attendance_rules` object at all.
struct AttendanceRulesInfo: Equatable {
    var configured: Bool = false
    var rules: AttendanceRules = AttendanceRules()
}

// MARK: - Tolerant decoding

extension AttendanceRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case selfieRequired = "selfie_required"
        case formCheckinRequired = "form_checkin_required"
        case trackTransportMode = "track_transport_mode"
        case transportModes = "transport_modes"
        case allowOfflineCheckin = "allow_offline_checkin"
        case shiftStart = "shift_start"
        case shiftEnd = "shift_end"
        case graceMinutes = "grace_minutes"
        case weeklyOff = "weekly_off"
    }

    /// Never throws for a wrong shape: the rules read from whatever JSON is there (see `AttendanceRulesParser`), and
    /// anything missing, unknown or mistyped reads as its default.
    init(from decoder: Decoder) throws {
        let tree: AnyJSON = (try? AnyJSON(from: decoder)) ?? .null
        self = AttendanceRulesParser.rules(rulesObject: tree, outer: nil)
    }

    /// The shape the server uses for `rules`, with the choices nested so one JSON value holds everything (this is what
    /// `AttendanceRulesCache` stores; the parser also reads `transport_modes` inside `rules`).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selfieRequired, forKey: .selfieRequired)
        try c.encode(formCheckinRequired, forKey: .formCheckinRequired)
        try c.encode(trackTransportMode, forKey: .trackTransportMode)
        try c.encode(transportModes, forKey: .transportModes)
        try c.encode(allowOfflineCheckin, forKey: .allowOfflineCheckin)
        try c.encodeIfPresent(shiftStart, forKey: .shiftStart)
        try c.encodeIfPresent(shiftEnd, forKey: .shiftEnd)
        try c.encodeIfPresent(graceMinutes, forKey: .graceMinutes)
        try c.encodeIfPresent(weeklyOff, forKey: .weeklyOff)
    }
}

/// Forgiving reader for the reply of `GET /attendance/rules`. It accepts both the usual `{ success, data: ... }`
/// envelope and the bare payload, a boolean sent as "true" / "false" or 0 / 1, a number sent as a string, and skips a
/// single unreadable choice instead of failing the list. It never throws: unreadable input gives nil / the defaults.
enum AttendanceRulesParser {

    /// `{ configured, rules: { ... }, transport_modes: [...] }`; nil when the reply is not an object at all.
    static func info(from root: AnyJSON?) -> AttendanceRulesInfo? {
        guard let o = object(unwrap(root)) else { return nil }
        let rulesTree: AnyJSON? = o["rules"]
        let rules = Self.rules(rulesObject: rulesTree ?? .null, outer: o)
        let configured: Bool = bool(o["configured"]) ?? false
        return AttendanceRulesInfo(configured: configured, rules: rules)
    }

    /// The rules from the `rules` object. `outer` is the object that holds `rules` (its `transport_modes` is where the
    /// server puts the choices; one nested inside `rules` is read too when the outer one is not an array).
    static func rules(rulesObject: AnyJSON, outer: [String: AnyJSON]?) -> AttendanceRules {
        let r: [String: AnyJSON] = object(rulesObject) ?? [:]
        var out = AttendanceRules()
        // Only an explicit false turns the selfie off; only an explicit true turns the others on.
        if let v = bool(r["selfie_required"]) { out.selfieRequired = v }
        if let v = bool(r["form_checkin_required"]) { out.formCheckinRequired = v }
        if let v = bool(r["track_transport_mode"]) { out.trackTransportMode = v }
        if let v = bool(r["allow_offline_checkin"]) { out.allowOfflineCheckin = v }
        out.shiftStart = text(r["shift_start"])
        out.shiftEnd = text(r["shift_end"])
        if let n = number(r["grace_minutes"]) { out.graceMinutes = Int(n) }
        if let days = array(r["weekly_off"]) {
            var list: [Int] = []
            for d in days {
                if let n = number(d) { list.append(Int(n)) }
            }
            out.weeklyOff = list
        }
        // The choices are kept only while the rule is on, and only the ones the server could accept.
        if out.trackTransportMode {
            let fromOuter: [TransportOption]? = options(outer?["transport_modes"])
            let fromRules: [TransportOption]? = options(r["transport_modes"])
            out.transportModes = TransportMode.sanitize(fromOuter ?? fromRules)
        } else {
            out.transportModes = []
        }
        return out
    }

    /// `[ { id, label, vehicle } ]`. Nil when the element is not an array (so the caller can try the other place);
    /// otherwise the readable rows, un-sanitized (a row without an id is skipped here).
    static func options(_ el: AnyJSON?) -> [TransportOption]? {
        guard let rows = array(el) else { return nil }
        var out: [TransportOption] = []
        for row in rows {
            guard let r = object(row), let id = text(r["id"]) else { continue }
            let label: String = text(r["label"]) ?? ""
            let vehicle: Bool = bool(r["vehicle"]) ?? false
            out.append(TransportOption(id: id, label: label, vehicle: vehicle))
        }
        return out
    }

    // MARK: tolerant helpers

    /// `data` of a `{ success, data }` envelope when there is one, else the value itself.
    static func unwrap(_ root: AnyJSON?) -> AnyJSON? {
        guard let root = root else { return nil }
        if case .null = root { return nil }
        if case .object(let o) = root, let data = o["data"] {
            if case .null = data { return root }
            return data
        }
        return root
    }

    static func object(_ j: AnyJSON?) -> [String: AnyJSON]? {
        if case .object(let o)? = j { return o }
        return nil
    }

    static func array(_ j: AnyJSON?) -> [AnyJSON]? {
        if case .array(let a)? = j { return a }
        return nil
    }

    /// A non-blank string (a number reads as its text); nil for anything else.
    static func text(_ j: AnyJSON?) -> String? {
        switch j {
        case .string(let s)?:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case .number(let n)?:
            if n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
            return String(n)
        default:
            return nil
        }
    }

    /// A finite number, or a string holding one ("20", "1,200"). Anything else is nil.
    static func number(_ j: AnyJSON?) -> Double? {
        switch j {
        case .number(let n)?:
            return n.isFinite ? n : nil
        case .string(let s)?:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            if let d = Double(t), d.isFinite { return d }
            return nil
        default:
            return nil
        }
    }

    /// A boolean; "true" / "false" (any case) and numbers (non-zero = true) are tolerated, anything else is nil.
    static func bool(_ j: AnyJSON?) -> Bool? {
        switch j {
        case .bool(let b)?:
            return b
        case .string(let s)?:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" { return true }
            if t == "false" { return false }
            return nil
        case .number(let n)?:
            return n != 0
        default:
            return nil
        }
    }
}

// MARK: - Remembered per user

/// The last rules answer THIS user got, remembered so an offline start (or a failed fetch) keeps the behaviour the
/// server last told this person. Keyed by user id, so one person's answer never serves another, and wiped at sign-out
/// (`SessionCleanup` lists the prefix). The `UserDefaults` is a parameter so tests use their own suite.
enum AttendanceRulesCache {
    /// Every key starts with this; `SessionCleanup` removes all of them at sign-out.
    static let keyPrefix = "attendance_rules."

    /// "attendance_rules.<user id>"; nil without a user id (nothing to key it by).
    static func key(userId: String?) -> String? {
        let u = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return nil }
        return keyPrefix + u
    }

    /// The remembered rules; nil when there is none (never loaded, another user's, wiped, or unreadable).
    static func read(key: String?, in defaults: UserDefaults = .standard) -> AttendanceRules? {
        guard let key = key, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AttendanceRules.self, from: data)
    }

    /// Remember the rules from a successful load.
    static func write(_ rules: AttendanceRules, key: String?, in defaults: UserDefaults = .standard) {
        guard let key = key, let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - When to ask the server again

/// How often a Home load asks for the rules again: a successful answer is trusted for five minutes, a failed one is
/// retried after a minute (not on every load while offline). Login and app start always ask (`force`).
enum AttendanceRulesRefresh {
    /// How long a successful fetch is trusted.
    static let ttl: TimeInterval = 5 * 60
    /// After a FAILED fetch the next one is tried only this much later.
    static let retryAfterFailure: TimeInterval = 60

    /// Ask the server again? `stamp` is what `stampAfterAttempt` returned for the last attempt (nil = none yet this run).
    static func shouldRefresh(now: Date, stamp: Date?, force: Bool) -> Bool {
        if force { return true }
        guard let stamp = stamp else { return true }
        if now < stamp { return true }                       // the clock moved back
        return now.timeIntervalSince(stamp) >= ttl
    }

    /// The value to remember after an attempt at `now`, so `shouldRefresh` answers "yes" again after `ttl` following a
    /// success, or after `retryAfterFailure` following a failure.
    static func stampAfterAttempt(now: Date, success: Bool) -> Date {
        success ? now : now.addingTimeInterval(-(ttl - retryAfterFailure))
    }
}

// MARK: - The holder the screens read

/// The attendance rules for the signed-in user, as one observable object. `rules` is what the screens read; until the
/// first answer arrives (and for a client that never configured anything, or a phone that never reached the server)
/// it is the defaults — today's behaviour. `didLoad` turns true once this user's rules are known: restored from the
/// phone, or after the first fetch attempt finished (a failed one leaves the defaults / the remembered copy and still
/// unblocks the screen, because failing soft means "today's behaviour").
@MainActor
final class AttendanceRulesStore: ObservableObject {
    static let shared = AttendanceRulesStore()

    @Published private(set) var rules: AttendanceRules = AttendanceRules()
    @Published private(set) var didLoad: Bool = false

    private let defaults: UserDefaults
    private let userIdProvider: () -> String?
    private let fetchProvider: (() async -> AttendanceRulesInfo?)?
    /// Whose rules `rules` holds (the user id); nil = nobody yet.
    private var heldFor: String? = nil
    private var lastAttemptStamp: Date? = nil
    private var refreshing = false

    /// `defaults`, `userId` and `fetch` are test seams (production passes none): where the remembered copy lives, who is
    /// signed in, and the request.
    init(defaults: UserDefaults? = nil,
         userId: (() -> String?)? = nil,
         fetch: (() async -> AttendanceRulesInfo?)? = nil) {
        self.defaults = defaults ?? UserDefaults.standard
        self.userIdProvider = userId ?? { Session.currentUser?.id }
        self.fetchProvider = fetch
        restoreCached()
    }

    /// Put the remembered copy for the signed-in user in `rules` (synchronous, no network), so a cold start without
    /// signal still behaves the way the server last said. Also re-keys the holder when the signed-in user changed:
    /// nothing of the previous person survives.
    func restoreCached() {
        let uid = normalized(userIdProvider())
        if uid == heldFor && (didLoad || uid == nil) { return }
        if uid != heldFor {
            heldFor = uid
            lastAttemptStamp = nil
            rules = AttendanceRules()
            didLoad = false
        }
        if let cached = AttendanceRulesCache.read(key: AttendanceRulesCache.key(userId: uid), in: defaults) {
            rules = cached
            didLoad = true
        }
    }

    /// The rules to act on right now: the signed-in user's, re-keyed first so another person's never leak through.
    func currentRules() -> AttendanceRules {
        restoreCached()
        return rules
    }

    /// Forget everything held (sign-out). The remembered copy on disk is wiped by `SessionCleanup`.
    func reset() {
        heldFor = nil
        lastAttemptStamp = nil
        rules = AttendanceRules()
        didLoad = false
    }

    /// Ask the server (throttled: five minutes after a success, a minute after a failure; `force` always asks). A
    /// failure keeps what is held — the remembered copy, or the defaults — and never throws.
    func refresh(force: Bool = false) async {
        restoreCached()
        guard Session.isAuthenticated || fetchProvider != nil else { return }
        if refreshing { return }
        if !AttendanceRulesRefresh.shouldRefresh(now: Date(), stamp: lastAttemptStamp, force: force) { return }
        refreshing = true
        defer { refreshing = false }

        // Fixed BEFORE the request: the answer belongs to this user even if the session changes while it is in flight.
        let askedFor = normalized(userIdProvider())
        let info: AttendanceRulesInfo?
        if let fetch = fetchProvider {
            info = await fetch()
        } else {
            info = await KinematicRepository.shared.fetchAttendanceRules()
        }
        // Somebody else signed in while we waited: this answer is not theirs.
        if normalized(userIdProvider()) != askedFor { return }

        lastAttemptStamp = AttendanceRulesRefresh.stampAfterAttempt(now: Date(), success: info != nil)
        if let info = info {
            rules = info.rules
            AttendanceRulesCache.write(info.rules, key: AttendanceRulesCache.key(userId: askedFor), in: defaults)
        }
        didLoad = true
    }

    private func normalized(_ id: String?) -> String? {
        let t = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Mode of transport

/// The small, pure rules of MODE OF TRANSPORT ("How are you travelling today?").
///
/// Opt-in per client BY DATA: everything here only matters when the signed-in user's attendance rules say
/// `track_transport_mode: true` AND the server handed over at least one choice (`transport_modes`). With the rule off,
/// absent, or never loaded (`isActive` false) nothing is asked, nothing is sent and nothing is shown: Clock-In is the
/// flow it always was.
///
/// When it is on, Clock-In first shows a REQUIRED single-choice step; the chosen id travels with the check-in request
/// (and with a queued check-in), Home shows it as a chip with a "Change" action (`PATCH /attendance/transport-mode`,
/// online only), and the post-checkout travel prompt pre-selects the vehicle when the mode is one of the expense
/// policy's vehicles (`preselectVehicle`).
enum TransportMode {

    /// The two fixed, non-vehicle choices the server always appends. Nothing is pre-selected for either of them.
    static let publicTransport = "public_transport"
    static let other = "other"

    /// The server accepts `[a-z0-9_]`, at most this long.
    static let maxIdLength = 40
    /// A sane ceiling on how many choices one chip row / one stored record holds.
    static let maxOptions = 12
    /// Longest label kept (a longer one is cut).
    static let maxLabelLength = 60

    /// True for an id the server would accept (`[a-z0-9_]`, 1...40 characters).
    static func isValidId(_ id: String?) -> Bool {
        guard let id = id, !id.isEmpty, id.unicodeScalars.count <= maxIdLength else { return false }
        for u in id.unicodeScalars {
            let v: UInt32 = u.value
            let lower: Bool = v >= 97 && v <= 122
            let digit: Bool = v >= 48 && v <= 57
            if !(lower || digit || v == 95) { return false }
        }
        return true
    }

    // MARK: the choices

    /// The choices to remember / show: only ids the server could accept, no repeated id (the first wins, so the
    /// policy's order is kept), a blank label replaced by a readable form of the id, an over-long label cut, at most
    /// `maxOptions`. Nil in = nothing out.
    static func sanitize(_ options: [TransportOption]?) -> [TransportOption] {
        guard let options = options, !options.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [TransportOption] = []
        for o in options {
            let id: String = o.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isValidId(id) { continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            var label: String = o.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty { label = prettify(id) }
            if label.count > maxLabelLength { label = String(label.prefix(maxLabelLength)) }
            out.append(TransportOption(id: id, label: label, vehicle: o.vehicle))
            if out.count >= maxOptions { break }
        }
        return out
    }

    /// `own_bike` -> `Own bike`: how an id reads when the server sent no label.
    static func prettify(_ id: String) -> String {
        let s: String = id.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ")
        guard let first = s.first else { return s }
        return String(first).uppercased() + String(s.dropFirst())
    }

    /// Is the question to be asked at all? Only when the rule is on AND there is something to choose from. A rule that
    /// is on with no choices (an older server, an unreadable reply) asks nothing: guessing ids the server may not know
    /// would only get the check-in refused.
    static func isActive(trackTransportMode: Bool, options: [TransportOption]) -> Bool {
        trackTransportMode && !options.isEmpty
    }

    /// The rep's pick when it is one of the offered choices; nil for blank, unknown or not offered (nothing is ever
    /// invented).
    static func choice(picked: String?, options: [TransportOption]) -> String? {
        guard let id = clean(picked) else { return nil }
        return options.first(where: { $0.id == id })?.id
    }

    /// What goes on a check-in request: `chosen` when the question is active and `chosen` is an offered choice, else
    /// nil (nothing is sent, the request is exactly what it always was). So a stale choice can never leak into a client
    /// whose rule is off, and a made-up id can never reach the server.
    static func modeToSend(trackTransportMode: Bool, options: [TransportOption], chosen: String?) -> String? {
        if isActive(trackTransportMode: trackTransportMode, options: options) {
            return choice(picked: chosen, options: options)
        }
        return nil
    }

    /// The text for a mode id: the offered choice's label, else the server's own label for the record, else a readable
    /// id; nil for no mode.
    static func labelFor(id: String?, options: [TransportOption], serverLabel: String? = nil) -> String? {
        guard let mode = clean(id) else { return nil }
        if let o = options.first(where: { $0.id == mode }) {
            let l = o.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !l.isEmpty { return l }
        }
        if let s = clean(serverLabel) { return s }
        return prettify(mode)
    }

    // MARK: the pre-selection on the post-checkout travel prompt

    /// The vehicle to pre-select on "Add today's travel to expenses?": `modeId` when it is one of the policy's vehicles
    /// (`policyVehicleIds` = ids of its `vehicle_rates`), otherwise nil. `public_transport` and `other` never
    /// pre-select anything (even if a policy happened to list a vehicle with such an id), and neither does an id the
    /// policy does not know.
    static func preselectVehicle(modeId: String?, policyVehicleIds: [String]) -> String? {
        guard let id = clean(modeId) else { return nil }
        if id == publicTransport || id == other { return nil }
        return policyVehicleIds.contains(id) ? id : nil
    }

    // MARK: Home: today's mode as a chip with "Change"

    /// What Home shows. `action` = the button next to it ("Change", or "Set" when no mode is recorded yet), nil when
    /// the mode cannot be changed right now (`note` then says why).
    struct Chip: Equatable {
        var text: String
        var action: String?
        var note: String?
    }

    /// The chip for today's `record`, or nil when the question is not `active` or the rep has not checked in. A
    /// check-in that is still waiting in the offline queue (the stand-in record) shows the chosen mode but offers no
    /// change: the server has no attendance row to change yet.
    static func chip(active: Bool, record: AttendanceRecord?, options: [TransportOption]) -> Chip? {
        guard let rec = record else { return nil }
        if !active || rec.checkinAt == nil { return nil }
        let mode: String? = validMode(rec.transportMode)
        let label: String? = labelFor(id: mode, options: options, serverLabel: rec.transportLabel)
        let text: String = label != nil ? "Travelling by \(label ?? "")" : "Travel mode not set"
        if OfflinePunchState.isStandIn(rec) {
            return Chip(text: text, action: nil, note: "You can change this once your check-in has synced.")
        }
        return Chip(text: text, action: mode != nil ? "Change" : "Set", note: nil)
    }

    /// Why today's mode cannot be changed right now, or nil when it can: no connection (the change is online only, it
    /// is never queued), no check-in yet, or a check-in the server does not have yet.
    static func cannotChange(online: Bool, record: AttendanceRecord?) -> String? {
        if !online { return "You're offline. Connect to the internet to change your travel mode." }
        if record?.checkinAt == nil { return "Check in first, then you can say how you're travelling." }
        if OfflinePunchState.isStandIn(record) {
            return "Your check-in hasn't reached the server yet. You can change your travel mode once it has synced."
        }
        return nil
    }

    /// What the rep is told when the change failed: a connection problem (`retryable`: no connection, 408 / 429 / 5xx)
    /// says so, a refusal (an HTTP status with the server's own `message`) shows that reason, and anything else (no
    /// status at all: an unreadable reply or a bug) is a plain "couldn't change", never a technical message.
    static func changeFailure(httpStatus: Int?, message: String?, retryable: Bool) -> String {
        if retryable {
            return "Couldn't reach the server, so your travel mode wasn't changed. Check your connection and try again."
        }
        if (httpStatus ?? 0) == 0 { return "Couldn't change your travel mode." }
        if let m = clean(message) { return m }
        return "Couldn't change your travel mode."
    }

    // MARK: self-heal

    /// Self-heal after a check-in: did the server lose the mode we SENT? True when `modeSent` is a mode the server
    /// would accept, and the record the server handed back (`returned`) is a real check-in (not the offline stand-in)
    /// that holds no mode at all. Then the app quietly sets it once with `PATCH /attendance/transport-mode`. A record
    /// that already has a mode (even a different one) is never overwritten, and nothing is repaired when no mode was
    /// sent (the rule is off). `expectedDate` (`yyyy-MM-dd`), when given, must be the record's own day, so a record of
    /// another day is left alone.
    static func needsRepair(modeSent: String?, returned: AttendanceRecord?, expectedDate: String? = nil) -> Bool {
        guard let sent = clean(modeSent), isValidId(sent) else { return false }
        guard let rec = returned else { return false }
        if rec.checkinAt == nil || OfflinePunchState.isStandIn(rec) { return false }
        if clean(rec.transportMode) != nil { return false }
        if let expected = expectedDate {
            if OfflinePunchState.isoDateOf(rec.date) != expected { return false }
        }
        return true
    }

    /// The `?date=` for the change: nil for a record of today (IST), which is the server's default, else the record's
    /// own day (a shift that started on an earlier day).
    static func changeDate(record: AttendanceRecord?, now: Date) -> String? {
        OfflinePunch.dateQuery(attendanceDate: OfflinePunchState.isoDateOf(record?.date), now: now)
    }

    /// `record` after a successful change to `mode`: everything the app already knew is kept (late info, times ...), the
    /// mode is the server's answer when it echoed one, and the label is the server's only when it belongs to that same
    /// mode. Nil when there is no record to update.
    static func applyChange(record: AttendanceRecord?, mode: String, serverRow: AttendanceRecord?) -> AttendanceRecord? {
        guard var rec = record else { return nil }
        let echoed: String? = validMode(serverRow?.transportMode)
        let newMode: String = echoed ?? mode
        var label: String? = nil
        if echoed != nil { label = clean(serverRow?.transportLabel) }
        rec.transportMode = newMode
        rec.transportLabel = label
        return rec
    }

    // MARK: helpers

    /// `value` trimmed; nil when blank.
    private static func clean(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    /// A record's mode when it is an id the server would accept.
    private static func validMode(_ value: String?) -> String? {
        guard let v = clean(value), isValidId(v) else { return nil }
        return v
    }
}

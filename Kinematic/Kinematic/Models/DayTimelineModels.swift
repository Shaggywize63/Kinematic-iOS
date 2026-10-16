//
//  DayTimelineModels.swift
//  Kinematic
//
//  The Timeline screen's data (module `timeline`): one person's day, read from
//    GET /api/v1/attendance/daily-report?date=&user_id=      → DayTimelineParser.dailyReport
//    GET /api/v1/attendance/daily-report/team?date=          → DayTimelineParser.teamReport
//  — the same report the web dashboard's Daily Travel Report shows.
//
//  Read forgivingly, like AttendanceRulesParser: the `{ success, data }` envelope or the bare payload, numbers sent as
//  strings (Postgres numerics), one unreadable row skipped instead of failing the list. Nothing here throws.
//  (Named `Day…` because SwiftUI already owns `TimelineView`.)
//

import Foundation

/// A point on a stretch of travel. `kind`: checkin | form_checkout (from) · form_checkin | checkout | now (to).
struct DayPoint: Equatable {
    var kind: String?
    var label: String?
    var at: Date?
}

struct DayLeg: Equatable {
    var index: Int
    var km: Double
    /// gps_trail | straight_line | none — how the distance was measured.
    var method: String?
    var from: DayPoint?
    var to: DayPoint?
}

struct DayVisit: Equatable {
    var id: String
    var label: String
    var arrival: Date?
    var departure: Date?
    var minutes: Int
    var lat: Double?
    var lng: Double?
}

struct DayHalt: Equatable {
    var index: Int
    var start: Date?
    var end: Date?
    var minutes: Int
    var points: Int
    var lat: Double?
    var lng: Double?
}

struct DayReportData: Equatable {
    /// `YYYY-MM-DD` (India day).
    var date: String
    var userId: String?
    var name: String
    var employeeId: String?
    /// nil when the person has no attendance that day: nothing to lay out.
    var attendanceId: String?
    var checkin: Date?
    var checkout: Date?
    var totalHours: Double?
    var inProgress: Bool
    /// The mode of transport as a person would read it ("Own Bike"), or nil.
    var modeLabel: String?
    var totalKm: Double
    var legs: [DayLeg]
    var visits: [DayVisit]
    var halts: [DayHalt]
}

/// One person with a shift on the day, for a manager's team list.
struct TeamDayRow: Equatable, Identifiable {
    var userId: String
    var name: String
    var employeeId: String?
    var checkin: Date?
    var checkout: Date?
    var totalHours: Double?
    var modeLabel: String?
    var totalKm: Double
    var visits: Int
    var visitMinutes: Int
    var halts: Int
    var haltMinutes: Int

    var id: String { userId }
}

enum DayTimelineParser {
    private typealias P = AttendanceRulesParser

    /// A whole number, or nil — guarded so a huge or odd JSON number can never trap in `Int(_:)`.
    private static func intOf(_ j: AnyJSON?) -> Int? {
        guard let n = P.number(j), abs(n) < 1_000_000_000 else { return nil }
        return Int(n)
    }

    private static func date(_ j: AnyJSON?) -> Date? {
        RupeeTargets.parseTimestamp(P.text(j))
    }

    /// A map coordinate: both numbers, in range. (0, 0) is "no fix", not a place.
    static func coordinate(lat: AnyJSON?, lng: AnyJSON?) -> (Double, Double)? {
        guard let a = P.number(lat), let b = P.number(lng) else { return nil }
        if abs(a) > 90 || abs(b) > 180 { return nil }
        if a == 0 && b == 0 { return nil }
        return (a, b)
    }

    /// "own_bike" → "Own bike"; blank → nil.
    static func readableMode(_ mode: String?) -> String? {
        let words = (mode ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = words.first else { return nil }
        return String(first).uppercased() + String(words.dropFirst())
    }

    /// `data` of the envelope when it is an object, else the object itself; nil when the reply is not an object.
    private static func payload(_ root: AnyJSON?) -> [String: AnyJSON]? {
        guard let o = P.object(root) else { return nil }
        if let inner = P.object(o["data"]) { return inner }
        return o
    }

    private static func point(_ j: AnyJSON?) -> DayPoint? {
        guard let o = P.object(j) else { return nil }
        return DayPoint(kind: P.text(o["kind"]), label: P.text(o["label"]), at: date(o["at"]))
    }

    /// The day report. nil when the reply is not an object that looks like one (no shift, no summary, no lists), so an
    /// error body never reads as an empty day. A day with no attendance IS a report: `attendanceId` nil, no rows.
    static func dailyReport(from root: AnyJSON?) -> DayReportData? {
        guard let d = payload(root) else { return nil }
        let shift = P.object(d["shift"])
        let travel = P.object(d["travel"])
        let summary = P.object(d["summary"])
        let visitRows = P.array(d["visits"])
        let haltRows = P.array(d["halts"])
        if shift == nil && summary == nil && travel == nil && visitRows == nil && haltRows == nil { return nil }

        var legs: [DayLeg] = []
        for (i, el) in (P.array(travel?["legs"]) ?? []).enumerated() {
            guard let l = P.object(el) else { continue }
            legs.append(DayLeg(
                index: intOf(l["index"]) ?? i,
                km: P.number(l["km"]) ?? 0,
                method: P.text(l["method"]),
                from: point(l["from"]),
                to: point(l["to"])))
        }
        var visits: [DayVisit] = []
        for (i, el) in (visitRows ?? []).enumerated() {
            guard let v = P.object(el) else { continue }
            let c = coordinate(lat: v["lat"], lng: v["lng"])
            visits.append(DayVisit(
                id: P.text(v["submission_id"]) ?? "visit-\(i)",
                label: P.text(v["label"]) ?? "Customer visit",
                arrival: date(v["arrival_at"]),
                departure: date(v["departure_at"]),
                minutes: intOf(v["minutes"]) ?? 0,
                lat: c?.0, lng: c?.1))
        }
        var halts: [DayHalt] = []
        for (i, el) in (haltRows ?? []).enumerated() {
            guard let h = P.object(el) else { continue }
            let c = coordinate(lat: h["lat"], lng: h["lng"])
            halts.append(DayHalt(
                index: intOf(h["index"]) ?? i,
                start: date(h["start_at"]),
                end: date(h["end_at"]),
                minutes: intOf(h["minutes"]) ?? 0,
                points: intOf(h["points"]) ?? 0,
                lat: c?.0, lng: c?.1))
        }

        let transport = P.object(d["transport"])
        let user = P.object(d["user"])
        return DayReportData(
            date: P.text(d["date"]) ?? "",
            userId: P.text(user?["id"]),
            name: P.text(user?["name"]) ?? "—",
            employeeId: P.text(user?["employee_id"]),
            attendanceId: P.text(shift?["attendance_id"]),
            checkin: date(shift?["checkin_at"]),
            checkout: date(shift?["checkout_at"]),
            totalHours: P.number(shift?["total_hours"]),
            inProgress: P.bool(shift?["in_progress"]) == true,
            modeLabel: P.text(transport?["label"]) ?? readableMode(P.text(transport?["mode"])),
            totalKm: P.number(travel?["total_km"]) ?? P.number(summary?["total_km"]) ?? 0,
            legs: legs,
            visits: visits,
            halts: halts)
    }

    /// The team list: `{ date, rows: [...] }` (or a bare rows array). A row without a `user_id` is skipped. nil when the
    /// reply has no rows list at all.
    static func teamReport(from root: AnyJSON?) -> [TeamDayRow]? {
        var rows: [AnyJSON]?
        if let a = P.array(root) {
            rows = a
        } else if let d = payload(root) {
            rows = P.array(d["rows"])
        }
        guard let list = rows else { return nil }
        var out: [TeamDayRow] = []
        for el in list {
            guard let r = P.object(el), let id = P.text(r["user_id"]) else { continue }
            out.append(TeamDayRow(
                userId: id,
                name: P.text(r["name"]) ?? "—",
                employeeId: P.text(r["employee_id"]),
                checkin: date(r["checkin_at"]),
                checkout: date(r["checkout_at"]),
                totalHours: P.number(r["total_hours"]),
                modeLabel: P.text(r["label"]) ?? readableMode(P.text(r["mode"])),
                totalKm: P.number(r["total_km"]) ?? 0,
                visits: intOf(r["visits"]) ?? 0,
                visitMinutes: intOf(r["visit_minutes"]) ?? 0,
                halts: intOf(r["halts"]) ?? 0,
                haltMinutes: intOf(r["halt_minutes"]) ?? 0))
        }
        return out
    }
}

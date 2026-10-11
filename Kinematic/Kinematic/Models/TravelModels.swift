//
//  TravelModels.swift
//  Kinematic
//
//  GET /api/v1/attendance/travel?date=YYYY-MM-DD — the distance a rep travelled on one India day, worked out by the
//  server from the check-in / check-out points, the forms visited and the GPS trail between them. The reply is
//  `{ success, data }`; these are the `data`.
//
//  Every field is optional and read forgivingly (a missing key, a null, a wrong type reads as "not there"), so a partial
//  or newer reply still decodes and extra keys (halts ...) are ignored. A day with no attendance record answers 200 with
//  `attendance_id: null, total_km: 0, method: "none"`.
//

import Foundation

/// A point on a stretch of travel (check-in, a form's check-in / check-out, check-out, "now").
struct TravelPoint: Decodable, Equatable {
    /// "checkin" | "form_checkout" (from) · "form_checkin" | "checkout" | "now" (to)
    let kind: String?
    let at: String?
    let lat: Double?
    let lng: Double?
    let label: String?

    private enum CodingKeys: String, CodingKey { case kind, at, lat, lng, label }

    init(kind: String? = nil, at: String? = nil, lat: Double? = nil, lng: Double? = nil, label: String? = nil) {
        self.kind = kind
        self.at = at
        self.lat = lat
        self.lng = lng
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? nil
        lat = (try? c.decodeIfPresent(Double.self, forKey: .lat)) ?? nil
        lng = (try? c.decodeIfPresent(Double.self, forKey: .lng)) ?? nil
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil
    }
}

/// One stretch of travel between two anchors (check-in, a form's check-out / check-in, check-out).
struct TravelLeg: Decodable, Equatable {
    let index: Int?
    let km: Double?
    /// "gps_trail" | "straight_line" | "none"
    let method: String?
    let from: TravelPoint?
    let to: TravelPoint?

    private enum CodingKeys: String, CodingKey { case index, km, method, from, to }

    init(index: Int? = nil, km: Double? = nil, method: String? = nil, from: TravelPoint? = nil, to: TravelPoint? = nil) {
        self.index = index
        self.km = km
        self.method = method
        self.from = from
        self.to = to
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? nil
        km = (try? c.decodeIfPresent(Double.self, forKey: .km)) ?? nil
        method = (try? c.decodeIfPresent(String.self, forKey: .method)) ?? nil
        from = (try? c.decodeIfPresent(TravelPoint.self, forKey: .from)) ?? nil
        to = (try? c.decodeIfPresent(TravelPoint.self, forKey: .to)) ?? nil
    }
}

/// A form visit in the day (the time between its check-in and check-out is not travel).
struct TravelStop: Decodable, Equatable {
    let submissionId: String?
    let label: String?
    let checkInAt: String?
    let checkOutAt: String?
    let minutes: Int?

    private enum CodingKeys: String, CodingKey {
        case label, minutes
        case submissionId = "submission_id"
        case checkInAt = "check_in_at"
        case checkOutAt = "check_out_at"
    }

    init(submissionId: String? = nil, label: String? = nil, checkInAt: String? = nil, checkOutAt: String? = nil, minutes: Int? = nil) {
        self.submissionId = submissionId
        self.label = label
        self.checkInAt = checkInAt
        self.checkOutAt = checkOutAt
        self.minutes = minutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        submissionId = (try? c.decodeIfPresent(String.self, forKey: .submissionId)) ?? nil
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil
        checkInAt = (try? c.decodeIfPresent(String.self, forKey: .checkInAt)) ?? nil
        checkOutAt = (try? c.decodeIfPresent(String.self, forKey: .checkOutAt)) ?? nil
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? nil
    }
}

struct TravelSummary: Decodable, Equatable {
    let date: String?
    let userId: String?
    let attendanceId: String?
    let startedAt: String?
    let endedAt: String?
    /// True while the shift is still open (the figure is "so far").
    let inProgress: Bool?
    let totalKm: Double?
    /// "gps_trail" | "straight_line" | "mixed" | "none"
    let method: String?
    let legs: [TravelLeg]?
    let stops: [TravelStop]?
    let pointsUsed: Int?
    let pointsExcluded: Int?

    private enum CodingKeys: String, CodingKey {
        case date, method, legs, stops
        case userId = "user_id"
        case attendanceId = "attendance_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case inProgress = "in_progress"
        case totalKm = "total_km"
        case pointsUsed = "points_used"
        case pointsExcluded = "points_excluded"
    }

    init(date: String? = nil, userId: String? = nil, attendanceId: String? = nil, startedAt: String? = nil,
         endedAt: String? = nil, inProgress: Bool? = nil, totalKm: Double? = nil, method: String? = nil,
         legs: [TravelLeg]? = nil, stops: [TravelStop]? = nil, pointsUsed: Int? = nil, pointsExcluded: Int? = nil) {
        self.date = date
        self.userId = userId
        self.attendanceId = attendanceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.inProgress = inProgress
        self.totalKm = totalKm
        self.method = method
        self.legs = legs
        self.stops = stops
        self.pointsUsed = pointsUsed
        self.pointsExcluded = pointsExcluded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? nil
        attendanceId = (try? c.decodeIfPresent(String.self, forKey: .attendanceId)) ?? nil
        startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? nil
        endedAt = (try? c.decodeIfPresent(String.self, forKey: .endedAt)) ?? nil
        inProgress = (try? c.decodeIfPresent(Bool.self, forKey: .inProgress)) ?? nil
        totalKm = (try? c.decodeIfPresent(Double.self, forKey: .totalKm)) ?? nil
        method = (try? c.decodeIfPresent(String.self, forKey: .method)) ?? nil
        legs = (try? c.decodeIfPresent([TravelLeg].self, forKey: .legs)) ?? nil
        stops = (try? c.decodeIfPresent([TravelStop].self, forKey: .stops)) ?? nil
        pointsUsed = (try? c.decodeIfPresent(Int.self, forKey: .pointsUsed)) ?? nil
        pointsExcluded = (try? c.decodeIfPresent(Int.self, forKey: .pointsExcluded)) ?? nil
    }

    /// The legs (empty when the reply had none, or `null`).
    var legList: [TravelLeg] { legs ?? [] }
    /// The visits (empty when the reply had none, or `null`).
    var stopList: [TravelStop] { stops ?? [] }
    var legCount: Int { legList.count }
}

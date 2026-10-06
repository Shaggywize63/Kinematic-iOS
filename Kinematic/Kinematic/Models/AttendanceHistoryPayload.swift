//
//  AttendanceHistoryPayload.swift
//  Kinematic
//
//  The `data` of GET /attendance/history.
//
//  The server has delivered this in more than one shape, and the app must read
//  all of them:
//    • a flat array                                  [ {…}, {…} ]
//    • the nested paginated shape                    { "data": [ … ], "pagination": { … } }
//    • both, plus the keys Android declares          { "items": [ … ], "total": …, "page": …,
//                                                      "data": [ … ], "pagination": { … } }
//  The app used to decode only a flat array, so against either object shape the
//  decode threw, `getAttendanceHistory` swallowed it and returned [] — the
//  history screen was always empty however many days had been worked.
//

import Foundation

struct AttendanceHistoryPayload: Codable {
    let records: [AttendanceRecord]

    private enum CodingKeys: String, CodingKey {
        case items, data
    }

    init(records: [AttendanceRecord]) {
        self.records = records
    }

    init(from decoder: Decoder) throws {
        // 1. A flat array.
        if let array = try? [AttendanceRecord](from: decoder) {
            records = array
            return
        }
        // 2. An object: `items` (what Android decodes), else `data` (the nested shape).
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try? container.decode([AttendanceRecord].self, forKey: .items) {
            records = items
        } else if let data = try? container.decode([AttendanceRecord].self, forKey: .data) {
            records = data
        } else {
            records = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .items)
    }
}

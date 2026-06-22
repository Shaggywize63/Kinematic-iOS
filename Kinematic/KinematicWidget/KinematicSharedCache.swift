//
//  KinematicSharedCache.swift
//  KinematicWidget (shared)
//
//  Read/write the widget's cached snapshot through the
//  group.com.shaggywize63.kinematic App Group so the host app and the
//  widget extension see the same data.
//
//  In the main Kinematic target, after every successful CRM refresh,
//  the app should call `KinematicSharedCache.write(...)` to push the
//  latest counts and then `WidgetCenter.shared.reloadAllTimelines()`
//  so the widget repaints immediately (otherwise iOS only refreshes
//  it on the timeline policy every 30 minutes).
//
//  ⚠️ Both targets must enable the App Group "group.com.shaggywize63.kinematic"
//  in Signing & Capabilities (Xcode).
//

import Foundation
import WidgetKit

public enum KinematicSharedCache {
    static let appGroup = "group.com.shaggywize63.kinematic"
    static let key = "kinematic_widget_summary_v1"

    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// Persist the latest snapshot. Safe to call from any thread.
    public static func write(
        totalLeads: Int,
        totalConversions: Int,
        conversionRate: Double,
        leadsToday: Int,
        leadsWeek: Int,
        trend7d: [Int],
        openDeals: Int = 0,
        wonDeals30d: Int = 0,
        openDealValue: Double = 0,
        refreshedAt: Date = Date()
    ) {
        let payload: [String: Any] = [
            "total_leads": totalLeads,
            "total_conversions": totalConversions,
            "conversion_rate": conversionRate,
            "leads_today": leadsToday,
            "leads_week": leadsWeek,
            "trend_7d": trend7d,
            "open_deals": openDeals,
            "won_deals_30d": wonDeals30d,
            "open_deal_value": openDealValue,
            "refreshed_at": refreshedAt.timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            store?.set(data, forKey: key)
        }
        // Reload widgets so users see the new numbers immediately.
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Read the cached snapshot. Returns `nil` when nothing has been
    /// written yet — the timeline provider falls back to a placeholder.
    public static func read() -> KinematicEntry? {
        guard let data = store?.data(forKey: key),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let trend = (raw["trend_7d"] as? [Int]) ?? []
        let refreshedTs = raw["refreshed_at"] as? TimeInterval
        return KinematicEntry(
            date: Date(),
            totalLeads:       (raw["total_leads"]       as? Int)    ?? 0,
            totalConversions: (raw["total_conversions"] as? Int)    ?? 0,
            conversionRate:   (raw["conversion_rate"]   as? Double) ?? 0,
            leadsToday:       (raw["leads_today"]       as? Int)    ?? 0,
            leadsWeek:        (raw["leads_week"]        as? Int)    ?? 0,
            trend7d:          trend.isEmpty ? Array(repeating: 0, count: 7) : trend,
            openDeals:        (raw["open_deals"]        as? Int)    ?? 0,
            wonDeals30d:      (raw["won_deals_30d"]     as? Int)    ?? 0,
            openDealValue:    (raw["open_deal_value"]   as? Double) ?? 0,
            refreshedAt:      refreshedTs.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

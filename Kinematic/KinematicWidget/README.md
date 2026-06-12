# Kinematic Widget

WidgetKit extension for the Kinematic iOS app. Three sizes
(`systemSmall`, `systemMedium`, `systemLarge`) showing Total Leads,
Total Conversions, conversion rate, and a 7-day trend sparkline.

## One-time Xcode setup

1. **Add a new target** — File → New → Target → **Widget Extension**.
   Name it `KinematicWidget`. Uncheck "Include Configuration Intent"
   (this widget uses `StaticConfiguration`).
2. **Replace the auto-generated sources** with the four files in this
   folder:
   - `KinematicWidgetBundle.swift`
   - `KinematicWidget.swift`
   - `KinematicSharedCache.swift`
   - `Info.plist`
3. **Add the same files to the main Kinematic target's compile
   list for `KinematicSharedCache.swift`** so the app can write the
   cache. (Or move the cache file into a shared "WidgetSharedKit"
   framework — for the v1 ship, sharing the single file via target
   membership is fine.)
4. **App Group** — in *Signing & Capabilities* for both targets, add
   the App Group `group.com.shaggywize63.kinematic`. The cache lives
   in this group's `UserDefaults`.

## Wiring the host app

In the main Kinematic target, after every successful CRM analytics
refresh, call:

```swift
KinematicSharedCache.write(
    totalLeads: summary.totalLeads,
    totalConversions: summary.totalConversions,
    conversionRate: summary.conversionRate,
    leadsToday: summary.leadsToday,
    leadsWeek: summary.leadsWeek,
    trend7d: summary.trend7d
)
```

`KinematicSharedCache.write` also calls
`WidgetCenter.shared.reloadAllTimelines()` so installed widgets
repaint immediately.

A background-fetch / `BGTaskScheduler` job can poll
`GET /api/v1/crm/analytics/widget-summary` and write the cache when
the app isn't open. iOS will not call the widget's timeline provider
more than every ~30 minutes, so the timeline provider itself reads
the cache rather than making the network call from the extension.

## Brand visuals

- Brand-red → deep-navy diagonal gradient (`BrandGradient` view)
- Rounded heavy numerals for big counts
- White semi-transparent sparkline with rounded stroke + end-cap dot
- "KINEMATIC" tracked label top-left, "Updated Xm ago" top-right

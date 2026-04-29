# iOS — Live Tracking & Outlet API Patch Notes

This branch (`claude/unify-apps-live-tracking-9j97F`) adds two new files
under `Kinematic/Kinematic/Services/`:

- `LiveTrackingDeviceInfo.swift` — `DeviceInfoSnapshot`, `UserStatusUpdate`,
  `currentBatteryPercentage()`. Mirrors the Android `UserStatusUpdate`
  payload so the dashboard's Live Tracking page receives the same
  `device_model / device_brand / os_version / battery_percentage` columns
  on every heartbeat regardless of platform.
- `OutletCache.swift` — `OutletCache.shared`, a 30-second in-memory TTL
  cache. Mirrors the Android OkHttp HTTP cache shipped on the same branch.

Two follow-up edits in `Kinematic/Kinematic/KinematicApp.swift` activate
these helpers. They are listed here as exact, copy-pasteable diffs so we
do not have to hand-overwrite the 62 KB single-file source — every other
function in `KinematicApp.swift` is left untouched.

---

## 1. Replace `sendLiveTrackingPing` with the unified `/users/status` call

Find the existing `sendLiveTrackingPing(lat:lng:battery:)` inside the
`KinematicRepository` class and replace it with the version below.

```swift
    func sendLiveTrackingPing(lat: Double, lng: Double, battery: Int) async -> Bool {
        // Unified with Android: post HEARTBEAT to /users/status so the
        // dashboard sees device_model/brand/os_version + battery_percentage.
        do {
            let payload = UserStatusUpdate.heartbeat(lat: lat, lng: lng, battery: battery)
            let body = try? JSONEncoder().encode(payload)
            let res: ApiResponse<[String: String]>? = try await performRequest(
                "/users/status",
                method: "PATCH",
                body: body
            )
            return res?.success ?? false
        } catch {
            print("❌ HEARTBEAT_ERROR: \(error)")
            return false
        }
    }
```

This swap:

- Posts to `PATCH /api/v1/users/status` (same as Android), so the existing
  `updateUserStatus` controller writes `users.battery_percentage`,
  `users.device_model/brand`, `users.os_version`, and inserts a
  `work_activity` HEARTBEAT row.
- Removes the legacy `/attendance/pings` endpoint entirely from the iOS
  flow, so the dashboard does not need a second source-of-truth.

---

## 2. Wrap the four hot outlet calls with `OutletCache`

Find `getMobileHome()`, `fetchMyRoutePlan()`, and any sibling outlet/store
fetches inside `KinematicRepository`, and prefix each with the cache
check below. Example for `getMobileHome`:

```swift
    func getMobileHome() async -> MobileHomeResponse? {
        if let cached = OutletCache.shared.get(MobileHomeResponse.self,
                                               key: .mobileHome) {
            return cached
        }
        do {
            let res: ApiResponse<MobileHomeResponse>? = try await performRequest("/analytics/mobile-home")
            if let home = res?.data {
                OutletCache.shared.put(home, key: .mobileHome)
                cache(home, forKey: cachedMobileHomeKey)
                if let routes = home.routePlan, !routes.isEmpty {
                    OutletCache.shared.put(routes, key: .routePlan)
                    cache(routes, forKey: cachedRoutePlanKey)
                }
                return home
            }
            return loadCached(MobileHomeResponse.self, forKey: cachedMobileHomeKey)
        } catch {
            return loadCached(MobileHomeResponse.self, forKey: cachedMobileHomeKey)
        }
    }
```

Apply the same `OutletCache.shared.get(...) ?? fetch + put` pattern to:

- `fetchMyRoutePlan()` → `key: .routePlan`
- any helper that hits `/api/v1/stores` → `key: .stores`
- any helper that hits `/api/v1/management/executives` → `key: .executives`

After a successful `logVisit` / route-plan update, call
`OutletCache.shared.invalidate(.mobileHome)` and `.routePlan` so the next
fetch sees fresh data.

On logout, call `OutletCache.shared.invalidateAll()`.

---

## 3. Heartbeat hookup (already aligned)

`AttendanceViewModel.toggleAttendance` and the existing
`LocationTrackingService` callback paths already pass the battery level
into `markAttendance`. Update the location-update callback chain to
schedule a `sendLiveTrackingPing(lat:lng:battery:)` every 60 seconds
(matching the Android `LocationTrackingService` heartbeat). The call now
silently includes the device fields via `UserStatusUpdate.heartbeat`.

---

## Result

After the two diffs above are applied:

- iOS and Android send identical heartbeat payloads, so the dashboard's
  Live Tracking page renders battery + device + os version for both.
- The four heaviest outlet endpoints serve from a 30 s in-memory cache,
  so the home screen "Assigned Outlets" surface appears within one frame
  on the second-and-later visit.

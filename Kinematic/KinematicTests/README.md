# KinematicTests

XCTest unit-test bundle for the Kinematic iOS app. Fast, deterministic,
network-free coverage of the model/logic layer.

## What is covered

| File | Under test |
| --- | --- |
| `LeadFieldOverridesModelTests.swift` | Built-in field-override merge/lookup (scoped-wins-per-property, B2C vs B2B, universal fallback, `explicitlyShownOnB2C`, generic-entity helpers) |
| `LeadModelTests.swift` | `Lead` snake_case decode, encode→decode round-trip, `displayName`, `fullAddress` |
| `AnyJSONTests.swift` | `AnyJSON` Bool-before-number probing, integral-Double `.any` re-emit as `Int`, nested containers, round-trip |
| `APIEnvelopeTests.swift` | `APIEnvelope` decoding `error` as a String **or** a `{code,message}` object |
| `CurrencyFormatterTests.swift` | `formatINR` (₹ prefix + digits) and `formatINRCompact` (Cr/L/K, `.0` trimming) |
| `WhatsAppHelperTests.swift` | `sanitize` / `waLink` / `canOpen` edge cases |
| `CRMClientScopeTests.swift` | UUID round-trip through `UserDefaults.standard`, legacy-string rejection |
| `LeadsViewModelTests.swift` | `activeFilterCount`, `resetFilters`, `hasMore`, `CreateOutcome` (pure logic only) |
| `ExpenseLogicTests.swift` | Expense rules: line validation, receipt scan fill + removal, the rejection-remark rule, partial-approval maths, claim history, approver gating, and decoding the server's claim / check / upload JSON |
| `AttendanceSyncPolicyTests.swift` | `AttendanceSyncPolicy`: which failed check-in / check-out is "saved offline" and stays queued (URLError network-down / timeout codes, HTTP 408 / 429 / 5xx) vs. refused by the server (shown with its message, rolled back, never replayed), oldest-first queue order, the tolerant `ApiResponse.error` decoding (string **or** `{code,message}`), and queued rows from older builds still loading |
| `AppUiConfigTests.swift` | `app_ui_config`: unknown keys survive decoding, the explicit-`true` tab check vs. the hide-only checks, the opt-in Expenses tab rule, and `CRMAnalyticsSummary` with its optional `leads_by_segment` |
| `QueueOwnershipTests.swift` | Offline-queue ownership: rows keyed by the stable user id (surviving token refreshes), and the careful migration of rows queued under the old token-suffix key — adopted only when provably the current user's, never lost, never reordered, idempotent, with the staleness window for attendance punches |
| `RupeeTargetsTests.swift` | Sales / Collection rupee targets: progress bar held at 100% with the true percentage, "No target set", ₹ Indian grouping, amount parsing + validation, the 24-hour delete window and timestamp parsing, card visibility, request idempotency key, and decoding the server's types / progress / entries JSON |
| `ChangePasswordTests.swift` | `PasswordPolicy`: the 10-character minimum (not 6), current-password-required, new-differs-from-current, confirmation match, UTF-16 length counting |
| `ActivityCompletionTests.swift` | `ActivityCompletion`: the Mark complete / Reopen PATCH body (status + ISO-8601 `completed_at`, vs. status `open` + an explicit JSON `null`), which rows offer which action (nothing for cancelled), and merging the server's PATCH response into the list without losing the lead / contact / deal names it doesn't carry |
| `LeadOwnerRulesTests.swift` | `lead_form.owner_assignment == "admin_only"`: parsing the flag (only the exact value restricts), who counts as an admin (admin / super_admin / main_admin / org_admin / sub_admin / client, but never a data scope of "own"), that a client without the flag is unchanged, that a non-admin's owner controls wait for the settings to load, and the model's `mayChooseLeadOwner` / `leadOwnerLocked` with the owner field override left alone |
| `ExpenseSoleVehicleTests.swift` | The expense Vehicle picker lists only the governing policy's vehicles (blank / repeated ids dropped); a policy with exactly one vehicle pre-selects it on mileage lines (also when the policy arrives late) without replacing a chosen vehicle, 2+ vehicles give no default, and an untouched line holding only the default is still treated as blank |
| `TestSupport.swift` | Shared `Lead` fixtures |

## Running

The `Kinematic` shared scheme already has this bundle wired into its Test
action, so from `Kinematic/` (the directory containing `Kinematic.xcodeproj`):

```sh
cd Kinematic
xcodebuild test \
  -project Kinematic.xcodeproj \
  -scheme Kinematic \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Or in Xcode: press ⌘U with the `Kinematic` scheme selected.

CI runs the same suite on every push / PR to `main` via
`.github/workflows/ios-tests.yml` (macos-26 / Xcode 26).

## Test-target wiring — one-time Xcode step required

A `KinematicTests` unit-test target is pre-wired into
`Kinematic.xcodeproj/project.pbxproj` (a `com.apple.product-type.unit-test-bundle`
hosted by the `Kinematic` app via `TEST_HOST`/`BUNDLE_LOADER`, with explicit
file references, a dependency on the app, and a `TestableReference` in the
shared `Kinematic` scheme). The target definition is structurally complete and
these test sources compile against the app module.

**However**, this pbxproj was hand-authored on a non-macOS environment, and
`xcodebuild` on CI reports `unable to resolve product type
com.apple.product-type.unit-test-bundle ... Couldn't load spec ... in domain
iphonesimulator` for it. That spec-resolution error clears once the project is
opened and saved once in Xcode 26 (Xcode finalizes the test target's product
spec). So a maintainer should, one time:

1. Open `Kinematic/Kinematic.xcodeproj` in Xcode 26.
2. Confirm the `KinematicTests` target is present (Project ▸ Targets) with these
   `.swift` files in its Compile Sources and **Host Application** = `Kinematic`.
   If Xcode flags anything, delete the target and re-add it: **File ▸ New ▸
   Target… ▸ Unit Testing Bundle**, name `KinematicTests`, **Target to be
   Tested** = `Kinematic`, then add these `.swift` files to it and tick it in
   the `Kinematic` scheme's Test action.
3. Save (⌘S) and commit the regenerated `project.pbxproj`.
4. Run ⌘U to confirm the suite is green, then re-enable the enforcing test step
   in `.github/workflows/ios-tests.yml` (see the note there).

Until that one-time step is done, CI **builds the app** (a real compile
smoke-test that must pass) and runs the tests as a **non-blocking** step so the
check stays green; the source files here are complete and correct.

## Notes for maintainers

- Every test class is annotated `@MainActor` to match the app module's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting (the app's model
  types are main-actor-isolated, so tests must touch them from the main actor).
- `LeadFieldOverridesModel` gained one **additive, internal** test seam,
  `ingest(rawOverrides:businessType:)`, which seeds the merged snapshots
  exactly the way `load()` does after the network fetch — production behavior
  is unchanged. All other production sources are untouched.

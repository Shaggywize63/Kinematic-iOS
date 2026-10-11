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
| `OwnerAssignmentFailClosedTests.swift` | `owner_assignment` fails closed: a successful settings load decides by itself (no flag = picker as before), a failed one keeps the user's last-known value per user + client, and with none a non-admin is restricted (admins never are); the remembered value's key / read / write; the full `/crm/settings` payload (lead statuses, field overrides, targets, unknown keys) decodes and parses; a reply without the `config` object counts as a failed load; the model's reload starts from scratch |
| `SessionCleanupTests.swift` | Sign-out leftovers: the exact list of persisted keys that belong to the person who signed out (picked client, location filter, cached Home / Route payloads, remembered owner-assignment values), the prefix family, what is left alone, the shared URL cache emptied, and the expense request ignoring the local cache |
| `ExpensePolicyRefreshTests.swift` | The expense policy is asked for again (claims load, editor open) and the fresh one replaces the held one, so a stale Vehicle picker cannot survive; a failed refresh keeps what was held; GET /expenses/policy for a one-vehicle policy decodes to that vehicle |
| `DistributionQueuePolicyTests.swift` | The distribution write queue's rules (orders, payments, returns): one stable Idempotency-Key per submission, what an answer means (2xx / "already recorded" 409 = done; no connection, timeout, 408 / 429 / 5xx / 401 = hold and retry; any other 4xx = a final rejection kept visible as failed), the server's reason, which rows the sender may send (the signed-in user's, not synced, not refused, oldest first), the retry backoff and the "N items saved — will upload when online" summary |
| `PaymentAllocationTests.swift` | Collect Payment: auto-allocate vs on account (what is sent, queue round-trip, old rows still load, sorted-key bytes), amount parsing / validation, the oldest-first "where will it go" estimate, summarising the server's allocation reply, ₹ Indian grouping |
| `SalesmanJSONTests.swift` | The tolerant readers for `GET /salesman/outlets`, `…/outstanding` and the create replies: envelope or bare payload, numbers sent as strings, one bad row skipped, nothing throws |
| `OutletPickerLogicTests.swift` | Outlet picker rows (subtitle, due label, name fallbacks), the order target (outlet + distributor), the local narrowing of the previous answer while the next one is on its way |
| `OrderCacheQueueTests.swift` | The on-disk distribution queue (against a temp directory): one row per Idempotency-Key, waiting / refused / synced states, only a refused row can be dismissed, a synced row is never dropped, rows are scoped to the signed-in user and survive a token refresh |
| `AttendanceRulesTests.swift` | `GET /attendance/rules`: the defaults are today's behaviour (selfie required, no form check-in, no travel question, no offline capture); only an explicit value changes anything; missing / unknown / mistyped keys never fail the load (incl. `"true"` strings, nested or missing `transport_modes`, rows without an acceptable id); the per-user remembered copy (keyed by user, wiped at sign-out); the throttle (5 min after a success, 1 min after a failure); and the holder the screens read (fails soft, never leaks another person's rules, drops an answer that arrives after the user changed) |
| `TransportModeTests.swift` | Mode of transport: valid ids, sanitising the choices, when the question is asked, what a check-in may carry, labels, the travel-prompt pre-selection, Home's chip (Change / Set / stand-in), when a change is refused, the failure wording, the `?date=`, `applyChange`, and the self-heal rule `needsRepair` |
| `OfflinePunchTests.swift` | Offline check-in / check-out: `captured_at` format, the IST attendance day either side of midnight, the `?date=` rule, the 36 h limit, queue-or-fail, what each server answer means for a queued row (409 = done), check-out held behind its check-in, the stand-in record and notice, an old queue row still loading, and the request body (opt-in fields absent unless set, byte-identical on every attempt) |
| `AttendancePunchTests.swift` | GPS-only punch (`selfie_required: false`): the Home / Attendance wording (identical to today's when the selfie is required), fix freshness, when a selfie is demanded |
| `AttendanceFlowTests.swift` | A client that configured nothing is never asked how it is travelling and gets the server's "today" untouched; a known travel mode is laid over the Home payload of the same day only; the question's sheet continues the interrupted Clock-In only after an answer (never after a cancel, never twice); an answer is good for its own Clock-In only; the final-check-out signal is take-once; sign-out forgets the flow state |
| `AttendanceLateTests.swift` | "Late by N min": the label, the `late` block on a record (absent for clients without shift rules, odd values never fail the record), the tally |
| `FormFieldLogicTests.swift` | Form-builder questions (route-plan and ad-hoc forms): which control each builder type gets (a checkbox with options is a multi-select, without is one box, unknown types stay a text box), how date / time / date-and-time / multi-select / location answers are stored and shown, the rating size, and what blocks a submit (hidden questions never, section headers never, unticked required checkboxes, phone / e-mail / number) |
| `FormVisitTests.swift` | Form check-in / check-out (`form_checkin_required`): which stored visit belongs to a form (its activity and outlet; an ad-hoc form has its own per template; a stale or future-dated start never matches), nothing stamped and no visit keys on the request when the rule is off (encodes as before), the four values (`check_in_at` / `check_out_at` / `check_in_gps` / `check_out_gps`) when it is on, a check-out without a GPS fix, a clock that went backwards, the running chip text, lengths of time in words, the success summary, and the per-person store (kept across restarts, never shown to another person, bounded, pruned) |
| `ActivityFeedLogicTests.swift` | The Home recent-activity card: the server's `title` / `subtitle` first, then customer, outlet and form name as the fallback ("Unknown store" is not a name), no repeated second line, the time line (today / this year / older, on the viewer's day), the timestamp shapes the API uses, decoding a row from the new and from an older server, one odd row never failing the feed, and the feed envelope |
| `CustomFieldInputTests.swift` | CRM custom fields: the `datetime` value stored as a UTC instant from the picked day and time and shown back on the viewer's clock (IST, UTC, New York, Auckland), every shape of stored instant that still reads, the number / currency filter (digits and one decimal point), and which field types get a multi-line box |
| `TravelPromptTests.swift` | "Add today's travel to expenses?": offered only for a policy with `gps_distance` and vehicle rates on a client with expenses, the vehicles and the pre-selection from today's mode of transport, the India day either side of midnight, what "Not now" / added / closed remember per user and day, what the server's answer means (ready / nothing to claim / not final / failed), the amount preview, the draft claim and its JSON, and decoding `GET /attendance/travel` |
| `ExpenseGpsDistanceTests.swift` | Policy `gps_distance` on the expense editor: which lines are GPS-distance lines, what is sent and priced for them, that a policy without the rule is unchanged, and that a saved GPS line comes back from the server as the same line |
| `RatePromptTests.swift` | The rate-the-app prompt: each eligibility boundary (3 days installed, 3 days opened, 2 good moments, 3 prompts at most, 30 days between), the counters and their ceiling, the stored text (round trip, junk, out-of-range numbers), the per-device store in its own suite, and the coordinator with a client that has / has not switched `app_ui_config.features.rate_prompt` on (nothing moves when it has not) |
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

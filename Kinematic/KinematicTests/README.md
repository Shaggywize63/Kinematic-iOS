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

## Test-target wiring (done)

The `KinematicTests` unit-test target **is** wired into
`Kinematic.xcodeproj/project.pbxproj` (a `com.apple.product-type.unit-test-bundle`
target hosted by the `Kinematic` app via `TEST_HOST`/`BUNDLE_LOADER`, with a
dependency on the app and a file-system-synchronized group so every `.swift`
file dropped in this folder is compiled automatically — the same
`objectVersion = 77` mechanism the app target uses). No manual Xcode step is
required; opening the project picks the target up.

If the project is ever regenerated and the target is lost, re-add it in Xcode:
**File ▸ New ▸ Target… ▸ Unit Testing Bundle**, name it `KinematicTests`, set
**Target to be Tested** = `Kinematic`, then drag these `.swift` files into the
new target and tick it in the Test action of the `Kinematic` scheme.

## Notes for maintainers

- Every test class is annotated `@MainActor` to match the app module's
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting (the app's model
  types are main-actor-isolated, so tests must touch them from the main actor).
- `LeadFieldOverridesModel` gained one **additive, internal** test seam,
  `ingest(rawOverrides:businessType:)`, which seeds the merged snapshots
  exactly the way `load()` does after the network fetch — production behavior
  is unchanged. All other production sources are untouched.

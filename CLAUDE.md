# Kinematic iOS App — Agent Guide

SwiftUI CRM client that talks to the Express/Supabase backend
(repo: `Kinematic`) at `https://api.kinematicapp.com`. CRM-only build
for Tata Tiscon and the parent Kinematic tenant.

## Built-in field overrides — the contract

Every render site for a built-in lead / contact / deal / account
field (those persisted as columns on the row, not as custom-field
jsonb) MUST be gated through `LeadFieldOverridesModel.isHidden(key,
isB2C:)`. There is no exception. If a new field is added to a form,
it ships gated on day one.

- Resolver: `Kinematic/Kinematic/Views/CRM/Components/
  LeadFieldOverridesModel.swift` — `@StateObject` it on every form
  that touches built-in fields; `.task { await fieldOverrides.load()
  }`; gate every row.
- Forms must:
  1. Defer rendering admin-gated rows until `fieldOverrides.didLoad`
     is true. Otherwise the form races `/api/v1/crm/settings` and
     briefly shows fields the admin had hidden.
  2. Wrap every built-in row in
     `if !fieldOverrides.isHidden("key", isB2C:)`.
  3. Route the label through
     `fieldOverrides.labelFor("key", defaultLabel:, isB2C:)` so
     admins can relabel without code.

Why this matters: hiding city / state / country / DOB / gender on
the web Settings page must immediately drop them from the iOS lead
forms. We have repeatedly had bugs where one render site was missed
(LocationPicker on Create, B2B company/title on Create, Status /
Source / Owner on Edit, B2C profile card on Detail). PRs that add
a field without the gate WILL be reverted.

## Build / check
- Xcode 26 / iOS 26 toolchain. CI builds via fastlane.

## Release — version bumps
- NEVER hand-edit `MARKETING_VERSION` in the Xcode project. Doing so
  repeatedly broke TestFlight uploads: a version that wasn't higher than
  the last approved one ("pre-release train closed") and app/widget
  version drift ("the embedded extension must contain the same version
  as the host app").
- Use **`./bump_version.sh`** at the repo root:
  - `./bump_version.sh current` — print the app marketing version.
  - `./bump_version.sh patch|minor|major` — bump it across the app +
    `KinematicWidget` **in lockstep** (the test target stays at 1.0).
  - `./bump_version.sh set X.Y.Z` — set an explicit version (warns if not
    higher than the current one).
  - `./bump_version.sh check` — verify app + widget share one version and
    one build number; the **Version lockstep** CI workflow runs this on
    every PR, so drift fails the PR instead of the archive.
- The build number (`CFBundleVersion` / `CURRENT_PROJECT_VERSION`) is
  `bump_build.sh`'s job (derived from the git commit count).

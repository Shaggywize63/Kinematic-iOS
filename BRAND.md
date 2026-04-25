# Kinematic Brand Identity — iOS

> Brand Identity Guidelines · v1.0 · 2026

This app implements the Kinematic visual system. Source of truth lives at `brand.kinematic.app`; this file documents the iOS bindings.

## Where things live

| Concern        | Location                                                              |
|----------------|-----------------------------------------------------------------------|
| Color tokens   | `Kinematic/Kinematic/Assets.xcassets/{BrandRed,BrandInk,DeepNavy,Stone,RuleGrey,SuccessGreen,CautionAmber,InformationBlue}.colorset` |
| Accent color   | `Kinematic/Kinematic/Assets.xcassets/AccentColor.colorset` (Kinematic Red `#D01E2C`) |
| Design tokens  | `Kinematic/Kinematic/DesignSystem/Brand.swift`                        |

## Color palette

### Primary
- **Kinematic Red** `#D01E2C` — CTAs, the mark, never body text. Pantone 186 C.
- **Kinematic Ink** `#0A0E1A` — Type, the mark, high-contrast UI. Pantone Black 6 C.
- **Paper White** `#FFFFFF` — Default light surface.

### Secondary
- **Deep Navy** `#0E1A2E` — Dark-mode product surface, hero panels. Pantone 5395 C.
- **Stone** `#FAFAFB` — Off-white cards, alternating rows.
- **Rule Grey** `#E4E6EB` — Borders, dividers, low-emphasis strokes.

### Functional (product UI only)
- **Success Green** `#0A8A4E` — Confirmations, ECC achievements.
- **Caution Amber** `#C97A00` — Warnings, pending, breach alerts.
- **Information Blue** `#0066FF` — Info messages, links inside product UI.

**60-30-10 rule**: 60% white/stone, 30% ink, 10% red. Red is a spice, not a sauce.

## Typography

| Role                | Family            | Notes                                                       |
|---------------------|-------------------|-------------------------------------------------------------|
| Display, headlines  | Manrope           | ExtraBold for hero & wordmark. Never for body.              |
| Body, interface     | Inter             | Default body 14–16 pt. Never bold body — use Medium (500).  |
| Data, code, eyebrow | JetBrains Mono    | ALL CAPS labels, IDs, KPI tag rails. Tracking +0.8.         |

Use `Brand.Display.*`, `Brand.Body.*`, `Brand.Mono.*` from `Brand.swift`. The eyebrow modifier is exposed as `.brandEyebrow()` on any `View`.

When brand fonts are unavailable, SwiftUI falls back through the spec’s system fallback chain (Manrope → Segoe UI / Helvetica Neue / Roboto / Arial; Inter → system; JetBrains Mono → SF Mono / Menlo).

## Logo

The Kinematic mark is a kinematic chain: one red disc anchored, two black satellite discs in coordinated orbit. It always pairs with the Manrope ExtraBold wordmark. Five approved variants only — Primary, Reverse, Mono Black, Mono White, Knockout.

**Clearspace** = diameter of one satellite disc. Never violate.

## Voice

Direct. Operational. Quietly confident. Numbers do the boasting. Avoid: *empower, leverage, world-class, best-in-breed, revolutionary, synergistic*. Use: *field executive* (never *manpower*), *team*, *check in*, *effective contact*, *beat / route*, *supervisor*. Notification copy is short, respectful, action-clear.

## Approval

- Logo, color, type questions — design@kinematic.app
- Co-branding, customer logos — marketing@kinematic.app

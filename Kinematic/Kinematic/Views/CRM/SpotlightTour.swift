import SwiftUI
import Combine

// MARK: - Spotlight tour
//
// A step-by-step coach-mark overlay that dims the whole screen and cuts a
// highlight around one real on-screen element at a time, with a tooltip that
// explains it. Mirrors the Android SpotlightTour.
//
// How it works:
//  - Target views tag themselves with `.spotlightAnchor("key")`, which
//    publishes their frame as an Anchor<CGRect> via a preference.
//  - The host screen (LeadsListView) attaches `.overlayPreferenceValue`,
//    resolves the current step's anchor to a CGRect, and renders
//    `SpotlightOverlay` above everything.
//
// iOS note: the system TabView tab bar and nav-bar toolbar items can't be
// reliably anchored, so this tour highlights the in-content controls — the
// search field, the "+" FAB and a lead row. Dim + a sharp cutout keeps the
// highlighted control crisp (a true background-only blur would blur the
// cutout too).

// MARK: Model

struct SpotlightStep: Identifiable {
    let id = UUID()
    /// Anchor id to highlight, or nil for a full-dim step with a centred tooltip.
    let key: String?
    let title: String
    let detail: String
}

extension SpotlightStep {
    /// Lead Management — the first shipped spotlight.
    static let leadManagement: [SpotlightStep] = [
        .init(key: nil,
              title: "Welcome to Lead Management",
              detail: "A quick tour of the Leads screen — it takes under a minute. Tap Next, or Skip anytime."),
        .init(key: SpotlightKeys.leadsSearch,
              title: "Find & filter",
              detail: "Search a lead by name or phone, and use Filters to narrow by status, source or owner."),
        .init(key: SpotlightKeys.leadsAdd,
              title: "Add a lead",
              detail: "Tap + to add a new lead in seconds — just a name and a mobile number to start."),
        .init(key: SpotlightKeys.leadsRow,
              title: "Open a lead",
              detail: "Tap any lead to open its profile — call, WhatsApp and log a visit right from there."),
        .init(key: nil,
              title: "You're all set!",
              detail: "When a lead is ready, open it and convert it into a deal. Replay this anytime from More → Guided Tour."),
    ]
}

enum SpotlightKeys {
    static let leadsSearch = "leads_search"
    static let leadsAdd = "leads_add"
    static let leadsRow = "leads_row"
}

/// Shared, observable tour state. Owned by CRMTabView, injected via the
/// environment so the Leads screen (anchors + overlay) and the guided-tour
/// hub (replay) can all reach it.
final class SpotlightModel: ObservableObject {
    @Published private(set) var steps: [SpotlightStep] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var active: Bool = false
    /// Flipped by the guided-tour hub to ask the shell to (re)launch the tour.
    @Published var replayRequested: Bool = false

    var current: SpotlightStep? { steps.indices.contains(index) ? steps[index] : nil }
    var isLast: Bool { index >= steps.count - 1 }

    func start(_ newSteps: [SpotlightStep]) {
        guard !newSteps.isEmpty else { return }
        steps = newSteps
        index = 0
        active = true
    }

    func next() { if isLast { stop() } else { index += 1 } }
    func back() { if index > 0 { index -= 1 } }
    func stop() { active = false; index = 0 }
}

// MARK: Anchors

struct SpotlightAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Tag this view as a spotlight target.
    func spotlightAnchor(_ key: String) -> some View {
        anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) { [key: $0] }
    }

    /// Tag this view as a spotlight target only when `condition` is true — used
    /// so only the first row of a list publishes the row anchor.
    @ViewBuilder func spotlightAnchor(_ key: String, if condition: Bool) -> some View {
        if condition { self.spotlightAnchor(key) } else { self }
    }

    /// Cut a hole in `self` shaped like `mask` (inverse mask).
    fileprivate func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        )
    }
}

// MARK: Overlay

struct SpotlightOverlay: View {
    @ObservedObject var model: SpotlightModel
    let step: SpotlightStep
    /// Target frame in the overlay's coordinate space, or nil for a full-dim step.
    let rect: CGRect?
    let containerSize: CGSize

    private let pad: CGFloat = 10
    private let corner: CGFloat = 14

    private var hole: CGRect? { rect?.insetBy(dx: -pad, dy: -pad) }
    private var tooltipAtTop: Bool { (hole?.midY ?? 0) > containerSize.height * 0.55 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dim + cutout. The reverse-mask punches the hole; the whole layer
            // still catches taps so the underlying screen can't be operated.
            Color.black.opacity(0.86)
                .reverseMask {
                    if let h = hole {
                        RoundedRectangle(cornerRadius: corner)
                            .frame(width: h.width, height: h.height)
                            .position(x: h.midX, y: h.midY)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { /* absorb */ }

            // Brand ring around the cutout.
            if let h = hole {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(Brand.red, lineWidth: 2)
                    .frame(width: h.width, height: h.height)
                    .position(x: h.midX, y: h.midY)
            }

            // Top strip: step counter + Skip.
            HStack {
                Text("Step \(model.index + 1) of \(model.steps.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button("Skip") { model.stop() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Tooltip, pinned opposite the highlighted element.
            VStack(spacing: 0) {
                if tooltipAtTop {
                    tooltipCard.padding(.top, 52)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    tooltipCard.padding(.bottom, 26)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title).font(.title3.bold())
            Text(step.detail).font(.body).foregroundStyle(.secondary)
            HStack {
                if model.index > 0 {
                    Button { model.back() } label: {
                        Text("Back").font(.headline)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                    }
                }
                Spacer()
                Button { model.next() } label: {
                    Text(model.isLast ? "Done" : "Next").font(.headline)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Brand.red, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: Environment plumbing
//
// LeadsListView is also reachable from CRMHomeView / CRMDashboardView, which
// don't own a tour. So the model is an OPTIONAL environment VALUE (defaulting
// to nil) rather than a required @EnvironmentObject — no crash where it's
// absent, and the overlay simply doesn't render there.

private struct SpotlightModelKey: EnvironmentKey {
    static let defaultValue: SpotlightModel? = nil
}

extension EnvironmentValues {
    var spotlightModel: SpotlightModel? {
        get { self[SpotlightModelKey.self] }
        set { self[SpotlightModelKey.self] = newValue }
    }
}

// MARK: Host attachment

/// Observes the model (so the overlay appears/updates as the tour runs) and
/// resolves the current step's anchor to a rect. Kept as its own view so the
/// @ObservedObject lives here — the host screen can hold the model as a plain
/// optional environment value without observing it.
private struct SpotlightHostView: View {
    @ObservedObject var model: SpotlightModel
    let anchors: [String: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if model.active, let step = model.current {
                let rect: CGRect? = step.key
                    .flatMap { anchors[$0] }
                    .map { proxy[$0] }
                SpotlightOverlay(
                    model: model,
                    step: step,
                    rect: rect,
                    containerSize: proxy.size
                )
            }
        }
    }
}

extension View {
    /// Host the spotlight overlay above this view. No-op when `model` is nil.
    @ViewBuilder func spotlightHost(_ model: SpotlightModel?) -> some View {
        if let model {
            overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
                SpotlightHostView(model: model, anchors: anchors)
            }
        } else {
            self
        }
    }
}

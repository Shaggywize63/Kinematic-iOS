import SwiftUI

// MARK: - Model
//
// A guided tour is a simple, ordered list of steps shown as a full-screen,
// step-by-step carousel. Kept deliberately self-contained (no anchoring to
// live views) so it's easy to maintain and identical across iOS + Android.
// Add more tours (Deals, Attendance, …) by extending `GuidedTour.all`.

/// One step: an SF Symbol, a short title, and one line of guidance.
struct GuidedTourStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

/// A named, ordered set of steps.
struct GuidedTour: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let steps: [GuidedTourStep]
}

extension GuidedTour {
    /// Lead Management — capture → track → convert. The first shipped tour.
    static let leadManagement = GuidedTour(
        id: "lead_management",
        title: "Lead Management",
        subtitle: "Capture, track and convert leads",
        icon: "person.crop.circle.badge.plus",
        steps: [
            .init(icon: "hand.wave.fill",
                  title: "Welcome to Lead Management",
                  detail: "A quick tour of how to capture, track and convert your leads. It takes under a minute — you can skip anytime."),
            .init(icon: "plus.circle.fill",
                  title: "Add a new lead",
                  detail: "Tap the + button on the Leads tab to add a lead in seconds. Just a name and mobile number — it even works on low signal."),
            .init(icon: "magnifyingglass",
                  title: "Find any lead",
                  detail: "Use search to find a lead by name or phone, and filters to narrow by status, source or owner."),
            .init(icon: "person.text.rectangle.fill",
                  title: "Open a lead",
                  detail: "Tap any lead to see its full profile — contact details, status, source and all custom fields."),
            .init(icon: "phone.fill",
                  title: "Call or WhatsApp",
                  detail: "Reach out in one tap — call or send a WhatsApp straight from the lead, without copying numbers."),
            .init(icon: "checkmark.square.fill",
                  title: "Log a visit or call",
                  detail: "Record a site visit, call or meeting with notes and a photo, so every touchpoint stays on the lead."),
            .init(icon: "flag.fill",
                  title: "Move it forward",
                  detail: "Update a lead's status as it progresses, and reassign the owner whenever you need to."),
            .init(icon: "arrow.right.circle.fill",
                  title: "Convert to a deal",
                  detail: "When a lead is ready, convert it into a deal to start tracking the opportunity and its value."),
            .init(icon: "checkmark.seal.fill",
                  title: "You're all set!",
                  detail: "That's Lead Management. Replay this tour anytime from More → Guided Tour."),
        ]
    )

    /// Deals — track an opportunity from first conversation to closed-won.
    static let deals = GuidedTour(
        id: "deals",
        title: "Deals",
        subtitle: "Track opportunities to closed-won",
        icon: "indianrupeesign.circle.fill",
        steps: [
            .init(icon: "hand.wave.fill",
                  title: "Welcome to Deals",
                  detail: "Track every opportunity from first conversation to closed. It takes under a minute — you can skip anytime."),
            .init(icon: "plus.circle.fill",
                  title: "Create a deal",
                  detail: "Add a deal from the Deals tab, or convert a qualified lead. Give it a name, a value and a pipeline."),
            .init(icon: "arrow.triangle.branch",
                  title: "Pipelines & stages",
                  detail: "Every deal lives in a pipeline and moves through its stages. Switch pipelines to see the right stages for that flow."),
            .init(icon: "rectangle.split.3x1.fill",
                  title: "Work the Kanban",
                  detail: "Open the Kanban board from More → Pipeline to drag deals between stages and see your whole pipeline at a glance."),
            .init(icon: "briefcase.fill",
                  title: "Open a deal",
                  detail: "Tap any deal to see its value, stage, the linked lead or contact, and the products attached to it."),
            .init(icon: "shippingbox.fill",
                  title: "Products & value",
                  detail: "Add products to a deal; the value rolls up automatically so the amount always reflects what's inside."),
            .init(icon: "checkmark.square.fill",
                  title: "Log activity",
                  detail: "Record calls, visits and meetings on the deal so the whole timeline stays in one place."),
            .init(icon: "trophy.fill",
                  title: "Close the deal",
                  detail: "Mark a deal Won with its closed amount, or Lost. A partial win can spin off a balance deal for the remainder."),
            .init(icon: "checkmark.seal.fill",
                  title: "You're all set!",
                  detail: "That's Deals. Replay this tour anytime from More → Guided Tour."),
        ]
    )

    /// Every tour listed in the re-launch hub. Add new tours here.
    static let all: [GuidedTour] = [.leadManagement, .deals]
}

// MARK: - Tour player (full-screen, step-by-step)

struct GuidedTourView: View {
    let tour: GuidedTour
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var index = 0

    private var isLast: Bool { index >= tour.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — step count + Skip
            HStack {
                Text("Step \(index + 1) of \(tour.steps.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { onFinish() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Paged steps
            TabView(selection: $index) {
                ForEach(Array(tour.steps.enumerated()), id: \.offset) { i, step in
                    stepCard(step).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: index)

            // Progress dots
            HStack(spacing: 8) {
                ForEach(tour.steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Brand.red : Color.secondary.opacity(0.25))
                        .frame(width: i == index ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3), value: index)
                }
            }
            .padding(.bottom, 20)

            // Controls
            HStack(spacing: 12) {
                if index > 0 {
                    Button { withAnimation { index -= 1 } } label: {
                        Text("Back")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.primary)
                    }
                }
                Button {
                    if isLast { onFinish() } else { withAnimation { index += 1 } }
                } label: {
                    Text(isLast ? "Get Started" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Brand.red, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background((scheme == .dark ? Brand.ink : Brand.paper).ignoresSafeArea())
    }

    private func stepCard(_ step: GuidedTourStep) -> some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(Brand.red.opacity(0.14)).frame(width: 132, height: 132)
                Image(systemName: step.icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Brand.red)
            }
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Re-launch hub (More → Guided Tour)

struct GuidedToursListView: View {
    @State private var active: GuidedTour?
    @Environment(\.spotlightModel) private var spotlight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    // Relaunch the interactive spotlight on the real Leads
                    // screen. The tour runs on the shell, so flip the replay
                    // signal and dismiss back to it.
                    spotlight?.replayRequested = true
                    dismiss()
                } label: {
                    hubRow(icon: "scope", title: "Guided walkthrough",
                           subtitle: "Highlights each button on the Leads screen",
                           trailing: "play.circle.fill")
                }
                NavigationLink {
                    ScreenOverviewView()
                } label: {
                    hubRow(icon: "map", title: "Screen overview",
                           subtitle: "What every button does")
                }
            }
            Section {
                ForEach(GuidedTour.all) { tour in
                    Button { active = tour } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Brand.red.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: tour.icon).foregroundStyle(Brand.red)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tour.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(tour.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill").foregroundStyle(Brand.red)
                        }
                    }
                }
            } header: {
                Text("Take a tour")
            } footer: {
                Text("Step-by-step walkthroughs of the app. More tours coming soon.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Guided Tour")
        .fullScreenCover(item: $active) { tour in
            GuidedTourView(tour: tour) { active = nil }
        }
    }

    private func hubRow(icon: String, title: String, subtitle: String, trailing: String? = nil) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Brand.red.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: icon).foregroundStyle(Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let trailing { Image(systemName: trailing).foregroundStyle(Brand.red) }
        }
    }
}

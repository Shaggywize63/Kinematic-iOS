import SwiftUI
import Combine

// MARK: - View model

/// What the "My targets" card shows — owned by the screen that hosts the card, which loads it on appear and on
/// pull-to-refresh (the card itself can be absent, and an absent view runs no tasks).
///
/// Opt-in by data: `types` stays empty — and so the card never appears — for a client that configured no
/// rupee targets, and when the very first load fails. A later failure keeps what was last shown.
@MainActor
final class MyTargetsViewModel: ObservableObject {
    @Published private(set) var types: [RupeeTargetType] = []
    @Published private(set) var progress: RupeeTargetProgress?
    /// "Sale logged" / "Collection logged", shown on the card for a few seconds.
    @Published private(set) var confirmation: String?

    private var confirmationTask: Task<Void, Never>?

    var rows: [RupeeTargets.CardRow] { RupeeTargets.cardRows(types: types, progress: progress) }
    var monthTitle: String? { RupeeTargets.monthTitle(periodStart: progress?.periodStart) }

    /// Fetch the configured types, then the month's progress.
    func load() async {
        do {
            let fetched = try await CRMService.shared.rupeeTargetTypes()
            if Task.isCancelled { return }
            types = fetched
        } catch {
            return     // keep whatever was shown; a client never seen with targets stays without
        }
        if types.isEmpty { progress = nil; return }
        if let p = try? await CRMService.shared.rupeeTargetProgress(), !Task.isCancelled { progress = p }
    }

    /// Same, but only where the home screen has not been told to hide the card (`home.my_targets == false`).
    func loadIfEnabled() async {
        guard ClientFeatures.homeVisible("my_targets") else { return }
        await load()
    }

    /// An entry was saved: confirm it and bring the figures up to date.
    func didLog(_ type: RupeeTargetType) async {
        showConfirmation(RupeeTargets.confirmation(forKey: type.key, label: type.label))
        await load()
    }

    private func showConfirmation(_ text: String) {
        confirmation = text
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.confirmation = nil }
        }
    }
}

// MARK: - Card

/// "My targets": this month's sales / collection against target, with a button to log each. Shown on the
/// field-force Home and the CRM Home. Tap it (or "History") for the month's entries.
struct MyTargetsCard: View {
    @ObservedObject var model: MyTargetsViewModel
    var title: String = "My targets"
    /// Side margin, applied to the card itself (not to the host's view of it) so that a client without targets —
    /// where this view is empty — gets no stray gap on its home screen.
    var horizontalPadding: CGFloat = 0

    @State private var logging: RupeeTargetType?
    @State private var showHistory = false

    var body: some View {
        // Shown only for a client with rupee targets configured, and not where the home screen hides it.
        if RupeeTargets.cardVisible(types: model.types, homeVisible: ClientFeatures.homeVisible("my_targets")) {
            card
                .sheet(item: $logging) { type in
                    LogTargetEntrySheet(type: type) { logged in
                        Task { await model.didLog(logged) }
                    }
                }
                .sheet(isPresented: $showHistory) {
                    NavigationStack {
                        TargetsHistoryView(types: model.types,
                                           periodStart: model.progress?.periodStart,
                                           periodEnd: model.progress?.periodEnd,
                                           monthTitle: model.monthTitle) {
                            Task { await model.load() }
                        }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } }
                        }
                    }
                }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).tracking(1)
                Spacer()
                Button { showHistory = true } label: {
                    HStack(spacing: 3) {
                        Text("History").font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(Brand.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Targets history")
            }

            // Tapping the figures opens the history; the buttons below act on their own.
            VStack(alignment: .leading, spacing: 14) {
                if let month = model.monthTitle {
                    Text(month).font(.subheadline.weight(.semibold))
                }
                ForEach(model.rows) { row in rowView(row) }
            }
            .contentShape(Rectangle())
            .onTapGesture { showHistory = true }

            if let c = model.confirmation {
                Label(c, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundColor(Brand.success)
                    .transition(.opacity)
            }

            HStack(spacing: 10) {
                ForEach(model.types) { type in
                    Button { logging = type } label: {
                        Text(RupeeTargets.logButtonTitle(key: type.key, label: type.label))
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .animation(.easeInOut(duration: 0.2), value: model.confirmation)
        .padding(.horizontal, horizontalPadding)
    }

    private func rowView(_ row: RupeeTargets.CardRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(.system(size: 15, weight: .bold))
                Spacer()
                Text(row.trailingText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(row.isComplete ? Brand.success : (row.percent == nil ? .secondary : Color(uiColor: .label)))
            }
            if row.showsBar {
                // The bar stops at 100%; the percentage beside it is the true one.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(height: 8)
                        Capsule().fill(row.isComplete ? Brand.success : Brand.red)
                            .frame(width: max(geo.size.width * row.barFraction, row.barFraction > 0 ? 8 : 0), height: 8)
                    }
                }
                .frame(height: 8)
            }
            Text(row.detailText).font(.caption).foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

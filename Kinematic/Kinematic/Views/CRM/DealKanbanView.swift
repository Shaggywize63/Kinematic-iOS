import SwiftUI
import UIKit

/// True horizontal Kanban for deals. Each pipeline stage gets its own
/// fixed-width column that scrolls vertically, and the whole row of
/// columns scrolls horizontally — matching what the web dashboard
/// renders. Long-press a card to move it to another stage (haptic +
/// confirmation dialog); tap to push DealDetailView.
struct DealKanbanView: View {
    @StateObject var vm = DealKanbanViewModel()
    @State private var movingDeal: Deal?
    @State private var creatingDeal = false
    @State private var moveSuccessTick = 0
    @AppStorage("crm.deals.showWeighted") private var showWeightedStored: Bool = false
    /// Tata Tiscon is the only client that gets the weighted-by-tonne
    /// toggle. Every other client always sees raw amount, regardless of
    /// what's persisted in @AppStorage (which might be true from a
    /// previous Tata-enabled session on the same device).
    private var showWeighted: Bool {
        get { ClientFeatures.isTataTiscon ? showWeightedStored : false }
    }
    private var showWeightedBinding: Binding<Bool> {
        Binding(get: { showWeightedStored }, set: { showWeightedStored = $0 })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                // First-load shell: show a single ProgressView until pipelines
                // resolve so the rep doesn't see a half-rendered, no-data UI
                // that looks frozen during the 3-call fan-out.
                if vm.pipelines.isEmpty && vm.isLoading {
                    loadingShell
                } else if vm.stages.isEmpty {
                    emptyShell
                } else {
                    loadedBody
                }
            }
            // FAB sits above the bottom safe area so it never collides
            // with the iOS 26 minimized tab bar.
            floatingNewDealButton
        }
        .navigationTitle("Pipeline")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                pipelineMenu
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
        // Haptic on every successful stage move — `moveSuccessTick` is
        // bumped by the move handler after the VM round-trip resolves.
        .sensoryFeedback(.success, trigger: moveSuccessTick)
        .confirmationDialog(
            movingDeal.map { "Move \"\($0.name)\" to…" } ?? "Move deal to stage",
            isPresented: Binding(
                get: { movingDeal != nil },
                set: { if !$0 { movingDeal = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(vm.stages.filter { $0.id != movingDeal?.stageId }) { stage in
                Button(stage.name) {
                    if let deal = movingDeal {
                        Task {
                            await vm.move(deal: deal, toStage: stage.id)
                            moveSuccessTick &+= 1
                        }
                    }
                    movingDeal = nil
                }
            }
            Button("Cancel", role: .cancel) { movingDeal = nil }
        }
        .sheet(isPresented: $creatingDeal) {
            DealCreateView { body in
                _ = try? await CRMService.shared.createDeal(body)
                await vm.load()
            }
        }
    }

    // MARK: - Shells

    private var loadingShell: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(Brand.red).scaleEffect(1.3)
            Text("Loading pipeline…")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyShell: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No stages in this pipeline yet")
                .font(.headline)
            Text("Add stages on the web dashboard to start tracking deals here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded board

    private var loadedBody: some View {
        VStack(spacing: 0) {
            // Sub-header: current pipeline name + Cost/Weighted toggle.
            // Keeps the toolbar Menu clean (just for switching).
            headerBar
            // Horizontal board — each column is its own vertical stack.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(vm.stages) { stage in
                        kanbanColumn(for: stage)
                    }
                    // Trailing breathing room so the last column isn't
                    // glued to the screen edge.
                    Spacer().frame(width: 4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 96) // clearance for the FAB
            }
            .refreshable { await vm.load() }
        }
    }

    private var headerBar: some View {
        let activePipeline = vm.pipelines.first(where: { $0.id == vm.selectedPipelineId })
        return VStack(spacing: 6) {
            HStack {
                if let p = activePipeline {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(Brand.red)
                            .font(.system(size: 12))
                        Text(p.name)
                            .font(.system(size: 14, weight: .bold))
                        if p.isDefault == true {
                            Text("DEFAULT")
                                .font(.system(size: 8, weight: .black))
                                .tracking(0.6)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Brand.red.opacity(0.15))
                                .foregroundColor(Brand.red)
                                .cornerRadius(3)
                        }
                    }
                }
                Spacer()
                Text(boardSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            // Cost / weighted-view toggle was built for Tata Tiscon's
            // tonnage-driven pipeline. Hidden for every other client until
            // it's generalised or moved behind a tenant setting — the
            // showWeighted state still exists so power users can turn it
            // back on per device, but the UI is Tata-only.
            if ClientFeatures.isTataTiscon {
                HStack(spacing: 8) {
                    Image(systemName: showWeighted ? "scalemass.fill" : "indianrupeesign.circle.fill")
                        .foregroundColor(Brand.red)
                        .font(.caption)
                    Text(showWeighted
                         ? "Weighted (amount × win prob)"
                         : "Raw amount")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: showWeightedBinding)
                        .labelsHidden()
                        .tint(Brand.red)
                        .scaleEffect(0.85)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    /// Toolbar pipeline switcher. Hides itself when only one pipeline
    /// exists since there's nothing to choose. Mirrors the web behaviour.
    @ViewBuilder
    private var pipelineMenu: some View {
        if vm.pipelines.count > 1 {
            Menu {
                ForEach(vm.pipelines) { p in
                    Button {
                        vm.selectedPipelineId = p.id
                        Task { await vm.load() }
                    } label: {
                        if p.id == vm.selectedPipelineId {
                            Label(p.name, systemImage: "checkmark")
                        } else {
                            Text(p.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.stack")
                    .foregroundColor(Brand.red)
            }
        }
    }

    // MARK: - Column

    @ViewBuilder
    private func kanbanColumn(for stage: Stage) -> some View {
        let deals = vm.dealsFor(stageId: stage.id)
        let total = showWeighted
            ? vm.weightedTotal(stageId: stage.id)
            : vm.rawTotal(stageId: stage.id)
        VStack(alignment: .leading, spacing: 0) {
            // Header: stage name + count chip + total.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stageColor(stage))
                        .frame(width: 8, height: 8)
                    Text(stage.name.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.6)
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(1)
                    Spacer()
                    Text("\(deals.count)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(stageColor(stage).opacity(0.18)))
                        .foregroundColor(stageColor(stage))
                }
                HStack(spacing: 4) {
                    Image(systemName: "indianrupeesign.circle.fill")
                        .foregroundColor(Brand.red)
                        .font(.system(size: 10))
                    Text(CurrencyFormatter.formatINRCompact(total))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    if showWeighted {
                        Text("weighted")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(stageColor(stage).opacity(0.10))
            )

            // Card stack — lazy so a long column doesn't pre-build every
            // card up-front.
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if deals.isEmpty {
                        emptyColumnHint
                    } else {
                        ForEach(deals) { deal in
                            kanbanCard(deal)
                        }
                    }
                    Spacer().frame(height: 12)
                }
                .padding(.top, 10)
            }
            .frame(maxHeight: .infinity)
        }
        // Column width adapts to the device: ~82% of the screen on a small
        // phone (so the next column peeks), capped at 300pt on larger screens.
        .frame(width: min(300, UIScreen.main.bounds.width * 0.82))
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    /// Empty-state hint inside a column so reps know they can drop deals
    /// here (long-press → move).
    private var emptyColumnHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 22))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No deals")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// One deal card inside a column. Tap navigates; long-press opens the
    /// move-to-stage confirmation dialog.
    private func kanbanCard(_ deal: Deal) -> some View {
        NavigationLink(destination: DealDetailView(dealId: deal.id, initialDeal: deal)) {
            DealCard(deal: deal)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Text(deal.name)
            Divider()
            Button {
                movingDeal = deal
            } label: {
                Label("Move to another stage", systemImage: "arrow.left.arrow.right")
            }
        } preview: {
            DealCard(deal: deal)
                .padding(12)
                .frame(width: 260)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            movingDeal = deal
        }
    }

    // MARK: - FAB

    private var floatingNewDealButton: some View {
        Button {
            creatingDeal = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("New Deal")
                    .font(.system(size: 14, weight: .black))
                    .tracking(0.3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(
                Capsule().fill(Brand.red)
                    .shadow(color: Brand.red.opacity(0.35), radius: 10, x: 0, y: 4)
            )
        }
        .padding(.trailing, 18)
        .padding(.bottom, 22)
        .sensoryFeedback(.impact(weight: .medium), trigger: creatingDeal)
    }

    // MARK: - Helpers

    private var boardSummary: String {
        let totalDeals = vm.deals.count
        let total = vm.stages.reduce(0.0) { acc, s in
            acc + (showWeighted ? vm.weightedTotal(stageId: s.id) : vm.rawTotal(stageId: s.id))
        }
        return "\(totalDeals) deals · \(CurrencyFormatter.formatINRCompact(total))"
    }

    /// Map a stage to a tint colour. Honour the persisted `color` hex
    /// when set, otherwise fall back to a deterministic palette so the
    /// columns are visually distinct.
    private func stageColor(_ stage: Stage) -> Color {
        if let hex = stage.color, let c = Color.fromHex(hex) {
            return c
        }
        let palette: [Color] = [.blue, .purple, .teal, .indigo, .orange, .pink, Brand.red, .green]
        let idx = abs(stage.id.hashValue) % palette.count
        return palette[idx]
    }
}

// MARK: - Color hex parser

private extension Color {
    /// Tolerant `#rrggbb` / `rrggbb` parser used by stages that ship a
    /// brand colour from the web settings panel.
    static func fromHex(_ raw: String) -> Color? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let v = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

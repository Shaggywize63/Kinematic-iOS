import SwiftUI

/// Help & Lifecycle — the end-to-end map of how a record moves through the
/// CRM. Shown on the "More" surface so any new rep can answer "how does
/// this all fit together?" without a training session. Content mirrors
/// the same screen on Android + dashboard.
struct CRMHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                stagesSection
                actionsSection
                aiSection
                reportsSection
                tipsSection
                contactSection
            }
            .padding(20)
        }
        .navigationTitle("Help & Lifecycle")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Brand.red.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "books.vertical.fill").foregroundColor(Brand.red)
                }
                Text("How Kinematic CRM works")
                    .font(.title3.bold())
            }
            Text("A Lead becomes a Contact + Account when qualified. A Deal tracks the conversation about money. Every Call, WhatsApp, or note logged along the way becomes an Activity that anyone on the team can read.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Brand.red.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.red.opacity(0.18), lineWidth: 1)))
    }

    // MARK: - Lifecycle stages

    private var stagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("The lifecycle")
            stage(
                number: 1,
                title: "Lead arrives",
                detail: "From a form, a referral, an import, or KINI's auto-capture. Status starts as NEW.",
                icon: "person.crop.circle.badge.plus"
            )
            stage(
                number: 2,
                title: "Qualify",
                detail: "Call, WhatsApp, or meet the lead. Set status → CONTACTED → QUALIFIED. AI score helps prioritise — focus on 70+.",
                icon: "checkmark.seal.fill"
            )
            stage(
                number: 3,
                title: "Convert",
                detail: "When the lead is real revenue, tap Convert. Kinematic spins up a Contact (the person), an Account (their company), and optionally a Deal in the pipeline.",
                icon: "arrow.triangle.branch"
            )
            stage(
                number: 4,
                title: "Move the deal",
                detail: "Drag stages on the pipeline. Win Probability and Next-Best-Action refresh from AI as the deal progresses.",
                icon: "square.stack.3d.up.fill"
            )
            stage(
                number: 5,
                title: "Close",
                detail: "Mark Won (with amount + close date) or Lost (with reason). Won deals add to revenue charts; lost reasons feed the win-rate report.",
                icon: "trophy.fill"
            )
        }
    }

    private func stage(number: Int, title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Brand.red).frame(width: 32, height: 32)
                Text("\(number)").font(.system(size: 14, weight: .black)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundColor(Brand.red).font(.system(size: 13, weight: .semibold))
                    Text(title).font(.system(size: 15, weight: .bold))
                }
                Text(detail).font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Day-to-day actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("What the buttons do")
            actionRow(icon: "phone.fill", color: .blue, title: "Call",
                      detail: "Dials the lead/contact and immediately logs a call activity. Cancel to keep the bare entry, save to add notes + duration.")
            actionRow(icon: "message.fill", color: .green, title: "WhatsApp",
                      detail: "Opens a pre-filled WhatsApp thread. The conversation is captured by KINI Auto-Response if enabled.")
            actionRow(icon: "sparkles", color: .purple, title: "AI Score",
                      detail: "Re-runs the KINI AI scoring model on the lead. The badge changes — green means high intent.")
            actionRow(icon: "arrow.triangle.branch", color: .red, title: "Convert",
                      detail: "Promotes the lead to Contact + Account + Deal. You'll be asked for a deal name, amount, and product so the new Deal lands on the pipeline ready to move.")
            actionRow(icon: "person.badge.plus", color: .orange, title: "Assign",
                      detail: "Hands the lead to another rep on the same team. Only same-client teammates are shown.")
            actionRow(icon: "pause.circle.fill", color: .gray, title: "Deactivate",
                      detail: "Marks the lead as Unqualified. Hidden from active views; keeps the record for history.")
        }
    }

    private func actionRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon).foregroundColor(color).font(.system(size: 14, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - KINI AI

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("KINI AI")
            actionRow(icon: "sparkles", color: .purple, title: "Score & prioritise leads",
                      detail: "Every lead gets an AI score 0–100 and an A–D grade from its signals. Work the highest first; the 'Boost this score' card shows what's missing.")
            actionRow(icon: "wand.and.stars", color: .purple, title: "Next-Best-Action",
                      detail: "On any lead or deal, KINI recommends the single best next move (call, meet, qualify, nurture) with the reasoning behind it.")
            actionRow(icon: "envelope.badge.fill", color: .blue, title: "Draft email & WhatsApp",
                      detail: "Generate a ready-to-edit email or WhatsApp template from a short goal — in English, Hindi, Odia, Bengali or Assamese.")
            actionRow(icon: "doc.text.magnifyingglass", color: .red, title: "Summarise & ask",
                      detail: "Summarise an account or deal, or ask KINI things like 'show deals stuck over 14 days' or 'draft a follow-up for X'.")
        }
    }

    // MARK: - Reports & analytics

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Reports & analytics")
            Text("Reports → open any report as a table and download it as CSV. The dashboard shows your pipeline, win rate, avg deal, sales cycle, new leads and a live leads map — scoped to your leads and team.")
                .font(.system(size: 13)).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(["Rep Leaderboard", "Forecast", "Stage Funnel", "Win / Loss", "Lead Aging", "Stuck Leads", "Activity Heatmap", "Lead Source ROI", "Sales Cycle"], id: \.self) { r in
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.doc.horizontal.fill").foregroundColor(Brand.red).font(.system(size: 12))
                        Text(r).font(.system(size: 13)).foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Tips")
            tip("Tap the phone number on any lead → both a call AND an activity land in one gesture.")
            tip("The KINI floating button is your AI helper. Ask things like 'show me deals stuck more than 14 days' or 'draft a follow-up for X'.")
            tip("Tasks on the inbox are coloured by urgency. Red = overdue. Blue = today. Pull-to-refresh anywhere to re-sync.")
            tip("Win Probability is the AI's guess based on stage + age + recent activity. It updates when you log meaningful interactions.")
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundColor(.yellow).font(.system(size: 13))
            Text(text).font(.system(size: 13)).foregroundColor(.primary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Footer

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Need more help?")
            Text("Anything outside this guide — settings, custom fields, automations — lives on the web console. Your team admin can also walk you through it.")
                .font(.system(size: 13)).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black))
            .tracking(1)
            .foregroundColor(Brand.red)
    }
}

import SwiftUI

struct LeadDetailView: View {
    @StateObject var vm: LeadDetailViewModel

    init(leadId: String) {
        _vm = StateObject(wrappedValue: LeadDetailViewModel(leadId: leadId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lead = vm.lead {
                    headerCard(lead: lead)
                    if lead.isB2c == true {
                        b2cProfileCard(lead: lead)
                    }
                    if let score = vm.score {
                        scoreCard(score: score)
                    }
                    aiActions
                    activitiesSection
                } else if vm.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    Text("Lead not found.").foregroundColor(.gray)
                }
            }
            .padding()
        }
        .navigationTitle("Lead")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
    }

    private func headerCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lead.displayName)
                    .font(.system(size: 22, weight: .black))
                Spacer()
                if lead.isB2c == true {
                    badge("B2C", color: .purple)
                } else {
                    badge("B2B", color: .blue)
                }
                ScoreBadge(score: lead.score ?? 0)
            }
            if lead.isB2c != true, let c = lead.company {
                Text(c).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                if let e = lead.email {
                    Label(e, systemImage: "envelope.fill").font(.caption).foregroundColor(.blue)
                }
                if let p = lead.phone {
                    Label(p, systemImage: "phone.fill").font(.caption).foregroundColor(.green)
                }
            }
            if let phone = lead.phone, WhatsAppHelper.canOpen(phone: phone) {
                let prefill = "Hi \(lead.firstName ?? lead.displayName.split(separator: " ").first.map(String.init) ?? "there"), "
                WhatsAppButton(phone: phone, prefillText: prefill, compact: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private func b2cProfileCard(lead: Lead) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOMER PROFILE")
                .font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 6) {
                if let dob = lead.dateOfBirth {
                    profileRow("Date of Birth", value: dob)
                }
                if let g = lead.gender {
                    profileRow("Gender", value: g.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                if let pcm = lead.preferredContactMethod {
                    profileRow("Preferred Channel", value: pcm.capitalized)
                }
                if let addr = lead.fullAddress {
                    profileRow("Address", value: addr)
                }
                profileRow("Marketing Consent", value: (lead.marketingConsent ?? false) ? "Yes" : "No")
                profileRow("WhatsApp Consent", value: (lead.whatsappConsent ?? false) ? "Yes" : "No")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.purple.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.18), lineWidth: 1))
        )
    }

    private func profileRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
                .frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 13)).foregroundColor(.primary)
            Spacer()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private func scoreCard(score: LeadScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI SCORE").font(.system(size: 10, weight: .black)).tracking(1).foregroundColor(.purple)
            HStack {
                Text("\(Int(score.score))")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.purple)
                if let band = score.band {
                    Text(band.uppercased())
                        .font(.caption2).bold()
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
            }
            if let breakdown = score.breakdown {
                ForEach(breakdown) { b in
                    HStack {
                        Text(b.factor).font(.caption)
                        Spacer()
                        Text("+\(Int(b.points))").font(.caption).foregroundColor(.green)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.purple.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.purple.opacity(0.25), lineWidth: 1))
        )
    }

    private var aiActions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.runAIScore() }
            } label: {
                HStack {
                    if vm.aiBusy { ProgressView().tint(.white) }
                    else { Image(systemName: "sparkles") }
                    Text("AI Score")
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            Button {
                Task { await vm.convert() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                    Text("Convert")
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            Spacer()
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVITY").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(.gray)
            if vm.activities.isEmpty {
                Text("No activity logged.").font(.caption).foregroundColor(.gray)
            } else {
                ForEach(vm.activities) { a in
                    ActivityTimelineItem(activity: a)
                }
            }
        }
    }
}

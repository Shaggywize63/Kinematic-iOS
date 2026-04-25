import SwiftUI

struct BroadcastHubView: View {
    @StateObject var vm = BroadcastHubViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.isLoading && vm.broadcasts.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if vm.broadcasts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "megaphone")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.3))
                        Text("No Announcements")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 100)
                } else {
                    ForEach(vm.broadcasts) { b in
                        BroadcastItemView(broadcast: b) { selectedIndex in
                            Task {
                                await vm.submitAnswer(id: b.id, selectedIndex: selectedIndex)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Broadcast Hub")
        .onAppear {
            Task { await vm.refresh() }
        }
    }
}

struct BroadcastItemView: View {
    let broadcast: BroadcastQuestion
    let onAnswer: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(broadcast.createdAt?.prefix(10) ?? "Announced")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Spacer()
                
                if broadcast.isUrgent {
                    Text("URGENT")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
                
                if broadcast.alreadyAnswered {
                    Text("ANSWERED")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }
            
            Text(broadcast.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(uiColor: .label))
            
            if !broadcast.alreadyAnswered {
                VStack(spacing: 8) {
                    ForEach(0..<broadcast.options.count, id: \.self) { i in
                        Button(action: { onAnswer(i) }) {
                            HStack {
                                Text(broadcast.options[i].label)
                                    .font(.system(size: 14))
                                Spacer()
                                Image(systemName: "circle")
                                    .font(.system(size: 14))
                            }
                            .padding()
                            .background(Color(uiColor: .label).opacity(0.05))
                            .cornerRadius(10)
                            .foregroundColor(Color(uiColor: .label).opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding()
        .liquidGlass()
    }
}

struct LearningHubView: View {
    @StateObject var vm = LearningHubViewModel()
    @State private var selectedCategory = "All"
    @State private var selectedType = "all"
    
    let types = ["all", "video", "pdf", "image", "link"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Training Progress Card
            if vm.totalMandatoryCount > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Training Progress")
                                .font(.headline)
                                .foregroundColor(Color(uiColor: .label))
                            Text("\(vm.completedMandatoryCount) of \(vm.totalMandatoryCount) mandatory items completed")
                                .font(.caption)
                                .foregroundColor(Color(uiColor: .secondaryLabel))
                        }
                        Spacer()
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 48, height: 48)
                            Circle()
                                .trim(from: 0, to: vm.progressPercentage)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 48, height: 48)
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(vm.progressPercentage * 100))%")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    
                    ProgressView(value: vm.progressPercentage)
                        .tint(.green)
                }
                .padding()
                .background(Color.blue.opacity(0.15))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                .padding()
            }
            
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.categories, id: \.self) { cat in
                        FilterChip(title: cat, isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            
            // Type Filter (Parity with Android)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(types, id: \.self) { type in
                        Button(action: { selectedType = type }) {
                            Text(type.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedType == type ? Color.red : Color(uiColor: .label).opacity(0.05))
                                .foregroundColor(selectedType == type ? .white : .gray)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 16)
            
            // Materials List
            ScrollView {
                VStack(spacing: 16) {
                    let filtered = vm.materials.filter { 
                        (selectedCategory == "All" || $0.category == selectedCategory) &&
                        (selectedType == "all" || $0.type?.lowercased() == selectedType)
                    }
                    
                    if vm.isLoading && vm.materials.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("No resources found").foregroundColor(.gray)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(filtered) { m in
                            LearningMaterialRow(material: m)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Learning Hub")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            Task { await vm.refresh() }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.2) : Color(uiColor: .label).opacity(0.05))
                .foregroundColor(isSelected ? .blue : .gray)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
    }
}

struct LearningMaterialRow: View {
    let material: LearningMaterial
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorForType(material.type ?? "").opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: iconForType(material.type ?? ""))
                    .font(.title3)
                    .foregroundColor(colorForType(material.type ?? ""))
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(material.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(uiColor: .label))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(material.type?.uppercased() ?? "DOC")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colorForType(material.type ?? "").opacity(0.1))
                        .foregroundColor(colorForType(material.type ?? ""))
                        .cornerRadius(4)
                    
                    if material.isMandatory ?? false {
                        Text("MANDATORY")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    Text(material.category ?? "General")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if material.myProgress?.isCompleted ?? false {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 20))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func iconForType(_ type: String) -> String {
        switch type.lowercased() {
        case "video": return "play.circle.fill"
        case "pdf": return "doc.fill"
        case "image": return "photo.fill"
        case "link": return "link"
        default: return "doc.text.fill"
        }
    }
    
    private func colorForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "video": return .red
        case "pdf": return .orange
        case "image": return .blue
        case "link": return .teal
        default: return .gray
        }
    }
}

// ── NEW PROFILE VIEW (Parity with Android) ─────────────────────

struct ProfileView: View {
    @ObservedObject var appState = KiniAppState.shared
    let user = Session.currentUser
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                mainCard
                weeklySummary
                accountDetails
            }
            .padding(.top, 20)
        }
        .navigationTitle("My Profile")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
    
    private var mainCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 4))
                    .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Text(user?.name.prefix(1).uppercased() ?? "U")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 6) {
                Text(user?.name ?? "Field Executive")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(uiColor: .label))
                
                Text(user?.role.uppercased() ?? "FIELD EXECUTIVE")
                    .font(.system(size: 12, weight: .black))
                    .tracking(2)
                    .foregroundColor(.gray)
                
                Text("ACTIVE")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(20)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .padding(.horizontal)
    }
    
    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("THIS WEEK SUMMARY")
                .font(.system(size: 12, weight: .black))
                .tracking(1)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                ProfileStatCard(title: "Forms", value: "\(appState.summary?.tffCount ?? 0)", color: .red)
                ProfileStatCard(title: "TFF", value: "0", color: .green)
                ProfileStatCard(title: "Days", value: "0", color: .blue)
            }
            .padding(.horizontal)
        }
    }
    
    private var accountDetails: some View {
        VStack(alignment: .leading, spacing: 1) {
            ProfileRow(icon: "envelope.fill", label: "Email", value: user?.email ?? "Not logged")
            ProfileRow(icon: "phone.fill", label: "Mobile", value: user?.mobile ?? "NA")
            ProfileRow(icon: "building.2.fill", label: "Organization", value: user?.orgId ?? "Kinematic Global")
        }
        .background(Color.white.opacity(0.03))
        .cornerRadius(20)
        .padding(.horizontal)
    }
}

struct ProfileStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 24, weight: .black))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct ProfileRow: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.blue.opacity(0.8))
                .font(.system(size: 18))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundColor(.gray)
                Text(value).font(.system(size: 15, weight: .medium)).foregroundColor(Color(uiColor: .label))
            }
            Spacer()
        }
        .padding(16)
    }
}

// ── NEW SETTINGS VIEW (Parity with Android) ─────────────────────

struct SettingsView: View {
    @ObservedObject var appState = KiniAppState.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Appearance Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("APPEARANCE")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App Theme")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Choose how the app looks")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 10) {
                            ThemeToggleCard(title: "System", type: .system, current: appState.theme, icon: "circle.lefthalf.filled")
                            ThemeToggleCard(title: "Light", type: .light, current: appState.theme, icon: "sun.max.fill")
                            ThemeToggleCard(title: "Dark", type: .dark, current: appState.theme, icon: "moon.stars.fill")
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(24)
                    .padding(.horizontal)
                }
                
                // Account Summary
                VStack(alignment: .leading, spacing: 16) {
                    Text("ACCOUNT")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 50, height: 50)
                            .overlay(Text(Session.currentUser?.name.prefix(1) ?? "U").foregroundColor(.red).bold())
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Session.currentUser?.name ?? "User").font(.headline)
                            Text(Session.currentUser?.role ?? "Executive").font(.subheadline).foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(20)
                    .padding(.horizontal)
                }
                
                // About section
                VStack(alignment: .leading, spacing: 16) {
                    Text("ABOUT")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        AboutRow(label: "App Version", value: "1.0.8 (Stable)")
                        Divider().background(Color.white.opacity(0.1))
                        AboutRow(label: "Build Mode", value: "Production")
                    }
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(20)
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 40)
                
                // Sign Out
                Button(action: { appState.logout() }) {
                    HStack {
                        Image(systemName: "arrow.right.square")
                        Text("Sign Out")
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .padding(.top, 20)
        }
        .navigationTitle("Settings")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

struct ThemeToggleCard: View {
    let title: String
    let type: AppTheme
    let current: AppTheme
    let icon: String
    
    var isSelected: Bool { type == current }
    
    var body: some View {
        Button(action: { KiniAppState.shared.theme = type }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color.red.opacity(0.1) : Color(uiColor: .label).opacity(0.03))
            .foregroundColor(isSelected ? .red : .gray)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
    }
}

struct AboutRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(.gray)
            Spacer()
            Text(value).foregroundColor(Color(uiColor: .secondaryLabel)).bold()
        }
        .font(.system(size: 14))
        .padding(16)
    }
}

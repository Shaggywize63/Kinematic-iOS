import SwiftUI

struct FormRendererView: View {
    let questions: [FormQuestion]
    @StateObject var formState = FormResponseState()
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var network: NetworkMonitor
    @State private var showSyncToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("Retail Audit Form")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .padding(.top, 40)
                    
                    ForEach(questions.sorted(by: { $0.orderIndex < $1.orderIndex })) { question in
                        renderField(for: question)
                    }
                    
                    Button(action: {
                        Task { await performSubmission() }
                    }) {
                        HStack {
                            if !network.isConnected {
                                Image(systemName: "icloud.and.arrow.down.fill")
                            }
                            Text(network.isConnected ? "Submit Form" : "Save Offline")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.kRed, Color(hex: "B31220")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: .kRed.opacity(0.4), radius: 15, x: 0, y: 8)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal)
                }
                .padding(.bottom, 60)
            }
            
            // Subtle Offline Toast
            if showSyncToast {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .font(.subheadline.bold())
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    @ViewBuilder
    private func renderField(for question: FormQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(question.title)
                    .font(.headline)
                    .foregroundColor(.white)
                if question.isRequired {
                    Text("*")
                        .foregroundColor(.kRed)
                }
            }
            
            if let desc = question.description {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Map the API schema to native SwiftUI components
            switch question.type {
            case .text:
                GlassTextField(
                    placeholder: "Enter response",
                    text: binding(for: question.id)
                )
                
            case .number:
                GlassTextField(
                    placeholder: "Enter number",
                    text: binding(for: question.id)
                )
                .keyboardType(.decimalPad)
                
            case .boolean:
                Toggle(isOn: boolBinding(for: question.id)) {
                    Text("Select")
                        .foregroundColor(.white.opacity(0.8))
                }
                .tint(.kRed)
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)
                
            case .select:
                if let options = question.options {
                    Menu {
                        ForEach(options, id: \.self) { option in
                            Button(option) {
                                formState.stringValues[question.id] = option
                            }
                        }
                    } label: {
                        HStack {
                            Text(formState.stringValues[question.id] ?? "Select Option")
                                .foregroundColor(formState.stringValues[question.id] == nil ? .white.opacity(0.6) : .white)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(16)
                    }
                }
                
            case .camera:
                Button(action: {
                    // Trigger native camera logic/PhotosPicker
                    print("Open Camera overlay")
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Capture Photo")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .liquidGlass(cornerRadius: 16, opacity: 0.15)
                }
                
            default:
                Text("Unsupported field type")
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .padding()
        .liquidGlass(cornerRadius: 24, opacity: 0.08)
        .padding(.horizontal)
    }
    
    // Helper Bindings
    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { self.formState.stringValues[key, default: ""] },
            set: { self.formState.stringValues[key] = $0 }
        )
    }
    
    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { self.formState.boolValues[key, default: false] },
            set: { self.formState.boolValues[key] = $0 }
        )
    }
    
    private func performSubmission() async {
        // Collect all responses into a single dictionary
        var responses: [String: Any] = [:]
        for (id, val) in formState.stringValues { responses[id] = val }
        for (id, val) in formState.boolValues { responses[id] = val }
        
        let liveSuccess = await KinematicRepository.shared.submitForm(
            templateId: "default_template",
            activityId: nil,
            outletId: nil,
            outletName: "Store Name",
            latitude: 19.076,
            longitude: 72.877,
            responses: responses,
            context: modelContext
        )
        
        withAnimation {
            toastMessage = liveSuccess ? "Form Submitted Successfully!" : "Saved Offline — Syncing later"
            showSyncToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showSyncToast = false }
        }
    }
}

/// A reusable sleek input field mimicking the Liquid Glass design
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        TextField(placeholder, text: $text)
            .padding()
            .foregroundColor(.white)
            .accentColor(.kRed)
            .background(Color.black.opacity(0.2))
            .cornerRadius(16)
    }
}

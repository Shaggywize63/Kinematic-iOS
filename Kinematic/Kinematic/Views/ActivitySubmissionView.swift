import SwiftUI

struct ActivitySubmissionView: View {
    let activity: RouteActivity
    @Environment(\.dismiss) var dismiss
    @State private var template: FormTemplate? = nil
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            VibrantBackgroundView()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .padding(12).background(Color(uiColor: .label).opacity(0.05)).clipShape(Circle()).foregroundColor(Color(uiColor: .label))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.name ?? "Unknown Activity").font(.headline).foregroundColor(Color(uiColor: .label))
                        Text("Task Execution").font(.caption).foregroundColor(.gray)
                    }
                    .padding(.leading, 8)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 20)
                
                if isLoading {
                    VStack {
                        ProgressView().tint(.red)
                        Text("Loading exact form...").font(.caption).foregroundColor(.gray).padding(.top, 10)
                    }
                    .frame(maxHeight: .infinity)
                } else if let t = template {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            // Section: Form Header
                            VStack(alignment: .leading, spacing: 5) {
                                Text(t.name.uppercased()).font(.caption).fontWeight(.bold).foregroundColor(.gray).tracking(1)
                                if let desc = t.description {
                                    Text(desc).font(.subheadline).foregroundColor(Color(uiColor: .label).opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Dynamic Fields
                            VStack(spacing: 20) {
                                if let fields = t.fields {
                                    ForEach(fields) { field in
                                        DynamicFieldRow(field: field, value: Binding(
                                            get: { responses[field.id] ?? "" },
                                            set: { responses[field.id] = $0 }
                                        ))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Submit Section
                            Button(action: { submit() }) {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("SUBMIT \((activity.name ?? "").uppercased())").fontWeight(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(activity.status == "completed" ? Color.gray.opacity(0.3) : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                            .padding(.horizontal, 20)
                            .disabled(activity.status == "completed" || isSubmitting)
                            
                            Spacer().frame(height: 50)
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.orange)
                        Text("Could not load activity form.\nPlease try again later.").multilineTextAlignment(.center).foregroundColor(.gray)
                        Button("Dismiss") { dismiss() }.foregroundColor(Color(uiColor: .label)).padding().background(Color(uiColor: .label).opacity(0.05)).cornerRadius(10)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .task {
            await loadTemplate()
        }
    }
    
    private func loadTemplate() async {
        print("LOADING_TEMPLATE_FOR_ACTIVITY: \(activity.id ?? "unknown")")
        let t = await KinematicRepository.shared.getFormTemplates(activityId: activity.id ?? "")
        
        await MainActor.run {
            if t == nil { print("TEMPLATE_LOAD_FAILED_FOR: \(activity.id ?? "unknown")") }
            self.template = t
            self.isLoading = false
            // Init responses
            if let fields = t?.fields {
                for f in fields { responses[f.id] = "" }
            }
        }
    }
    
    private func submit() {
        isSubmitting = true
        Task {
            let reqResponses = responses.map { FormResponse(fieldId: $0.key, value: $0.value) }
            let request = FormSubmissionRequest(
                templateId: template?.id ?? "",
                activityId: activity.id ?? "",
                outletId: AppState.shared.selectedOutlet?.rawId,
                submittedAt: ISO8601DateFormatter().string(from: Date()),
                responses: reqResponses
            )
            
            let success = await KinematicRepository.shared.submitForm(request: request)
            await MainActor.run {
                isSubmitting = false
                if success { 
                    // Update local state for immediate feedback
                    if let index = AppState.shared.selectedOutlet?.activities?.firstIndex(where: { $0.id == activity.id }) {
                        AppState.shared.selectedOutlet?.activities?[index].status = "completed"
                    }
                    dismiss() 
                }
            }
        }
    }
}

struct DynamicFieldRow: View {
    let field: FormField
    @Binding var value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label).font(.caption).foregroundColor(.gray).fontWeight(.bold)
            
            if field.fieldType == "select" || field.fieldType == "dropdown" {
                Menu {
                    ForEach(field.options ?? [], id: \.value) { opt in
                        Button(opt.label) { value = opt.value }
                    }
                } label: {
                    HStack {
                        Text(selectedLabel).foregroundColor(value.isEmpty ? .gray : Color(uiColor: .label))
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                    }
                    .padding()
                    .liquidGlass()
                }
            } else if field.fieldType == "number" {
                TextField(field.placeholder ?? "Enter numeric value", text: $value)
                    .keyboardType(.decimalPad)
                    .padding()
                    .liquidGlass()
            } else {
                TextField(field.placeholder ?? "Enter text", text: $value)
                    .padding()
                    .liquidGlass()
            }
        }
    }
    
    private var selectedLabel: String {
        field.options?.first(where: { $0.value == value })?.label ?? field.placeholder ?? "Select option"
    }
}

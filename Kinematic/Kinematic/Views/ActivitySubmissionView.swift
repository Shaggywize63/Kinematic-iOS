import SwiftUI
import CoreLocation

struct ActivitySubmissionView: View {
    let activity: RouteActivity
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var template: FormTemplate? = nil
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var isLoading = true
    @State private var cachedImages: [String: [UIImage]] = [:]
    
    private var progress: Double {
        guard let fields = template?.fields else { return 0 }
        let requiredFields = fields.filter { $0.isRequired && $0.fieldType != "section_header" }
        if requiredFields.isEmpty { return 0.5 }
        let filledRequired = requiredFields.filter { field in
            let val = responses[field.id] ?? ""
            let hasImages = cachedImages[field.id]?.isEmpty == false
            return !val.isEmpty || hasImages
        }
        return Double(filledRequired.count) / Double(requiredFields.count)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Apple-Style Navigation Bar
                HStack {
                    Button(action: { 
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { appState.selectedActivity = nil }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Text(activity.name ?? "Audit")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Invisible spacer for centering
                    Image(systemName: "chevron.left.circle.fill").opacity(0).font(.title2)
                }
                .padding(.horizontal)
                .padding(.top, 60)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)
                
                if isLoading {
                    VStack {
                        ProgressView().tint(.red).scaleEffect(1.2)
                        Text("REFINING INTERFACE").font(.system(size: 10, weight: .bold)).foregroundColor(.gray).tracking(1).padding(.top, 10)
                    }
                    .frame(maxHeight: .infinity)
                } else if let t = template {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Page Title
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.name)
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(.primary)
                                if let desc = t.description {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            
                            // Progress Section
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("FIELD COMPLETION").font(.footnote).fontWeight(.bold).foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(progress * 100))%").font(.footnote).fontWeight(.bold).foregroundColor(.red)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.gray.opacity(0.1)).frame(height: 4)
                                        Capsule().fill(Color.red)
                                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                    }
                                }
                                .frame(height: 4)
                            }
                            .padding(.horizontal, 20)
                            
                            // Dynamic Groups
                            VStack(spacing: 20) {
                                if let fields = t.fields {
                                    ForEach(fields) { field in
                                        if shouldShow(field: field) {
                                            VStack(alignment: .leading, spacing: 0) {
                                                DynamicFieldRow(field: field, value: Binding(
                                                    get: { responses[field.id] ?? "" },
                                                    set: { responses[field.id] = $0 }
                                                ), images: Binding(
                                                    get: { cachedImages[field.id] ?? [] },
                                                    set: { cachedImages[field.id] = $0 }
                                                ))
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                                            .cornerRadius(16)
                                            .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
                                            .transition(.move(edge: .bottom).combined(with: .opacity))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            Spacer().frame(height: 140)
                        }
                    }
                }
            }
            
            // Floating Apple-Style Button
            if template != nil && !isLoading {
                VStack {
                    Divider().background(Color.gray.opacity(0.1))
                    Button(action: { submit() }) {
                        Text("Finish Audit")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(activity.status == "completed" ? Color.gray : Color.red)
                            .cornerRadius(14)
                            .padding(.horizontal, 20)
                    }
                    .disabled(activity.status == "completed" || isSubmitting)
                    .padding(.vertical, 20)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .task { await loadTemplate() }
    }
    
    private func shouldShow(field: FormField) -> Bool {
        guard let depId = field.dependsOnId, !depId.isEmpty else { return true }
        let depValue = responses[depId] ?? ""
        return depValue == field.dependsOnValue
    }
    
    private func loadTemplate() async {
        let t = await KinematicRepository.shared.getFormTemplates(activityId: activity.id ?? "")
        await MainActor.run {
            self.template = t
            self.isLoading = false
            if let fields = t?.fields {
                for f in fields { responses[f.id] = "" }
            }
        }
    }
    
    private func submit() {
        isSubmitting = true
        Task {
            var finalResponses: [String: FormResponse] = [:]
            await withTaskGroup(of: (String, FormResponse).self) { group in
                for (id, val) in responses {
                    let field = template?.fields?.first(where: { $0.id == id })
                    let images = cachedImages[id] ?? []
                    group.addTask {
                        var photoValue: String? = nil
                        if !images.isEmpty && (field?.fieldType == "image" || field?.fieldType == "photo") {
                            var uploadedUrls: [String] = []
                            for img in images {
                                if let url = await KinematicRepository.shared.uploadImage(image: img, type: "activity_form") {
                                    uploadedUrls.append(url)
                                }
                            }
                            photoValue = uploadedUrls.joined(separator: ",")
                        }
                        return (id, FormResponse(fieldId: id, value: val, photo: photoValue, gps: nil))
                    }
                }
                for await (id, response) in group { finalResponses[id] = response }
            }
            
            let processedResponses = responses.map { (id, _) in
                finalResponses[id] ?? FormResponse(fieldId: id, value: responses[id], photo: nil, gps: nil)
            }
            
            let request = FormSubmissionRequest(
                templateId: template?.id,
                activityId: activity.id,
                outletId: AppState.shared.selectedOutlet?.rawId,
                outletName: AppState.shared.selectedOutlet?.storeName,
                latitude: LocationTrackingService.shared.lastLocation?.coordinate.latitude,
                longitude: LocationTrackingService.shared.lastLocation?.coordinate.longitude,
                submittedAt: ISO8601DateFormatter().string(from: Date()),
                isConverted: false,
                responses: processedResponses
            )
            
            let success = await KinematicRepository.shared.submitForm(request: request)
            await MainActor.run {
                isSubmitting = false
                if success { 
                    if let index = AppState.shared.selectedOutlet?.activities?.firstIndex(where: { $0.id == activity.id }) {
                        AppState.shared.selectedOutlet?.activities?[index].status = "completed"
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { appState.selectedActivity = nil }
                }
            }
        }
    }
}

struct DynamicFieldRow: View {
    let field: FormField
    @Binding var value: String
    @Binding var images: [UIImage]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if field.fieldType != "section_header" {
                HStack(spacing: 4) {
                    Text(field.label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    if field.isRequired {
                        Text("*").foregroundColor(.red).font(.system(size: 11))
                    }
                    Spacer()
                }
            }
            
            if let help = field.helpText, !help.isEmpty {
                Text(help).font(.footnote).foregroundColor(.secondary).padding(.bottom, 2)
            }
            
            fieldView
        }
    }
    
    @ViewBuilder
    private var fieldView: some View {
        switch field.fieldType {
        case "section_header":
            VStack(alignment: .leading, spacing: 6) {
                Text(field.label).font(.headline).foregroundColor(.red).padding(.top, 10)
                Divider()
            }
        case "select", "dropdown":
            Menu {
                ForEach(field.options ?? [], id: \.value) { opt in
                    Button(opt.label) { value = opt.value }
                }
            } label: {
                HStack {
                    Text(selectedLabel).foregroundColor(value.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundColor(.secondary)
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }
        case "radio", "checkbox":
            VStack(spacing: 1) {
                ForEach(field.options ?? [], id: \.value) { opt in
                    let isSelected = field.fieldType == "radio" ? (value == opt.value) : value.split(separator: ",").contains(Substring(opt.value))
                    Button(action: {
                        if field.fieldType == "radio" {
                            value = opt.value
                        } else {
                            var current = value.split(separator: ",").map { String($0) }
                            if isSelected { current.removeAll { $0 == opt.value } }
                            else { current.append(opt.value) }
                            value = current.joined(separator: ",")
                        }
                    }) {
                        HStack {
                            Text(opt.label).foregroundColor(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark").foregroundColor(.red).font(.system(size: 14, weight: .bold))
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    }
                    if opt.value != field.options?.last?.value {
                        Divider().padding(.leading)
                    }
                }
            }
            .cornerRadius(10)
        case "yes_no":
            HStack(spacing: 10) {
                YesNoButtonRedesign(label: "YES", isSelected: value == "yes") { value = "yes" }
                YesNoButtonRedesign(label: "NO", isSelected: value == "no") { value = "no" }
            }
        case "rating":
            RatingStarsRedesign(value: $value)
        case "image", "photo":
            MultiPhotoPickerRedesign(images: $images, maxCount: field.imageCount ?? 5)
        case "long_text":
            TextEditor(text: $value)
                .frame(height: 100)
                .padding(8)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(10)
        case "location":
            LocationFetcherRedesign(value: $value)
        default:
            TextField(field.placeholder ?? "Enter result", text: $value)
                .padding()
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(10)
        }
    }
    
    private var selectedLabel: String {
        field.options?.first(where: { $0.value == value })?.label ?? field.placeholder ?? "Choose..."
    }
}

struct YesNoButtonRedesign: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.red : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10)
        }
    }
}

struct RatingStarsRedesign: View {
    @Binding var value: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= (Int(value) ?? 0) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundColor(star <= (Int(value) ?? 0) ? .orange : .secondary.opacity(0.3))
                    .onTapGesture { value = "\(star)" }
            }
        }
    }
}

struct MultiPhotoPickerRedesign: View {
    @Binding var images: [UIImage]
    let maxCount: Int
    @State private var showCamera = false
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if images.count < maxCount {
                    Button(action: { showCamera = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "camera.fill").font(.title3)
                            Text("ADD").font(.system(size: 8, weight: .black))
                        }
                        .foregroundColor(.red)
                        .frame(width: 60, height: 60)
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(10)
                    }
                }
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60).cornerRadius(10).clipped()
                        .onTapGesture { images.remove(at: index) }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: Binding(get: { nil }, set: { if let img = $0 { images.append(img) } }), sourceType: .camera)
        }
    }
}

struct LocationFetcherRedesign: View {
    @Binding var value: String
    @State private var isFetching = false
    var body: some View {
        Button(action: {
            isFetching = true
            if let loc = LocationTrackingService.shared.lastLocation {
                value = String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isFetching = false }
        }) {
            HStack {
                Image(systemName: "location.circle.fill").foregroundColor(.red)
                Text(value.isEmpty ? "Tap to pinpoint GPS" : value).font(.subheadline).foregroundColor(value.isEmpty ? .secondary : .primary)
                Spacer()
                if isFetching { ProgressView() }
            }
            .padding().background(Color(uiColor: .tertiarySystemGroupedBackground)).cornerRadius(10)
        }
    }
}

struct Line { var points: [CGPoint] }

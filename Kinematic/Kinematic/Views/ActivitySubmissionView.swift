import SwiftUI
import CoreLocation
import PhotosUI

struct ActivitySubmissionView: View {
    let activity: RouteActivity
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: KiniAppState
    @State private var template: FormTemplate? = nil
    @State private var responses: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var isLoading = true
    @State private var cachedImages: [String: [UIImage]] = [:]

    private var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? UIScreen.main.bounds.width
    }

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
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            appState.selectedActivity = nil
                        }
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
                    Image(systemName: "chevron.left.circle.fill")
                        .opacity(0)
                        .font(.title2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.red).scaleEffect(1.2)
                        Text("Loading form...").font(.footnote).foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let t = template {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(t.name)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let desc = t.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Completion")
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(progress * 100))%")
                                        .font(.footnote)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(height: 5)
                                        Capsule()
                                            .fill(Color.red)
                                            .frame(width: geo.size.width * CGFloat(progress), height: 5)
                                            .animation(.easeInOut(duration: 0.3), value: progress)
                                    }
                                }
                                .frame(height: 5)
                            }
                            .padding(.horizontal, 24)

                            if let fields = t.fields {
                                VStack(spacing: 16) {
                                    ForEach(fields) { field in
                                        if shouldShow(field: field) {
                                            if field.fieldType == "section_header" {
                                                SectionHeaderRow(label: field.label)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.top, 8)
                                            } else {
                                                FieldCard(
                                                    field: field,
                                                    value: Binding(
                                                        get: { responses[field.id] ?? "" },
                                                        set: { responses[field.id] = $0 }
                                                    ),
                                                    images: Binding(
                                                        get: { cachedImages[field.id] ?? [] },
                                                        set: { cachedImages[field.id] = $0 }
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }

                            Spacer().frame(height: 120)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if template != nil && !isLoading {
                VStack(spacing: 0) {
                    Divider()
                    Button(action: { submit() }) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white).scaleEffect(0.85)
                            }
                            Text(isSubmitting ? "Submitting..." : "Submit Audit")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(activity.status == "completed" ? Color.gray : Color.red)
                        .cornerRadius(14)
                        .padding(.horizontal, 24)
                    }
                    .disabled(activity.status == "completed" || isSubmitting)
                    .padding(.vertical, 16)
                }
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .frame(width: screenWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                outletId: KiniAppState.shared.selectedOutlet?.rawId,
                outletName: KiniAppState.shared.selectedOutlet?.storeName,
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
                    if let index = KiniAppState.shared.selectedOutlet?.activities?.firstIndex(where: { $0.id == activity.id }) {
                        KiniAppState.shared.selectedOutlet?.activities?[index].status = "completed"
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        appState.selectedActivity = nil
                    }
                }
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeaderRow: View {
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .cornerRadius(1)
        }
    }
}

// MARK: - Field Card

struct FieldCard: View {
    let field: FormField
    @Binding var value: String
    @Binding var images: [UIImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(field.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if field.isRequired {
                    Text("Required")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                }
                Spacer(minLength: 0)
            }

            if let help = field.helpText, !help.isEmpty {
                Text(help)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            fieldControl
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private var fieldControl: some View {
        switch field.fieldType {
        case "select", "dropdown":
            DropdownField(field: field, value: $value)
        case "radio":
            ChoiceListField(field: field, value: $value, multiSelect: false)
        case "checkbox":
            ChoiceListField(field: field, value: $value, multiSelect: true)
        case "yes_no":
            YesNoField(value: $value)
        case "rating":
            RatingField(value: $value)
        case "image", "photo":
            PhotoCaptureField(images: $images, maxCount: field.imageCount ?? 5)
        case "file":
            FileAttachmentField(value: $value)
        case "signature":
            SignatureCaptureField(value: $value)
        case "consent":
            ConsentToggleField(value: $value)
        case "long_text":
            LongTextField(value: $value, placeholder: field.placeholder)
        case "location":
            LocationFetchField(value: $value)
        case "number":
            StyledTextField(value: $value, placeholder: field.placeholder ?? "0", keyboardType: .numberPad)
        case "phone":
            StyledTextField(value: $value, placeholder: field.placeholder ?? "Phone number", keyboardType: .phonePad)
        case "email":
            StyledTextField(value: $value, placeholder: field.placeholder ?? "Email address", keyboardType: .emailAddress)
        case "date":
            DateInputField(value: $value)
        default:
            StyledTextField(value: $value, placeholder: field.placeholder ?? "Enter response")
        }
    }
}

// MARK: - Field Controls

struct StyledTextField: View {
    @Binding var value: String
    var placeholder: String = "Enter response"
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $value)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .sentences)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
    }
}

struct LongTextField: View {
    @Binding var value: String
    var placeholder: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if value.isEmpty, let ph = placeholder {
                Text(ph)
                    .foregroundColor(Color(uiColor: .placeholderText))
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $value)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

struct DropdownField: View {
    let field: FormField
    @Binding var value: String

    private var selectedLabel: String {
        field.options?.first(where: { $0.value == value })?.label ?? field.placeholder ?? "Choose an option"
    }

    var body: some View {
        Menu {
            ForEach(field.options ?? [], id: \.value) { opt in
                Button(opt.label) { value = opt.value }
            }
        } label: {
            HStack {
                Text(selectedLabel)
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
}

struct ChoiceListField: View {
    let field: FormField
    @Binding var value: String
    let multiSelect: Bool

    private func isSelected(_ opt: FormOption) -> Bool {
        multiSelect
            ? value.split(separator: ",").map(String.init).contains(opt.value)
            : value == opt.value
    }

    private func toggle(_ opt: FormOption) {
        if multiSelect {
            var current = value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
            if isSelected(opt) { current.removeAll { $0 == opt.value } }
            else { current.append(opt.value) }
            value = current.joined(separator: ",")
        } else {
            value = opt.value
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array((field.options ?? []).enumerated()), id: \.element.value) { index, opt in
                Button(action: { toggle(opt) }) {
                    HStack(spacing: 12) {
                        Image(systemName: multiSelect
                            ? (isSelected(opt) ? "checkmark.square.fill" : "square")
                            : (isSelected(opt) ? "circle.inset.filled" : "circle"))
                            .foregroundColor(isSelected(opt) ? .red : .secondary)
                            .font(.system(size: 18))
                        Text(opt.label)
                            .foregroundColor(.primary)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isSelected(opt) ? Color.red.opacity(0.06) : Color(uiColor: .tertiarySystemGroupedBackground))
                }
                if index < (field.options?.count ?? 0) - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))
    }
}

struct YesNoField: View {
    @Binding var value: String
    var body: some View {
        HStack(spacing: 12) {
            YesNoButton(label: "Yes", isSelected: value == "yes") { value = "yes" }
            YesNoButton(label: "No", isSelected: value == "no") { value = "no" }
        }
    }
}

struct YesNoButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected
                    ? (label == "Yes" ? "checkmark.circle.fill" : "xmark.circle.fill")
                    : "circle")
                    .font(.system(size: 15))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isSelected ? Color.red : Color(uiColor: .tertiarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

struct RatingField: View {
    @Binding var value: String
    var body: some View {
        HStack(spacing: 16) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (Int(value) ?? 0)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundColor(filled ? .orange : Color.gray.opacity(0.3))
                    .onTapGesture { value = "\(star)" }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct PhotoCaptureField: View {
    @Binding var images: [UIImage]
    let maxCount: Int
    @State private var showCamera = false
    @State private var showGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if images.count < maxCount {
                HStack(spacing: 10) {
                    Button(action: { showCamera = true }) {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(10)
                    }
                    Button(action: { showGallery = true }) {
                        Label("Gallery", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(10)
                    }
                    Spacer()
                    Text("\(images.count)/\(maxCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<images.count, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: images[index])
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(10)
                                    .clipped()
                                Button(action: { images.remove(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                        .padding(4)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(
                image: Binding(get: { nil }, set: { if let img = $0 { images.append(img) } }),
                sourceType: .camera
            )
        }
        .sheet(isPresented: $showGallery) {
            PHPickerRepresentable(images: $images, maxCount: maxCount - images.count)
        }
    }
}

struct FileAttachmentField: View {
    @Binding var value: String
    @State private var showPicker = false

    private var hasFile: Bool { !value.isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: { showPicker = true }) {
                HStack(spacing: 12) {
                    Image(systemName: hasFile ? "doc.fill" : "paperclip.circle.fill")
                        .font(.title3)
                        .foregroundColor(hasFile ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasFile ? value : "Choose a file")
                            .font(.subheadline)
                            .foregroundColor(hasFile ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(hasFile ? "Tap to replace" : "PDF, images, or documents")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    if hasFile {
                        Button(action: { value = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                value = url.lastPathComponent
            }
        }
    }
}

struct ConsentToggleField: View {
    @Binding var value: String

    private var isConsented: Bool {
        value == "true" || value == "yes" || value == "1"
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isConsented },
            set: { value = $0 ? "true" : "false" }
        )) {
            HStack(spacing: 8) {
                Image(systemName: isConsented ? "checkmark.seal.fill" : "seal")
                    .foregroundColor(isConsented ? .green : .secondary)
                Text(isConsented ? "Agreed" : "Tap to agree")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isConsented ? .primary : .secondary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .green))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isConsented ? Color.green.opacity(0.07) : Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.2), value: isConsented)
    }
}

struct LocationFetchField: View {
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
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.isEmpty ? "Tap to capture location" : value)
                        .font(.subheadline)
                        .foregroundColor(value.isEmpty ? .secondary : .primary)
                    if !value.isEmpty {
                        Text("GPS coordinates captured")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                Spacer()
                if isFetching {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: value.isEmpty ? "location" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(value.isEmpty ? .secondary : .green)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
}

struct DateInputField: View {
    @Binding var value: String

    private var dateBinding: Binding<Date> {
        Binding(
            get: { ISO8601DateFormatter().date(from: value) ?? Date() },
            set: { value = ISO8601DateFormatter().string(from: $0) }
        )
    }

    var body: some View {
        HStack {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

// MARK: - PHPicker gallery wrapper

struct PHPickerRepresentable: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    let maxCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = max(1, maxCount)
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PHPickerRepresentable
        init(_ parent: PHPickerRepresentable) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        DispatchQueue.main.async { self.parent.images.append(image) }
                    }
                }
            }
        }
    }
}

// MARK: - Signature

struct SignatureCaptureField: View {
    @Binding var value: String
    @State private var lines: [SignatureLine] = []
    @State private var currentLine = SignatureLine(points: [])

    private var hasSignature: Bool { !value.isEmpty || !lines.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                Color(uiColor: .tertiarySystemGroupedBackground)
                Canvas { ctx, _ in
                    for line in lines {
                        var path = Path()
                        guard let first = line.points.first else { continue }
                        path.move(to: first)
                        for point in line.points.dropFirst() { path.addLine(to: point) }
                        ctx.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if !currentLine.points.isEmpty {
                        var path = Path()
                        path.move(to: currentLine.points[0])
                        for point in currentLine.points.dropFirst() { path.addLine(to: point) }
                        ctx.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                if !hasSignature {
                    Text("Sign here")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        currentLine.points.append(gesture.location)
                        if value.isEmpty { value = "drawn" }
                    }
                    .onEnded { _ in
                        if !currentLine.points.isEmpty {
                            lines.append(currentLine)
                            currentLine = SignatureLine(points: [])
                        }
                    }
            )

            if hasSignature {
                Button(action: clear) {
                    Label("Clear signature", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func clear() {
        lines.removeAll()
        currentLine = SignatureLine(points: [])
        value = ""
    }
}

struct SignatureLine {
    var points: [CGPoint]
}

// MARK: - Backward-compat aliases
typealias DynamicFieldRow = FieldCard
typealias YesNoButtonRedesign = YesNoButton
typealias RatingStarsRedesign = RatingField
typealias MultiPhotoPickerRedesign = PhotoCaptureField
typealias LocationFetcherRedesign = LocationFetchField

struct Line { var points: [CGPoint] }

struct SuccessOverlay: View {
    let message: String
    let action: () -> Void
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 25) {
                Spacer()
                ZStack {
                    Circle().fill(Color.green.opacity(0.1)).frame(width: 120, height: 120)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 80)).foregroundColor(.green)
                }
                VStack(spacing: 12) {
                    Text("Thank You!").font(.title2).fontWeight(.black).foregroundColor(Color(uiColor: .label))
                    Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 60)

                Button(action: action) {
                    Text("CONTINUE")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.green)
                        .cornerRadius(18)
                }
                .padding(.horizontal, 60)
                .padding(.top, 20)
                Spacer()
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
    }
}

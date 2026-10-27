import SwiftUI

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Mat Board")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !isSaving {
                            Button("Cancel", action: onCancel)
                        }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }

    private var isSaving: Bool {
        if case .saving = model.stage { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .loading:
            ProgressView("Opening photos…")
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: onCancel)
            }
            .padding()
        case .ready:
            editor
        case .saving(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Saving \(min(done + 1, total)) of \(total)")
            }
            .padding()
        case .finished(let saved, let skipped):
            VStack(spacing: 12) {
                Text(saved == 1 ? "Saved 1 photo" : "Saved \(saved) photos").font(.headline)
                ForEach(skipped, id: \.self) { line in
                    Text(line).font(.footnote).foregroundColor(.secondary)
                }
                Button("Done", action: onDone).buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var editor: some View {
        VStack(spacing: 16) {
            Group {
                if let preview = model.preview {
                    Image(uiImage: preview).resizable().scaledToFit().shadow(radius: 4)
                } else if model.previewFailed {
                    Text("Preview unavailable — you can still save.")
                        .font(.footnote).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }
            }
            .frame(maxHeight: 280)

            Picker("Border", selection: $model.settings.border) {
                ForEach(BorderSize.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            colourRow

            Picker("Size", selection: $model.settings.shape) {
                ForEach(Shape.allCases, id: \.self) { shape in
                    Text(ShapeLabel.chip(shape, settings: model.settings)).tag(shape)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.settings.shape.hasOrientation {
                Picker("Orientation", selection: $model.settings.orientation) {
                    Text("Portrait").tag(Orientation.portrait)
                    Text("Landscape").tag(Orientation.landscape)
                }
                .pickerStyle(.segmented)
            }

            if ShapeLabel.instagramCrops(model.settings) {
                Text("Instagram's feed will crop this shape.")
                    .font(.footnote).foregroundColor(.secondary)
            }

            Button {
                model.save()
            } label: {
                Text(model.paths.count == 1 ? "Save 1 photo" : "Save \(model.paths.count) photos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    /// Five swatches. The custom colour is chosen in the app; here it can
    /// only be picked as it is.
    private var colourRow: some View {
        HStack(spacing: 12) {
            ForEach(BorderColour.allCases, id: \.self) { colour in
                let rgb = model.settings.copying(colour: colour).fillRGB
                let selected = model.settings.colour == colour
                Button {
                    model.settings.colour = colour
                } label: {
                    Circle()
                        .fill(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selected ? 3 : 1))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colour == .custom ? "Custom colour, \(model.settings.customColour)" : colour.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

private extension RenderSettings {
    func copying(colour: BorderColour) -> RenderSettings {
        var copy = self
        copy.colour = colour
        return copy
    }
}

/// The same labels the app shows, so the two read alike.
enum ShapeLabel {
    static func chip(_ shape: Shape, settings: RenderSettings) -> String {
        var shown = settings
        shown.shape = shape
        switch shape {
        case .original: return "Original"
        case .custom: return "Custom \(number(settings.customWidth)):\(number(settings.customHeight))"
        default:
            guard let ratio = shown.ratio else { return shape.rawValue }
            let text = shape == .instagramWide ? "1.91:1" : "\(ratio.width):\(ratio.height)"
            return "\(text) \(purpose(shape, settings.orientation))"
        }
    }

    static func instagramCrops(_ settings: RenderSettings) -> Bool {
        guard let ratio = settings.ratio else { return false }
        let aspect = Double(ratio.width) / Double(ratio.height)
        return aspect < 0.75 - 1e-9 || aspect > 1.91 + 1e-9
    }

    private static func purpose(_ shape: Shape, _ orientation: Orientation) -> String {
        let portrait = orientation == .portrait
        switch shape {
        case .fiveFour: return portrait ? "Instagram" : "Print"
        case .fourThree: return portrait ? "Instagram tall" : "iPhone"
        case .threeTwo: return "Camera"
        case .sixteenNine: return portrait ? "Stories" : "Widescreen"
        case .square: return "Square"
        case .instagramWide: return "Instagram widest"
        case .custom, .original: return ""
        }
    }

    private static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

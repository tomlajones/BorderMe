import SwiftUI

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            content
                .navigationTitle("BorderMe")
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

            Picker("Colour", selection: $model.settings.colour) {
                ForEach(BorderColour.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Size", selection: $model.settings.size) {
                ForEach(SizePreset.allCases, id: \.self) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)

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
}

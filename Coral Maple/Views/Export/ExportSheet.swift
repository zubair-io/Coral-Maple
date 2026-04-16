import SwiftUI
import CoralCore

struct ExportSheet: View {
    @Environment(EditSession.self) private var editSession
    @Environment(UnifiedLibraryViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var config = ExportConfiguration()
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $config.format) {
                        ForEach(ExportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }

                    if config.format == .jpeg || config.format == .heic {
                        HStack {
                            Text("Quality")
                            Slider(value: $config.quality, in: 0.1...1.0, step: 0.05)
                            Text("\(Int(config.quality * 100))%")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                    }
                }

                Section("Resize") {
                    Picker("Size", selection: resizeModeBinding) {
                        Text("Original").tag(0)
                        Text("Long Edge").tag(1)
                    }

                    if case .longEdge = config.resizeMode {
                        HStack {
                            Text("Max pixels")
                            TextField("", value: longEdgeBinding, format: .number)
                                .frame(width: 80)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Text("px")
                        }
                    }
                }

                Section("Metadata") {
                    Toggle("Include EXIF/IPTC", isOn: $config.includeMetadata)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(JM.Font.caption())
                    }
                }

                if let url = exportedURL {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(JM.successText)
                            Text("Exported to \(url.lastPathComponent)")
                                .font(JM.Font.caption())
                        }
                    }
                }
            }
            .navigationTitle("Export Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { performExport() }
                        .disabled(isExporting)
                }
            }
            .overlay {
                if isExporting {
                    ProgressView("Exporting...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    // MARK: - Resize mode bindings

    private var resizeModeBinding: Binding<Int> {
        Binding(
            get: {
                if case .longEdge = config.resizeMode { return 1 }
                return 0
            },
            set: { val in
                config.resizeMode = val == 1 ? .longEdge(2048) : .original
            }
        )
    }

    private var longEdgeBinding: Binding<Int> {
        Binding(
            get: {
                if case .longEdge(let px) = config.resizeMode { return px }
                return 2048
            },
            set: { val in
                config.resizeMode = .longEdge(max(100, val))
            }
        )
    }

    // MARK: - Export

    private func performExport() {
        guard let asset = editSession.asset,
              let source = viewModel.activeSource else { return }

        isExporting = true
        errorMessage = nil
        exportedURL = nil

        Task {
            do {
                let engine = ExportEngine()
                let pipeline = ImageEditPipeline()
                let url = try await engine.export(
                    asset: asset,
                    adjustments: editSession.adjustments,
                    config: config,
                    source: source,
                    pipeline: pipeline
                )
                exportedURL = url
                #if os(macOS)
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                #endif
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
}

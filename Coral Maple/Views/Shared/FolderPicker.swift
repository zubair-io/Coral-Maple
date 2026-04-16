#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// UIDocumentPickerViewController wrapper for picking folders on iPadOS.
/// Starts security-scoped access immediately on the picked URL before
/// passing it to the callback — this is required for SMB shares.
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            // Don't start security scope here — FilesystemSource.addFolder()
            // handles scope acquisition and persists the bookmark.
            onPick(url)
        }
    }
}
#endif

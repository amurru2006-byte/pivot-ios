import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import UIKit
import SwiftUI

/// PhotosPicker hands off a file. Bound the read before allocating its bytes;
/// never retain photo-library identifiers or original image metadata.
struct CoachDocumentPhotoTransfer: Transferable {
    let bytes: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            .init(bytes: try read(received.file))
        }
    }
    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL, let stream = InputStream(url: url) else { throw CoachDocumentReader.Failure.image }
        stream.open(); defer { stream.close() }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw CoachDocumentReader.Failure.image }
            if count == 0 { break }
            guard bytes.count + count <= 20 * 1024 * 1024 else { throw CoachDocumentReader.Failure.image }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return bytes
    }
}

/// Camera is presented only after an explicit tap and OS permission. Video,
/// audio and automatic library saving are never requested.
struct CoachDocumentCamera: UIViewControllerRepresentable {
    var complete: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let complete: (Data?) -> Void
        init(complete: @escaping (Data?) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, image.size.width > 0, image.size.height > 0 else { complete(nil); return }
            let scale = min(1, 3000 / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            complete(reduced.jpegData(compressionQuality: 0.9))
        }
    }
}

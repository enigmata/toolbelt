import SwiftUI

/// Renders image data on both iOS (UIImage) and macOS (NSImage).
struct PhotoImage: View {
    let data: Data

    var body: some View {
        if let image = platformImage {
            image
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private var platformImage: Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}

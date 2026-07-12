import SwiftUI
import UIKit

/// Renders stored image data, falling back to a placeholder symbol.
struct PhotoImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

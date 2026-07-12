import SwiftUI

/// Full-screen, swipeable photo viewer with pinch-to-zoom and
/// double-tap-to-reset per page.
struct PhotoGalleryView: View {
    let photos: [ToolPhoto]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photos: [ToolPhoto], initialIndex: Int = 0) {
        self.photos = photos
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    ZoomablePhoto(data: photo.data)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

private struct ZoomablePhoto: View {
    let data: Data

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            PhotoImage(data: data)
                .aspectRatio(contentMode: .fit)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = max(1, min(5, lastScale * value.magnification))
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        scale = 1
                        lastScale = 1
                    }
                }
        }
    }
}

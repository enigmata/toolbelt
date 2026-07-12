import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera capture. Hands back JPEG data via `onCapture`;
/// the caller dismisses the presentation.
struct CameraCaptureView: View {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorized: Bool?
    private let camera = CameraService()

    var body: some View {
        ZStack {
            switch authorized {
            case .some(true):
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                controls
            case .some(false):
                deniedView
            case nil:
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            authorized = await CameraService.requestAuthorization()
            if authorized == true {
                camera.configureAndStart()
            }
        }
        .onDisappear { camera.stop() }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Cancel") { dismiss() }
                    .padding()
                    .foregroundStyle(.white)
                Spacer()
            }
            Spacer()
            Button {
                camera.capturePhoto { data in
                    onCapture(data)
                    dismiss()
                }
            } label: {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().fill(.white).frame(width: 60, height: 60))
            }
            .padding(.bottom, 32)
            .accessibilityLabel("Take Photo")
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("Allow camera access in Settings to photograph your tools.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel") { dismiss() }
        }
    }
}

/// AVCaptureSession lifecycle on a dedicated queue; session mutation and
/// capture callbacks never touch the main thread.
nonisolated final class CameraService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.enigmata.toolbelt.camera")
    private let output = AVCapturePhotoOutput()
    private var onCapture: (@MainActor (Data) -> Void)?

    static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func configureAndStart() {
        queue.async { [self] in
            if session.inputs.isEmpty {
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                }
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                session.commitConfiguration()
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func capturePhoto(completion: @escaping @MainActor (Data) -> Void) {
        onCapture = completion
        queue.async { [self] in
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let onCapture else { return }
        self.onCapture = nil
        Task { @MainActor in
            onCapture(data)
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

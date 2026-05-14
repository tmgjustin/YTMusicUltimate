import SwiftUI
import AVFoundation
import Vision

struct CameraScanView: View {
    @ObservedObject var viewModel: ScannerViewModel
    @StateObject private var camera = CameraController()
    @State private var textRegions: [CGRect] = []
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewLayer(session: camera.session).ignoresSafeArea()
            GeometryReader { geo in
                let diameter = min(geo.size.width, geo.size.height) * 0.75
                let cx = geo.size.width / 2; let cy = geo.size.height / 2
                ZStack {
                    Canvas { ctx, size in
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.50)))
                        ctx.blendMode = .clear
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - diameter/2, y: cy - diameter/2,
                                                        width: diameter, height: diameter)), with: .color(.white))
                    }.ignoresSafeArea()
                    Circle().stroke(.white, lineWidth: 2).frame(width: diameter, height: diameter).position(x: cx, y: cy)
                    ForEach(Array(textRegions.enumerated()), id: \.offset) { _, rect in
                        let f = CGRect(x: rect.minX * geo.size.width, y: (1 - rect.maxY) * geo.size.height,
                                       width: rect.width * geo.size.width, height: rect.height * geo.size.height)
                        Rectangle().stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                            .frame(width: f.width, height: f.height).position(x: f.midX, y: f.midY)
                    }
                }
            }
            VStack {
                Text("將鏡頭對準黑膠唱片中間標籤")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule()).padding(.top, 12)
                if !textRegions.isEmpty {
                    Text("偵測到文字 \(textRegions.count) 區塊")
                        .font(.caption).foregroundStyle(.yellow).padding(.top, 4)
                }
                Spacer()
                captureButton
                Spacer().frame(height: 44)
            }
        }
        .onAppear {
            camera.onTextDetected = { regions in
                withAnimation(.easeInOut(duration: 0.15)) { textRegions = regions }
            }
            camera.startSession()
        }
        .onDisappear { camera.stopSession() }
        .alert("需要相機權限", isPresented: $showPermissionAlert) {
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("請在「設定 > 隱私權 > 相機」中允許此 App 使用相機") }
    }

    @ViewBuilder
    private var captureButton: some View {
        if case .processing = viewModel.state {
            ProgressView().tint(.white).scaleEffect(1.5).frame(width: 72, height: 72)
        } else {
            Button {
                camera.capturePhoto { image in Task { await viewModel.processCapture(image) } }
            } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.4), lineWidth: 4).frame(width: 80, height: 80)
                    Circle().fill(.white).frame(width: 68, height: 68)
                }
            }
        }
    }
}

final class CameraController: NSObject, ObservableObject,
    AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    var onTextDetected: (([CGRect]) -> Void)?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue", qos: .userInitiated)
    private var captureCompletion: ((UIImage) -> Void)?
    private var lastFrameTime = Date.distantPast

    func startSession() { checkPermission() }
    func stopSession() { queue.async { self.session.stopRunning() } }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { if $0 { self.configureAndStart() } }
        default: break
        }
    }

    private func configureAndStart() {
        queue.async {
            guard !self.session.isRunning else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input)
            else { self.session.commitConfiguration(); return }
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        captureCompletion = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.captureCompletion?(image) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastFrameTime) > 0.4,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = Date()
        let req = VNDetectTextRectanglesRequest { [weak self] req, _ in
            let rects = (req.results as? [VNTextObservation])?.map(\.boundingBox) ?? []
            DispatchQueue.main.async { self?.onTextDetected?(rects) }
        }
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:]).perform([req])
    }
}

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> VideoPreviewView {
        let v = VideoPreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

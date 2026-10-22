import AVFoundation
import UIKit
import Vision

final class FingerCounterViewController: UIViewController {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let previewView = PreviewView()
    private let overlayView = LandmarkOverlayView()
    private let statusLabel = UILabel()
    private let videoQueue = DispatchQueue(label: "com.example.fingercounter.video")
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()
    private var isConfigured = false
    private var frameNumber = 0
    private var latestFaceData: FaceData?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureInterface()
        requestCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
        overlayView.frame = view.bounds
        overlayView.pointConverter = { [weak self] point in
            guard let self else { return .zero }
            let capturePoint = CGPoint(x: point.x, y: 1 - point.y)
            return self.previewView.videoPreviewLayer.layerPointConverted(
                fromCaptureDevicePoint: capturePoint
            )
        }
    }

    private func configureInterface() {
        previewView.videoPreviewLayer.session = captureSession
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)
        view.addSubview(overlayView)
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false

        statusLabel.text = "Đưa tay và khuôn mặt vào camera"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        ])
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    self?.statusLabel.text = "Hãy cấp quyền camera trong Cài đặt"
                    return
                }
                self?.configureCaptureSession()
            }
        }
    }

    private func configureCaptureSession() {
        guard !isConfigured else { return }
        isConfigured = true
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            captureSession.canAddInput(input),
            captureSession.canAddOutput(videoOutput)
        else {
            captureSession.commitConfiguration()
            statusLabel.text = "Không thể mở camera"
            return
        }

        captureSession.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        captureSession.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            connection.isVideoMirrored = true
        }
        if let previewConnection = previewView.videoPreviewLayer.connection,
           previewConnection.isVideoOrientationSupported {
            previewConnection.videoOrientation = .portrait
            previewConnection.isVideoMirrored = true
        }
        handRequest.maximumHandCount = 2
        captureSession.commitConfiguration()
        videoQueue.async { [captureSession] in captureSession.startRunning() }
    }

    private func handData(from observation: VNHumanHandPoseObservation) -> HandData? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        let names: [VNHumanHandPoseObservation.JointName] = [
            .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
        ]
        let tips = names.compactMap { name -> CGPoint? in
            guard let point = points[name], point.confidence > 0.35 else { return nil }
            return point.location
        }
        guard tips.count == names.count else { return nil }
        return HandData(tips: tips)
    }

    private func faceData(from observation: VNFaceObservation) -> FaceData? {
        guard let landmarks = observation.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let outerLips = landmarks.outerLips else { return nil }

        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map { local in
                return CGPoint(
                    x: observation.boundingBox.minX + local.x * observation.boundingBox.width,
                    y: observation.boundingBox.minY + local.y * observation.boundingBox.height
                )
            }
        }

        let left = points(leftEye)
        let right = points(rightEye)
        let lips = points(outerLips)
        guard let leftCenter = left.center, let rightCenter = right.center, let mouthCenter = lips.center else {
            return nil
        }
        let leftOpen = left.verticalSpan / max(left.horizontalSpan, 0.001) > 0.22
        let rightOpen = right.verticalSpan / max(right.horizontalSpan, 0.001) > 0.22
        let mouthOpen = lips.verticalSpan / max(lips.horizontalSpan, 0.001) > 0.12
        return FaceData(leftEye: leftCenter, rightEye: rightCenter, mouth: mouthCenter,
                        leftOpen: leftOpen, rightOpen: rightOpen, mouthOpen: mouthOpen)
    }
}

extension FingerCounterViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        frameNumber += 1
        do {
            try handler.perform(frameNumber % 3 == 0 ? [handRequest, faceRequest] : [handRequest])
            let hands = handRequest.results?.compactMap(handData) ?? []
            if frameNumber % 3 == 0 {
                latestFaceData = faceRequest.results?.first.flatMap(faceData)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.overlayView.update(hands: hands, face: self.latestFaceData)
                if hands.isEmpty && self.latestFaceData == nil {
                    self.statusLabel.text = "Đưa tay và khuôn mặt vào camera"
                } else {
                    self.statusLabel.text = "Xanh = mở · đỏ = đóng · chạm = vàng"
                }
            }
        } catch {
            print("Vision request failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.overlayView.update(hands: [], face: nil)
                self?.statusLabel.text = "Không nhận diện được, hãy đưa mặt/tay gần camera"
            }
        }
    }
}

private struct HandData {
    let tips: [CGPoint]
}

private struct FaceData {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let mouth: CGPoint
    let leftOpen: Bool
    let rightOpen: Bool
    let mouthOpen: Bool
}

private extension Array where Element == CGPoint {
    var center: CGPoint? {
        guard !isEmpty else { return nil }
        return CGPoint(x: reduce(0) { $0 + $1.x } / CGFloat(count),
                       y: reduce(0) { $0 + $1.y } / CGFloat(count))
    }

    var horizontalSpan: CGFloat {
        (map(\.x).max() ?? 0) - (map(\.x).min() ?? 0)
    }

    var verticalSpan: CGFloat {
        (map(\.y).max() ?? 0) - (map(\.y).min() ?? 0)
    }
}

private final class LandmarkOverlayView: UIView {
    private var hands: [HandData] = []
    private var face: FaceData?

    func update(hands: [HandData], face: FaceData?) {
        self.hands = hands
        self.face = face
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)
        for hand in hands {
            drawHand(hand, in: context)
        }
        if let face {
            drawDot(face.leftEye, color: face.leftOpen ? .systemGreen : .systemRed, in: context)
            drawDot(face.rightEye, color: face.rightOpen ? .systemGreen : .systemRed, in: context)
            drawDot(face.mouth, color: face.mouthOpen ? .systemGreen : .systemRed, in: context)
        }
    }

    private func drawHand(_ hand: HandData, in context: CGContext) {
        let colors: [UIColor] = [.systemOrange, .systemGreen, .systemBlue, .systemPurple, .systemPink]
        let thumb = hand.tips[0]
        let scale = max(distance(thumb, hand.tips[2]), 0.03)
        let hitRadius = scale * 0.16
        let displayRadius = max(10, hitRadius * min(bounds.width, bounds.height))
        for index in 1..<hand.tips.count {
            let touching = distance(thumb, hand.tips[index]) <= hitRadius * 2
            drawLine(thumb, hand.tips[index], color: touching ? .systemYellow : colors[index], width: touching ? 7 : 4, in: context)
            drawDot(hand.tips[index], color: touching ? .systemYellow : colors[index], radius: displayRadius, in: context)
        }
        drawDot(thumb, color: .systemOrange, radius: displayRadius, in: context)
    }

    private func drawLine(_ first: CGPoint, _ second: CGPoint, color: UIColor, width: CGFloat, in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: convert(first))
        context.addLine(to: convert(second))
        context.strokePath()
    }

    private func drawDot(_ point: CGPoint, color: UIColor, radius: CGFloat = 10, in context: CGContext) {
        context.setFillColor(color.cgColor)
        let converted = convert(point)
        context.fillEllipse(in: CGRect(x: converted.x - radius, y: converted.y - radius, width: radius * 2, height: radius * 2))
    }

    private func convert(_ point: CGPoint) -> CGPoint {
        pointConverter?(point) ?? CGPoint(x: point.x * bounds.width, y: (1 - point.y) * bounds.height)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    var pointConverter: ((CGPoint) -> CGPoint)?
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

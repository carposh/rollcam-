import AVFoundation
import UIKit

final class CameraController: NSObject, ObservableObject {
    enum Access { case unknown, authorized, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var torchAvailable = false
    @Published private(set) var isCapturing = false
    @Published var flashOn = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.ran.rollcam.camera")
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var pending: ((Data?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .authorized
            queue.async {
                self.configureIfNeeded()
                if !self.session.isRunning { self.session.startRunning() }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.start() } else { self.access = .denied }
                }
            }
        default:
            access = .denied
        }
    }

    func stop() {
        queue.async {
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flip() {
        queue.async {
            guard self.configured else { return }
            let target: AVCaptureDevice.Position = (self.input?.device.position == .front) ? .back : .front
            guard let device = Self.camera(at: target),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.setTorch(false)
            self.session.beginConfiguration()
            if let old = self.input { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
            } else if let old = self.input, self.session.canAddInput(old) {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            self.publishDeviceState()
        }
    }

    /// Takes one exposure. The torch stands in for a flash when `flash` is on.
    func capture(flash: Bool, completion: @escaping (Data?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        queue.async {
            guard self.configured, self.session.isRunning else {
                DispatchQueue.main.async {
                    self.isCapturing = false
                    completion(nil)
                }
                return
            }
            self.pending = completion
            if flash, self.input?.device.hasTorch == true {
                self.setTorch(true)
                Thread.sleep(forTimeInterval: 0.4) // let auto-exposure settle on the lit scene
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Private (camera queue)

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let device = Self.camera(at: .back) ?? Self.camera(at: .front),
           let deviceInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
            input = deviceInput
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
        configured = true
        publishDeviceState()
    }

    private func publishDeviceState() {
        let pos = input?.device.position ?? .back
        let torch = input?.device.hasTorch ?? false
        DispatchQueue.main.async {
            self.position = pos
            self.torchAvailable = torch
            if !torch { self.flashOn = false }
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = input?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on, device.isTorchModeSupported(.on) {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else if !on, device.torchMode != .off {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            // Torch is best effort; a failed flash still takes the picture.
        }
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async {
            self.setTorch(false)
            let completion = self.pending
            self.pending = nil
            DispatchQueue.main.async {
                self.isCapturing = false
                completion?(data)
            }
        }
    }
}

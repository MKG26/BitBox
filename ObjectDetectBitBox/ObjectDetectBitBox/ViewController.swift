//
//  ViewController.swift
//  ObjectDetectBitBox
//
//  Created by Mohit Kumar Gupta on 15/03/24.
//

import UIKit
import SwiftUI
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var permissionGranted = false
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private var previewLayer = AVCaptureVideoPreviewLayer()
    var screenRect: CGRect! = nil
    
    // Detector
    private var videoOutput = AVCaptureVideoDataOutput()
    var requests = [VNRequest]()
    var detectionLayer: CALayer! = nil
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer() // Speech synthesizer
    
    func playSound() {
        guard let soundFileURL = Bundle.main.url(forResource: "Tada-sound", withExtension: "mp3") else {
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: soundFileURL)
            audioPlayer?.play()
        } catch {
            print("Error playing sound: \(error.localizedDescription)")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        checkPermission()
        
        sessionQueue.async { [unowned self] in
            guard permissionGranted else { return }
            self.setupCaptureSession()
            
            self.setupLayers()
            self.setupDetector()
            
            self.captureSession.startRunning()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Reset layers when view reappears
        self.setupLayers()
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        screenRect = UIScreen.main.bounds
        self.previewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)

        switch UIDevice.current.orientation {
        // Home button on top
        case UIDeviceOrientation.portraitUpsideDown:
            self.previewLayer.connection?.videoOrientation = .portraitUpsideDown
         
        // Home button on right
        case UIDeviceOrientation.landscapeLeft:
            self.previewLayer.connection?.videoOrientation = .landscapeRight
        
        // Home button on left
        case UIDeviceOrientation.landscapeRight:
            self.previewLayer.connection?.videoOrientation = .landscapeLeft
         
        // Home button at bottom
        case UIDeviceOrientation.portrait:
            self.previewLayer.connection?.videoOrientation = .portrait
            
        default:
            break
        }
        
        // Detector
        updateLayers()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        // Permission has been granted before
        case .authorized:
            permissionGranted = true
            
        // Permission has not been requested yet
        case .notDetermined:
            requestPermission()
                
        default:
            permissionGranted = false
        }
    }
    
    func requestPermission() {
        sessionQueue.suspend()
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
            self.sessionQueue.resume()
        }
    }
    
    func setupCaptureSession() {
        // Camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInDualWideCamera,for: .video, position: .back) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
           
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
                         
        // Preview layer
        screenRect = UIScreen.main.bounds
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill // Fill screen
        previewLayer.connection?.videoOrientation = .portrait
        
        // Detector
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        // Updates to UI must be on main queue
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(self!.previewLayer)
        }
    }
}

struct HostedViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

extension ViewController {
    
    func setupDetector() {
        let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc")
    
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL!))
            let recognitions = VNCoreMLRequest(model: visionModel, completionHandler: detectionDidComplete)
            self.requests = [recognitions]
        } catch let error {
            print(error)
        }
    }
    
    func detectionDidComplete(request: VNRequest, error: Error?) {
        DispatchQueue.main.async(execute: {
            if let results = request.results {
                self.extractDetections(results)
            }
        })
    }
    
    func extractDetections(_ results: [VNObservation]) {
        detectionLayer.sublayers = nil
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else { continue }
            
            // Transformations
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(screenRect.size.width), Int(screenRect.size.height))
            let transformedBounds = CGRect(x: objectBounds.minX, y: screenRect.size.height - objectBounds.maxY, width: objectBounds.maxX - objectBounds.minX, height: objectBounds.maxY - objectBounds.minY)
            
            // Play sound if object is close enough
            if transformedBounds.width > screenRect.width / 3 || transformedBounds.height > screenRect.height / 3 {
                playSound()
                speakLabel(objectObservation.labels.first?.identifier ?? "Unknown") // Speak label
                displayLabel(objectObservation.labels.first?.identifier ?? "Unknown", at: transformedBounds) // Display label
            }
            
            // Draw bounding box
            let boxLayer = drawBoundingBox(transformedBounds)
            
            detectionLayer.addSublayer(boxLayer)
        }
    }
    
    func setupLayers() {
        detectionLayer = CALayer()
        detectionLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        DispatchQueue.main.async { [weak self] in
            self!.view.layer.addSublayer(self!.detectionLayer)
        }
    }
    
    func updateLayers() {
        detectionLayer?.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
    }
    
    func drawBoundingBox(_ bounds: CGRect) -> CALayer {
        let boxLayer = CALayer()
        boxLayer.frame = bounds
        boxLayer.borderWidth = 3.0
        boxLayer.borderColor = CGColor.init(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        boxLayer.cornerRadius = 4
        return boxLayer
    }
    
    func speakLabel(_ label: String) {
        let speechUtterance = AVSpeechUtterance(string: label)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(speechUtterance)
    }
    
    func displayLabel(_ label: String, at bounds: CGRect) {
        let labelLayer = CATextLayer()
        labelLayer.string = label
        labelLayer.fontSize = 14
        labelLayer.foregroundColor = UIColor.white.cgColor
        labelLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        labelLayer.frame = CGRect(x: bounds.minX, y: bounds.minY - 20, width: bounds.width, height: 20)
        labelLayer.alignmentMode = .center
        detectionLayer.addSublayer(labelLayer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
}

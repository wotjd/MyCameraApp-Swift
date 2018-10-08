//
//  ViewController.swift
//  MyCameraApp3
//
//  Created by wotjd on 2018. 8. 6..
//  Copyright © 2018년 wotjd. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    @IBOutlet weak var camPreview: UIView!
    
    @IBOutlet weak var zoomSlider: UISlider!
    @IBOutlet weak var zoomLabel: UILabel!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var exposureSlider: UISlider!
    
    @IBOutlet weak var recordingTimeLabel: UILabel!
    
    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var activeInput: AVCaptureDeviceInput!
    var outputURL: URL!
    var currentScale: CGFloat = 1.0
    
    var isFlashOn = false
    var isRecording = false
    
    // hide zoom label with animation
    var zoomTimer: Timer?
    var zoomExitAnimator : UIViewPropertyAnimator? = nil
    
    // recording time
    var recordingTimer: Timer?
    var seconds : Int64 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        recordingTimeLabel.layer.masksToBounds = true
//        recordingTimeLabel.layer.cornerRadius = 10
        if self.setupSession() {
            self.setupPreview()
            self.startSession()
        
            self.exposureSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi/2))
            self.exposureSlider.layer.position = CGPoint(x: 325, y: 334)
//            exposureSlider.minimumValue = self.activeInput.device.minExposureTargetBias   // -8.0
//            exposureSlider.maximumValue =  self.activeInput.device.maxExposureTargetBias  // 8.0
            self.exposureSlider.minimumValue = -5.0
            self.exposureSlider.maximumValue = 5.0
            self.exposureSlider.value = self.activeInput.device.exposureTargetBias
            
            self.view.addSubview(exposureSlider)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func setupPreview() {
        // Configure previewlayer
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer.frame = self.camPreview.bounds
        self.previewLayer.videoGravity = .resizeAspectFill
        self.camPreview.layer.addSublayer(self.previewLayer)
    }
    
    // MARK:- Setup Camera
    func setupSession() -> Bool {
        self.captureSession.sessionPreset = AVCaptureSession.Preset.hd1920x1080
        
        // Setup Camera
        let camera = AVCaptureDevice.default(for: .video)
        
        
        if let device = camera {
            for vFormat in camera!.formats {
                let ranges = vFormat.videoSupportedFrameRateRanges
                let frameRates = ranges[0]
                
                let dimensions = CMVideoFormatDescriptionGetDimensions(vFormat.formatDescription)

                if dimensions.width == 1920 && frameRates.maxFrameRate == 30 {
                    do {
                        try device.lockForConfiguration()
                        device.activeFormat = vFormat as AVCaptureDevice.Format
                        device.activeVideoMinFrameDuration = frameRates.minFrameDuration
                        device.activeVideoMaxFrameDuration = frameRates.maxFrameDuration
                        
                        print("format info : \(vFormat.description)")
                        device.unlockForConfiguration()
                    } catch {
                        print("Error Setting Configuration: \(error)")
                    }
                    break;
                }
            }
            
//            device.addObserver(self, forKeyPath: "adjustingFocus", options: .new, context: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera!)
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
                self.activeInput = input
            }
        } catch {
            print("Error Setting device video input: \(error)")
            return false
        }
        
        // Setup Microphone
        let microphone = AVCaptureDevice.default(for: .audio)
        
        do {
            let micInput = try AVCaptureDeviceInput(device: microphone!)
            if captureSession.canAddInput(micInput) {
                captureSession.addInput(micInput)
            }
        } catch {
            print("Error Setting device audio input: \(error)")
            return false
        }
        
        // Movie output
        if self.captureSession.canAddOutput(self.movieOutput) {
            self.captureSession.addOutput(self.movieOutput)
        }
        
        return true
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "adjustingFocus" {
            if self.activeInput.device.isAdjustingFocus {
                print("adjusting focus")
            } else {
                print("ignoring adjusting focus")
            }
        }
    }
    
    @objc func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        print("subjectAreaDidChange")
        self.focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    // MARK:- Camera Session
    func startSession() {
        if !self.captureSession.isRunning {
            DispatchQueue.main.async {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        if self.captureSession.isRunning {
            DispatchQueue.main.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func currentVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation
        
        switch UIDevice.current.orientation {
        case .portrait :
            orientation = AVCaptureVideoOrientation.portrait
        case .landscapeRight :
            orientation = AVCaptureVideoOrientation.landscapeRight
        case .landscapeLeft :
            orientation = AVCaptureVideoOrientation.landscapeLeft
        default :
            orientation = AVCaptureVideoOrientation.portraitUpsideDown
        }
        
        return orientation
    }
    
    func startCapture() {
        self.startRecording()
    }
    
    func tempURL() -> URL? {
        let directory = NSTemporaryDirectory() as NSString
        
        if directory != "" {
            let path = directory.appendingPathComponent(NSUUID().uuidString + ".mp4")
            print("\(path)")
            return URL(fileURLWithPath: path)
        }
        
        return nil
    }
    
    func startRecording() {
        if self.movieOutput.isRecording == false {
            let connection = self.movieOutput.connection(with: .video)
            if (connection?.isVideoOrientationSupported)! {
                connection?.videoOrientation = self.currentVideoOrientation()
            }
            
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }
            
            let device = self.activeInput.device
            if (device.isSmoothAutoFocusSupported) {
                do {
                    try device.lockForConfiguration()
                    device.isSmoothAutoFocusEnabled = false
                    device.unlockForConfiguration()
                } catch {
                    print("Error Setting Configuration: \(error)")
                }
            }
            
            self.outputURL = self.tempURL()
            self.movieOutput.startRecording(to: self.outputURL, recordingDelegate: self)
            print("start Recording")
        } else {
            stopRecording();
        }
    }

    func stopRecording() {
        if self.movieOutput.isRecording == true {
            self.movieOutput.stopRecording()
            print("stopRecording : \(self.outputURL!.absoluteString)")
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if (error != nil) {
            print("Error recording movie: \(error!.localizedDescription)")
        } else {
            let url = self.outputURL!
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { saved, error in
                if saved {
                    DispatchQueue.main.async {
                        let alertController = UIAlertController(title: "Your video was successfully saved!", message: nil, preferredStyle: .alert)
                        let defaultAction = UIAlertAction(title: "OK", style: .default, handler : nil)
                        alertController.addAction(defaultAction)
                        self.present(alertController, animated: true, completion: nil)
                    }
                    print("saved video")
                } else {
                    print("cannot save video")
                    print("\(error.debugDescription)")
                }
            }
            _ = self.outputURL as URL
        }
        self.outputURL = nil
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        DispatchQueue.main.async {
            let device = self.activeInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                // reset exposure bias
                device.setExposureTargetBias(0, completionHandler: nil)
                self.exposureSlider.value = 0
                if exposureMode == .continuousAutoExposure {
                    self.exposureSlider.isEnabled = false
                    self.exposureSlider.isHidden = true
                } else {
                    self.exposureSlider.isHidden = false
                    self.exposureSlider.isEnabled = true
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    func zoom(_ factor : CGFloat, isSlider : Bool = false) {
        if self.currentScale != factor {
            let device = self.activeInput.device
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                self.zoomLabel.text = "Zoom Factor : \(Int(factor * 100))%"
                //                self.zoomLabel ("Zoom Factor : \(Int(factor * 100))%")
                if !isSlider {
                    self.zoomSlider.setValue(Float(factor), animated: true)
                }
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    @IBAction func recordTap(_ sender: KYShutterButton) {
        switch sender.buttonState {
        case .normal:
            self.startRecording()
            self.startRecordingTimer()
            //            print("started")
            sender.buttonState = .recording
            self.isRecording = true
        case .recording:
            self.stopRecording()
            self.resetRecordingTimer()
            print("stopped")
            self.isRecording = false
            sender.buttonState = .normal
        }
    }
    
    @IBAction func focusTap(_ sender: UITapGestureRecognizer) {
        let devicePoint = self.previewLayer.captureDevicePointConverted(fromLayerPoint: sender.location(in: sender.view))
        print("focusTap : converted point : \(devicePoint)")
        
        self.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    @IBAction func focusLongPress(_ sender: UITapGestureRecognizer) {
        let devicePoint = self.previewLayer.captureDevicePointConverted(fromLayerPoint: sender.location(in: sender.view))
        
        switch sender.state {
        case .began :
            print("focusLongPress : began")
            print("focusLongPress : converted point \(devicePoint)")
            
            self.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: false)
            
        case .ended :
            print("focusLongPress : ended")
            self.focus(with: .locked, exposureMode: .locked, at: devicePoint, monitorSubjectAreaChange: false)
        default :
            break
        }
    }
    
    
    @IBAction func sliderTouchDown(_ sender: Any) {
        self.showZoomInfo()
    }
    
    @IBAction func zoomSlide(_ sender: UISlider) {
        //        print("[zoomSlide] value changed \(sender.value)")
        self.zoom(CGFloat(sender.value), isSlider : true)
    }
    
    @IBAction func sliderTouchUp(_ sender: Any) {
        self.hideZoomInfo()
    }
    
    @IBAction func pinch(_ sender: UIPinchGestureRecognizer) {
        switch sender.state {
        case .began :
            self.currentScale = self.activeInput.device.videoZoomFactor
            print("max zoom factor : \(self.activeInput.device.activeFormat.videoMaxZoomFactor)")
            self.showZoomInfo()
        case .changed :
            self.zoom(max(1, min(self.currentScale * sender.scale, self.activeInput.device.activeFormat.videoMaxZoomFactor)))
        default:    // ended
            print("ended")
            self.hideZoomInfo()
            break
        }
    }
    
    
    @IBAction func flashTap(_ sender: UIButton) {
        let device = self.activeInput.device
        do {
            try device.lockForConfiguration()
            
            if self.isFlashOn {
                let img = UIImage(named: "Flash Off Icon")
                sender.setImage(img, for: UIControlState.normal)
                device.torchMode = .on
            } else {
                let img = UIImage(named: "Flash On Icon")
                sender.setImage(img, for: UIControlState.normal)
                device.torchMode = .off
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
        }
        
        self.isFlashOn = !self.isFlashOn
    }
    
    @IBAction func exposureSlide(_ sender: UISlider) {
        do {
            //            print("range : \(self.activeInput.device.minExposureTargetBias) ~ \(self.activeInput.device.maxExposureTargetBias)")
            try self.activeInput.device.lockForConfiguration()
            self.activeInput.device.setExposureTargetBias(sender.value, completionHandler: nil)
            self.activeInput.device.unlockForConfiguration()
            print("value : \(sender.value)")
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
}

// update recording time
extension ViewController {
    @objc func tickClock() {
        self.seconds += 1
        self.recordingTimeLabel.text = String(format: "%02d:%02d:%02d", Int(seconds/3600), Int(seconds/60), seconds % 60)
    }
    
    func startRecordingTimer() {
        self.recordingTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.tickClock), userInfo: nil, repeats: true)
    }
    
    func resetRecordingTimer() {
        self.recordingTimer?.invalidate()
        self.seconds = 0
        self.recordingTimeLabel.text = "00:00:00"
    }
}

// hide zoom label with animation
extension ViewController {
    func showZoomInfo() {
        print("showZoomInfo")
        self.zoomTimer?.invalidate()
        self.zoomExitAnimator?.stopAnimation(true)
        
        self.flashButton.isHidden = true
        self.zoomSlider.alpha = 1
        self.zoomSlider.isHidden = false
        self.zoomLabel.alpha = 1
        self.zoomLabel.isHidden = false
    }
    
    func hideZoomInfo() {
        self.zoomTimer = Timer.scheduledTimer(timeInterval: 2.75, target: self, selector: #selector(zoomExitWithAnimation), userInfo: nil, repeats: false)
        print("hideZoomInfo")
        
        self.zoomExitAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) {
            self.zoomSlider.alpha = 0
            self.zoomLabel.alpha = 0
        }
        
        self.zoomExitAnimator!.addCompletion { _ in
            self.zoomSlider.isHidden = true
            self.zoomLabel.isHidden = true
            self.flashButton.isHidden = false
        }
    }
    
    @objc func zoomExitWithAnimation() {
        self.zoomExitAnimator!.startAnimation()
    }
}

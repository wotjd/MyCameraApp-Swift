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

// TODO : add device property
class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    @IBOutlet weak var camPreview: UIView!
    @IBOutlet weak var notFoundLabel: UILabel!
    
//    @IBOutlet weak var zoomLabel: UILabel!
    @IBOutlet weak var flashButton: UIButton!
    @IBOutlet weak var flashStateSegment: UISegmentedControl!
    @IBOutlet weak var recordingTimeLabel: UILabel!
    @IBOutlet weak var exposureSlider: UISlider!
    @IBOutlet weak var zoomSlider: UISlider!
    @IBOutlet weak var recordingButton: UIButton!
    @IBOutlet weak var cameraChangeButton: UIButton!
    
    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    
    var previewLayer: AVCaptureVideoPreviewLayer!
    var activeInput: AVCaptureDeviceInput!
    var outputURL: URL!
    var currentScale: CGFloat = 1.0
    
    var isFlashOn = false
    var isRecording = false
    
    var animationQueue = DispatchQueue(label: "animationQueue")
    var flashSegmentAnimator : UIViewPropertyAnimator? = nil
    
    // hide zoom label with animation
    var zoomTimer: Timer?
    var zoomExitAnimator : UIViewPropertyAnimator? = nil
    
    // recording time
    var recordingTimer: Timer?
    var seconds : Int64 = 0
    
    private var isVideoAuthorized = true
    private var isAudioAuthorized = true
    private var isPhotoAuthorized = true
    
    private var isDualCamera = false
    
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var isSetupSuccess = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        recordingTimeLabel.layer.masksToBounds = true
//        recordingTimeLabel.layer.cornerRadius = 10
        
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            break;
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization() { status in
                if status != .authorized {
                    self.isPhotoAuthorized = false
                }
            }
        default:
            self.isPhotoAuthorized = false
        }
        
        
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break;
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                if !granted {
                    self.isAudioAuthorized = false
                }
            })
        default:
            self.isAudioAuthorized = false
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.isVideoAuthorized = false
                }
            })
        default:
            self.isVideoAuthorized = false
        }
        
        self.setupPreview()
        self.sessionQueue.async {
            self.isSetupSuccess = self.setupSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.sessionQueue.async {
            if self.isSetupSuccess {
                DispatchQueue.main.async {
                    self.cameraChangeButton.isEnabled = self.isDualCamera
                    self.recordingButton.isEnabled = true
                    self.flashButton.isEnabled = true
                
                    self.exposureSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi/2))
                    self.exposureSlider.layer.position = CGPoint(x: 325, y: 334)
                    self.exposureSlider.minimumValue = self.activeInput.device.minExposureTargetBias   // -8.0
                    self.exposureSlider.maximumValue =  self.activeInput.device.maxExposureTargetBias  // 8.0
                    self.exposureSlider.value = self.activeInput.device.exposureTargetBias
                
                    self.view.addSubview(self.exposureSlider)
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            
                self.captureSession.startRunning()
            } else {
                self.notFoundLabel.alpha = 1.0
                if !self.isVideoAuthorized || !self.isPhotoAuthorized || !self.isAudioAuthorized {
                    self.notFoundLabel.alpha = 1.0
                    DispatchQueue.main.async {
                        let changePrivacySetting = "이 앱을 사용하기 위해서 카메라, 사진, 마이크의 권한이 필요합니다. 설정에서 권한을 변경해주세요."
                        let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                        let alertController = UIAlertController(title: "권한이 필요합니다", message: message, preferredStyle: .alert)
                        /*
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                                style: .cancel,
                                                                handler: nil))
                        */
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                                style: .`default`,
                                                                handler: { _ in
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: convertToUIApplicationOpenExternalURLOptionsKeyDictionary([:]), completionHandler: nil)
                        }))
                        
                        self.present(alertController, animated: true, completion: nil)
                    }
                } else {
                    DispatchQueue.main.async {
                        let alertMsg = "카메라 실행 도중 알 수 없는 에러가 발생 했습니다."
                        let message = NSLocalizedString("Unable to capture Media", comment: alertMsg)
                        let alertController = UIAlertController(title: "카메라 실행 불가", message: message, preferredStyle: .alert)
                        
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                                style: .cancel,
                                                                handler: nil))
                        
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.isIdleTimerDisabled = false
        
        self.setRecorderState(false)
        self.captureSession.stopRunning()
        
        self.notFoundLabel.alpha = 0.0
        self.cameraChangeButton.isEnabled = false
        self.recordingButton.isEnabled = false
        self.flashButton.isEnabled = false
        self.zoomSlider.isEnabled = false
        self.exposureSlider.isEnabled = false
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    @IBAction func cameraTap(_ sender: UIButton) {
        if self.isDualCamera {
            let currentType = self.activeInput.device.deviceType
            
            do {
                var camera : AVCaptureDevice? = nil
                var color = UIColor.white
                
                if currentType == .builtInWideAngleCamera {
                    camera = AVCaptureDevice.default(.builtInTelephotoCamera, for: nil, position: .back)
                    color = UIColor(displayP3Red: 1, green: 197.0/255.0, blue: 45.0/255.0, alpha: 1.0)
                } else {
                    camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: nil, position: .back)
                }
                
                guard let device = camera else {
                    print("failed to find device")
                    return
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                self.captureSession.beginConfiguration()
                
                self.captureSession.removeInput(self.activeInput)
                
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.activeInput = input
                } else {
                    self.captureSession.addInput(self.activeInput)
                }
                
                self.captureSession.commitConfiguration()
                
                self.cameraChangeButton.tintColor = color
            } catch {
                print("error")
            }
            
        }
    }
    
    @IBAction func recordTap(_ sender: KYShutterButton) {
        if self.captureSession.isRunning {
            switch sender.buttonState {
            case .normal:
                self.setRecorderState(true)
                sender.buttonState = .recording
                self.cameraChangeButton.isEnabled = false
            case .recording:
                self.setRecorderState(false)
                sender.buttonState = .normal
                self.cameraChangeButton.isEnabled = self.isDualCamera
            }
        }
    }
    
    @IBAction func focusTap(_ sender: UITapGestureRecognizer) {
        if self.captureSession.isRunning {
            let devicePoint = self.previewLayer.captureDevicePointConverted(fromLayerPoint: sender.location(in: sender.view))
            print("focusTap : converted point : \(devicePoint)")
            
            self.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        }
    }
    
    @IBAction func focusLongPress(_ sender: UITapGestureRecognizer) {
        if self.captureSession.isRunning {
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
    }
    
    
    @IBAction func sliderTouchDown(_ sender: Any) {
        if self.captureSession.isRunning {
            self.showZoomInfo()
        }
    }
    
    @IBAction func zoomSlide(_ sender: UISlider) {
        //        print("[zoomSlide] value changed \(sender.value)")
        if self.captureSession.isRunning {
            self.zoom(CGFloat(sender.value), isSlider : true)
        }
    }
    
    @IBAction func sliderTouchUp(_ sender: Any) {
        if self.captureSession.isRunning {
            self.hideZoomInfo()
        }
    }
    
    @IBAction func pinch(_ sender: UIPinchGestureRecognizer) {
        if self.captureSession.isRunning {
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
    }
    
    var isFlashSegmentShow = false
    @IBAction func flashTap(_ sender: UIButton) {
        if self.isFlashSegmentShow {
            self.hideFlashSegment()
            self.isFlashSegmentShow = false
        } else {
            self.showFlashSegment()
            self.isFlashSegmentShow = true
        }
    }
    
    @IBAction func flashSegmentTap(_ sender: UISegmentedControl) {
        print("selected : \(sender.selectedSegmentIndex)")
        
        if self.captureSession.isRunning {
            let device = self.activeInput.device
            do {
                try device.lockForConfiguration()
  
                switch sender.selectedSegmentIndex {
                    case 0 : device.torchMode = .auto
                    case 1 : device.torchMode = .on
                    default : device.torchMode = .off
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
        self.hideFlashSegment()
    }
    
    @IBAction func exposureSlide(_ sender: UISlider) {
        if self.captureSession.isRunning {
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
}

extension ViewController {
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
        
        if let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: nil, position: .back) {
            print("found built in telephoto camera")
            self.isDualCamera = true
        }
        
        // Setup Camera
        //        let camera = AVCaptureDevice.default(.builtInWideAngleCamera ,for: .video, position: .back)
        let camera = AVCaptureDevice.default(.builtInWideAngleCamera ,for: .video, position: .back)
        
        guard let device = camera else {
            print("cannot find camera device")
            return false
        }
        
        for vFormat in device.formats {
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
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
                self.activeInput = input
            }
        } catch {
            print("Error adding video input: \(error)")
            return false
        }
        
        // Setup Microphone
        if let microphone = AVCaptureDevice.default(for: .audio) {
            do {
                let micInput = try AVCaptureDeviceInput(device: microphone)
                if captureSession.canAddInput(micInput) {
                    captureSession.addInput(micInput)
                }
            } catch {
                print("Error Setting device audio input: \(error)")
            }
        } else {
            print("cannot access to mic. movie will be recorded without audio.")
        }
        
        
        // Movie output
        if self.captureSession.canAddOutput(self.movieOutput) {
            self.captureSession.addOutput(self.movieOutput)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: self.activeInput.device)
        
        return true
    }
    
    func currentVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation
        
        switch UIDevice.current.orientation {
        case .portrait, .landscapeLeft :
            orientation = .landscapeRight
        default :
            orientation = .landscapeLeft
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
    
    func setRecorderState(_ state: Bool) {
        guard state != self.isRecording else {
            return
        }
        
        if state {
            self.startRecording()
            self.startRecordingTimer()
            print("started")
            
        } else {
            self.stopRecording()
            self.resetRecordingTimer()
            print("stopped")
        }
        
        self.isRecording = state
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
                    do {
                        print("saved video. deleting file..")
                        try FileManager.default.removeItem(at: url)
                        print("successfully deleted")
                    } catch {
                        print(error)
                    }
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
                //                self.zoomLabel.text = "Zoom Factor : \(Int(factor * 100))%"
                if !isSlider {
                    self.zoomSlider.setValue(Float(factor), animated: true)
                }
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
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

extension ViewController {
    func showFlashSegment() {
//        print("showFlashSegment")
//        print("\(self.flashStateSegment.alpha)")
        if !self.flashStateSegment.isEnabled {
            self.flashStateSegment.isEnabled = true
            self.flashStateSegment.alpha = 0
        }
        
        self.flashSegmentAnimator?.stopAnimation(true)
        
        
        self.flashSegmentAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) {
            self.flashStateSegment.alpha = 1
            self.recordingTimeLabel.alpha = 0
            
            let img = UIImage(named: "Flash On Icon")
            self.flashButton.setImage(img, for: UIControl.State.normal)
            self.flashButton.tintColor = UIColor.white
        }
        
        self.flashSegmentAnimator!.startAnimation()
    }
    
    func hideFlashSegment() {
//        print("hideFlashSegment")
        let torchMode = self.activeInput.device.torchMode
        if torchMode == .off {
            let img = UIImage(named: "Flash Off Icon")
            self.flashButton.setImage(img, for: UIControl.State.normal)
        } else {
            let img = UIImage(named: "Flash On Icon")
            self.flashButton.setImage(img, for: UIControl.State.normal)
        }
        
        self.flashSegmentAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) {
            self.flashStateSegment.alpha = 0
            self.recordingTimeLabel.alpha = 1
            if torchMode == .on {
                // 255, 197, 45
                self.flashButton.tintColor = UIColor(displayP3Red: 1, green: 197.0/255.0, blue: 45.0/255.0, alpha: 1.0)
            }
        }
        
        self.flashSegmentAnimator!.addCompletion { _ in
            self.flashStateSegment.isEnabled = false
        }
        
        self.flashSegmentAnimator!.startAnimation()
    }
}

// hide zoom label with animation
extension ViewController {
    func showZoomInfo() {
        print("showZoomInfo")
        self.zoomTimer?.invalidate()
        self.zoomExitAnimator?.stopAnimation(true)
        
//        self.flashButton.isHidden = true
        self.zoomSlider.alpha = 1
        self.zoomSlider.isEnabled = true
        self.zoomSlider.isHidden = false
        
//        self.zoomLabel.alpha = 1
//        self.zoomLabel.isHidden = false
    }
    
    func hideZoomInfo() {
        self.zoomTimer = Timer.scheduledTimer(timeInterval: 2.75, target: self, selector: #selector(zoomExitWithAnimation), userInfo: nil, repeats: false)
        print("hideZoomInfo")
        
        self.zoomExitAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) {
            self.zoomSlider.alpha = 0
//            self.zoomLabel.alpha = 0
        }
        
        self.zoomExitAnimator!.addCompletion { _ in
            self.zoomSlider.isEnabled = false
            self.zoomSlider.isHidden = true
//            self.zoomLabel.isHidden = true
//            self.flashButton.isHidden = false
        }
    }
    
    @objc func zoomExitWithAnimation() {
        self.zoomExitAnimator!.startAnimation()
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUIApplicationOpenExternalURLOptionsKeyDictionary(_ input: [String: Any]) -> [UIApplication.OpenExternalURLOptionsKey: Any] {
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (UIApplication.OpenExternalURLOptionsKey(rawValue: key), value)})
}

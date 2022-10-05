// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AVFoundation
import UIKit
import os
import ARKit
import FirebaseStorage
import FirebaseAuth
import Foundation
import ARDataLogger
import AudioToolbox

public struct PixelData {
    var a: UInt8
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

extension UIImage {
    convenience init?(pixels: [PixelData], width: Int, height: Int) {
        guard width > 0 && height > 0, pixels.count == width * height else { return nil }
        var data = pixels
        guard let providerRef = CGDataProvider(data: Data(bytes: &data, count: data.count * MemoryLayout<PixelData>.size) as CFData)
            else { return nil }
        guard let cgim = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * MemoryLayout<PixelData>.size,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: providerRef,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
        else { return nil }
        self.init(cgImage: cgim)
    }
}


class ViewController: UIViewController, ARSCNViewDelegate {
    // MARK: Storyboards Connections
    let appStartTime = Date()
    var saidFirstAnnouncement = false
    var saidClutteredAnnouncement = false
    let calculateMIDAS = false
    let uploadData = false
    var meters = true
    var haptic = true
    var voice = true
    var closestObstacle: Float?
    
  @IBOutlet weak var previewView: ARSCNView!

  //@IBOutlet weak var overlayView: OverlayView!
  @IBOutlet weak var overlayView: UIImageView!
        
  private var imageView : UIImageView = UIImageView(frame:CGRect(x:0, y:0, width:400, height:400))
    
  private var imageViewInitialized: Bool = false

  @IBOutlet var unitsLabel: UILabel!
  @IBOutlet var meterButton: UIButton!
  @IBOutlet var feetButton: UIButton!
    
  @IBOutlet var hapticButton: UIButton!
  @IBOutlet var feedbackLabel: UILabel!
  @IBOutlet var voiceButton: UIButton!
    
  @IBOutlet weak var tableView: UITableView!

  @IBOutlet weak var threadCountLabel: UILabel!
  @IBOutlet weak var threadCountStepper: UIStepper!

  @IBOutlet weak var delegatesControl: UISegmentedControl!
  var sentData = false
  var lastFrameUploadTime = Date()
  
  // MARK: ModelDataHandler traits
  var threadCount: Int = Constants.defaultThreadCount
  var delegate: Delegates = Constants.defaultDelegate

  // MARK: Result Variables
  // Inferenced data to render.
  private var inferencedData: InferencedData?

  // Minimum score to render the result.
  private let minimumScore: Float = 0.5
    
  private var avg_latency: Double = 0.0

  // Relative location of `overlayView` to `previewView`.
  private var overlayViewFrame: CGRect?

  private var previewViewFrame: CGRect?

  // MARK: Controllers that manage functionality
  // Handles all the camera related functionality
  //private lazy var cameraCapture = CameraFeedManager(previewView: previewView)

  // Handles all data preprocessing and makes calls to run inference.
  private var modelDataHandler: ModelDataHandler?

  let configuration = ARWorldTrackingConfiguration()
    
  // MARK: View Handling Methods
  override func viewDidLoad() {
    super.viewDidLoad()
    setupARSession()
    do {
      modelDataHandler = try ModelDataHandler()
    } catch let error {
      fatalError(error.localizedDescription)
    }
      
    AnnouncementManager.shared.startHaptics()

    //cameraCapture.delegate = self
    //tableView.delegate = self
    //tableView.dataSource = self
      let hapticTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
          if let closestObstacle = self.closestObstacle, self.haptic == true {
              AnnouncementManager.shared.vibrate(intensity: min(1/(2 * (closestObstacle - 0.2)) + 0.1, 1))
          }
      }
    // MARK: UI Initialization
    // Setup thread count stepper with white color.
    // https://forums.developer.apple.com/thread/121495
      meterButton.backgroundColor = UIColor.white
      feetButton.backgroundColor = UIColor.lightGray
      hapticButton.backgroundColor = UIColor.white
      voiceButton.backgroundColor = UIColor.white
      unitsLabel.textColor = UIColor.white
      feedbackLabel.textColor = UIColor.white
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    //cameraCapture.checkCameraConfigurationAndStartSession()
  }

  override func viewWillDisappear(_ animated: Bool) {
    //cameraCapture.stopSession()
  }

  override func viewDidLayoutSubviews() {
    overlayViewFrame = overlayView.frame
    previewViewFrame = previewView.frame
  }
    
    
    @IBAction func hapticButtonTapped(_ sender: Any) {
        if haptic == false {
            haptic = true
            hapticButton.backgroundColor = UIColor.white
            AnnouncementManager.shared.announce(announcement: "Haptic feedback on.")
        }
        else {
            haptic = false
            hapticButton.backgroundColor = UIColor.lightGray
            AnnouncementManager.shared.announce(announcement: "Haptic feedback off.")
        }
    }
    
    @IBAction func voiceButtonTapped(_ sender: Any) {
        if voice == false {
            voice = true
            voiceButton.backgroundColor = UIColor.white
            AnnouncementManager.shared.announce(announcement: "Voice veedback on.")
        }
        else {
            voice = false
            voiceButton.backgroundColor = UIColor.lightGray
            AnnouncementManager.shared.announce(announcement: "Voice feedback off.")
        }
    }
    
    @IBAction func metersButtonTapped(_ sender: Any) {
        if meters == false {
            AnnouncementManager.shared.announce(announcement: "Switched units to meters")
            meters = true
            meterButton.backgroundColor = UIColor.white
            feetButton.backgroundColor = UIColor.lightGray
        }
    }
    
    @IBAction func feetButtonTapped(_ sender: Any) {
        if meters == true {
            AnnouncementManager.shared.announce(announcement: "Switched units to feet")
            meters = false
            meterButton.backgroundColor = UIColor.lightGray
            feetButton.backgroundColor = UIColor.white
        }
    }

    // MARK: Button Actions
  @IBAction func didChangeThreadCount(_ sender: UIStepper) {
    let changedCount = Int(sender.value)
    if threadCountLabel.text == changedCount.description {
      return
    }

    do {
      modelDataHandler = try ModelDataHandler(threadCount: changedCount, delegate: delegate)
    } catch let error {
      fatalError(error.localizedDescription)
    }
    threadCount = changedCount
    threadCountLabel.text = changedCount.description
    os_log("Thread count is changed to: %d", threadCount)
  }

  @IBAction func didChangeDelegate(_ sender: UISegmentedControl) {
    guard let changedDelegate = Delegates(rawValue: delegatesControl.selectedSegmentIndex) else {
      fatalError("Unexpected value from delegates segemented controller.")
    }
    do {
      modelDataHandler = try ModelDataHandler(threadCount: threadCount, delegate: changedDelegate)
    } catch let error {
      fatalError(error.localizedDescription)
    }
    delegate = changedDelegate
    os_log("Delegate is changed to: %s", delegate.description)
  }

  @IBAction func didTapResumeButton(_ sender: Any) {
//    cameraCapture.resumeInterruptedSession { complete in
//
//      if complete {
//        self.resumeButton.isHidden = true
//        self.cameraUnavailableLabel.isHidden = true
//      } else {
//        self.presentUnableToResumeSessionAlert()
//      }
//    }
  }
  func setupARSession(){
      ARDataLogger.ARLogger.shared.doAynchronousUploads = false
      ARDataLogger.ARLogger.shared.dataDir = "depth_benchmarking"
      ARDataLogger.ARLogger.shared.startTrial()
        //1. Set The AR Session
      previewView.delegate = self
      previewView.debugOptions = [.showFeaturePoints]
        
      configuration.planeDetection = [.horizontal, .vertical]
      if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
          configuration.frameSemantics = .sceneDepth
      }
      previewView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
      previewView.session.delegate = self
  }
  func presentUnableToResumeSessionAlert() {
    let alert = UIAlertController(
      title: "Unable to Resume Session",
      message: "There was an error while attempting to resume session.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))

    self.present(alert, animated: true)
  }
}

// MARK: - CameraFeedManagerDelegate Methods
extension ViewController: CameraFeedManagerDelegate {
  func cameraFeedManager(_ manager: CameraFeedManager, didOutput pixelBuffer: CVPixelBuffer) {
    runModel(on: pixelBuffer)
  }

  // MARK: Session Handling Alerts
  func cameraFeedManagerDidEncounterSessionRunTimeError(_ manager: CameraFeedManager) {
    // Handles session run time error by updating the UI and providing a button if session can be
    // manually resumed.
  }

  func cameraFeedManager(
    _ manager: CameraFeedManager, sessionWasInterrupted canResumeManually: Bool
  ) {

  }

  func cameraFeedManagerDidEndSessionInterruption(_ manager: CameraFeedManager) {

  }

  func presentVideoConfigurationErrorAlert(_ manager: CameraFeedManager) {
    let alertController = UIAlertController(
      title: "Confirguration Failed", message: "Configuration of camera has failed.",
      preferredStyle: .alert)
    let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
    alertController.addAction(okAction)

    present(alertController, animated: true, completion: nil)
  }

  func presentCameraPermissionsDeniedAlert(_ manager: CameraFeedManager) {
    let alertController = UIAlertController(
      title: "Camera Permissions Denied",
      message:
        "Camera permissions have been denied for this app. You can change this by going to Settings",
      preferredStyle: .alert)

    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    let settingsAction = UIAlertAction(title: "Settings", style: .default) { action in
      if let url = URL.init(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    }

    alertController.addAction(cancelAction)
    alertController.addAction(settingsAction)

    present(alertController, animated: true, completion: nil)
  }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // This visualization covers only detected planes.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        // Create a SceneKit plane to visualize the node using its position and extent.
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.z)

        // SCNPlanes are vertically oriented in their local coordinate space.
        // Rotate it to match the horizontal orientation of the ARPlaneAnchor.
        planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2, 1, 0, 0)
        planeNode.opacity = 0.4

        // ARKit owns the node corresponding to the anchor, so make the plane a child node.
        node.addChildNode(planeNode)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let planeNode = node.childNodes.first else {
            return
        }
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        planeNode.geometry = plane
        planeNode.position = SCNVector3Make(planeAnchor.center.x, 0, planeAnchor.center.z)
    }

  @objc func runModel(on pixelBuffer: CVPixelBuffer)->[Float]? {
    guard let overlayViewFrame = overlayViewFrame, let previewViewFrame = previewViewFrame
    else {
      return nil
    }
    // To put `overlayView` area as model input, transform `overlayViewFrame` following transform
    // from `previewView` to `pixelBuffer`. `previewView` area is transformed to fit in
    // `pixelBuffer`, because `pixelBuffer` as a camera output is resized to fill `previewView`.
    // https://developer.apple.com/documentation/avfoundation/avlayervideogravity/1385607-resizeaspectfill
    let modelInputRange = overlayViewFrame.applying(
      previewViewFrame.size.transformKeepAspect(toFitIn: pixelBuffer.size))

    // Run Midas model.
    guard
      let (result, width, height, times) = self.modelDataHandler?.runMidas(
        on: pixelBuffer,
        from: modelInputRange,
        to: overlayViewFrame.size)
    else {
      os_log("Cannot get inference result.", type: .error)
      return nil
    }

    if avg_latency == 0 {
        avg_latency = times.inference
    } else {
        avg_latency = times.inference*0.1 + avg_latency*0.9
    }
    
    // Udpate `inferencedData` to render data in `tableView`.
    inferencedData = InferencedData(score: Float(avg_latency), times: times)
    
    //let height = 256
    //let width = 256
    
    let outputs = result
    let outputs_size = width * height;
      
    var multiplier : Float = 1.0;
    
    let max_val : Float = outputs.max() ?? 0
    let min_val : Float = outputs.min() ?? 0
    
    if((max_val - min_val) > 0) {
        multiplier = 255 / (max_val - min_val);
    }
    
    // Draw result.
    DispatchQueue.main.async {
      self.tableView.reloadData()
                        
        var pixels: [PixelData] = .init(repeating: .init(a: 255, r: 0, g: 0, b: 0), count: width * height)
             
        for i in pixels.indices {
        //if(i < 1000)
        //{
            let val = UInt8((outputs[i] - min_val) * multiplier)
            
            pixels[i].r = val
            pixels[i].g = val
            pixels[i].b = val
        //}
        }
        
        
        /*
           pixels[i].a = 255
           pixels[i].r = .random(in: 0...255)
           pixels[i].g = .random(in: 0...255)
           pixels[i].b = .random(in: 0...255)
        }
        */
        
        DispatchQueue.main.async {
            let image = UIImage(pixels: pixels, width: width, height: height)

            self.imageView.image = image
            
            if (self.imageViewInitialized == false) {
                self.imageViewInitialized = true
                self.overlayView.addSubview(self.imageView)
                self.overlayView.setNeedsDisplay()
            }
        }
        
        /*
        let image = UIImage(pixels: pixels, width: width, height: height)
        
        var imageView : UIImageView
        imageView  = UIImageView(frame:CGRect(x:0, y:0, width:400, height:400));
        imageView.image = image
        self.overlayView.addSubview(imageView)
        self.overlayView.setNeedsDisplay()
        */
    }
      return result
  }
/*
  func drawResult(of result: Result) {
    self.overlayView.dots = result.dots
    self.overlayView.lines = result.lines
    self.overlayView.setNeedsDisplay()
  }

  func clearResult() {
    self.overlayView.clear()
    self.overlayView.setNeedsDisplay()
  }
    */
    
}


// MARK: - TableViewDelegate, TableViewDataSource Methods
extension ViewController: UITableViewDelegate, UITableViewDataSource {
  func numberOfSections(in tableView: UITableView) -> Int {
    return InferenceSections.allCases.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let section = InferenceSections(rawValue: section) else {
      return 0
    }

    return section.subcaseCount
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell") as! InfoCell
    guard let section = InferenceSections(rawValue: indexPath.section) else {
      return cell
    }
    guard let data = inferencedData else { return cell }

    var fieldName: String
    var info: String

    switch section {
    case .Score:
      fieldName = section.description
      info = String(format: "%.3f", data.score)
    case .Time:
      guard let row = ProcessingTimes(rawValue: indexPath.row) else {
        return cell
      }
      var time: Double
      switch row {
      case .InferenceTime:
        time = data.times.inference
      }
      fieldName = row.description
      info = String(format: "%.2fms", time)
    }

    cell.fieldNameLabel.text = fieldName
    cell.infoLabel.text = info

    return cell
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    guard let section = InferenceSections(rawValue: indexPath.section) else {
      return 0
    }

    var height = Traits.normalCellHeight
    if indexPath.row == section.subcaseCount - 1 {
      height = Traits.separatorCellHeight + Traits.bottomSpacing
    }
    return height
  }

}

// MARK: - Private enums
/// UI coinstraint values
fileprivate enum Traits {
  static let normalCellHeight: CGFloat = 35.0
  static let separatorCellHeight: CGFloat = 25.0
  static let bottomSpacing: CGFloat = 30.0
}

fileprivate struct InferencedData {
  var score: Float
  var times: Times
}

/// Type of sections in Info Cell
fileprivate enum InferenceSections: Int, CaseIterable {
  case Score
  case Time

  var description: String {
    switch self {
    case .Score:
      return "Average"
    case .Time:
      return "Processing Time"
    }
  }

  var subcaseCount: Int {
    switch self {
    case .Score:
      return 1
    case .Time:
      return ProcessingTimes.allCases.count
    }
  }
}

/// Type of processing times in Time section in Info Cell
fileprivate enum ProcessingTimes: Int, CaseIterable {
  case InferenceTime

  var description: String {
    switch self {
    case .InferenceTime:
      return "Inference Time"
    }
  }
}

/// Filters planes based on the classification type
extension ARPlaneAnchor.Classification {
    var description: String {
            switch self {
            case .wall:
                return "wall"
            case .floor:
                return "floor"
            case .ceiling:
                return "ceiling"
            case .table:
                return "table"
            case .seat:
                return "seat"
            case .door:
                return "door"
            case .window:
                return "window"
            default:
                return "object"
            }
        }
}


extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        ARDataLogger.ARLogger.shared.session(session, didUpdate: frame)
        if !saidFirstAnnouncement {
            let supportLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            if !supportLiDAR {
                let lidarNotAvailableAlert = UIAlertController(title: "LiDAR Not Available", message: "Object detection will not work on your device", preferredStyle: UIAlertController.Style.alert)
                lidarNotAvailableAlert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
                self.present(lidarNotAvailableAlert, animated: true, completion: nil)
                AnnouncementManager.shared.announce(announcement: "Warning. Your device is not equipped with a LiDAR sensor. Object detection is not available.")
            }
            else{
                AnnouncementManager.shared.announce(announcement: "Announcing object distances from camera in meters. Press meter or feet button to switch units. Press haptic or voice button to customize feedback.")
            }
            saidFirstAnnouncement = true
        }
        if -lastFrameUploadTime.timeIntervalSinceNow > 0.75 {
            print("getting the cloud")
            if let logFrame = ARDataLogger.ARLogger.shared.toLogFrame(frame: frame, type: "", meshLoggingBehavior: .none) {
                let planes = frame.anchors.compactMap({ $0 as? ARPlaneAnchor })
                let truePointCloud = getTrueLidarPointCloud(logFrame: logFrame, planes: planes)
                let pointCloudGlobalFrame = getGlobalPointCloud(logFrame: logFrame, truePointCloud: truePointCloud)
                let filteredPointCloud = isolateObstacles(logFrame: logFrame, yawAdjustedPointCloud: pointCloudGlobalFrame)
                print("filtered point cloud size: \(filteredPointCloud.count)")
                let obstacles = findObstacles(filteredPointCloud:filteredPointCloud)
                if obstacles.count > 3 {
                    if !saidClutteredAnnouncement{
                        AnnouncementManager.shared.announce(announcement: "Warning. You are in a cluttered environment. Obstacle detection accuracy will be low.")
                        saidClutteredAnnouncement = true
                    }
                    else{
                        AnnouncementManager.shared.announce(announcement: "Warning. Cluttered environment.")
                    }
                }
                else {
                    self.closestObstacle = obstacles.min()
                    if let closestObstacle = closestObstacle {
                        if Date().timeIntervalSince(appStartTime) > 4{
                            if voice == true{
                                if meters == true{
                                    AnnouncementManager.shared.announce(announcement: "\(round(closestObstacle * 10) / 10.0)")
                                }
                                else {
                                    AnnouncementManager.shared.announce(announcement: "\(round(closestObstacle * 10 * 3.28) / 10.0)")
                                }
                            }
                        }
                    }
                }
            }
            lastFrameUploadTime = Date()
            if calculateMIDAS {
                do {
                    let convertedImage = try AECapturedTools(frame: frame)
                    if let rgbBuffer = convertedImage.rgbPixel, let results = runModel(on: rgbBuffer) {
                        print(CVPixelBufferGetPixelFormatName(pixelBuffer: rgbBuffer))
                    }
                } catch {
                    print("error converting image")
                }
            }
            if uploadData {
                ARDataLogger.ARLogger.shared.log(frame: frame, withType: "depth_benchmarking", withMeshLoggingBehavior: .none)
            }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        ARDataLogger.ARLogger.shared.session(session, didAdd: anchors)
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        ARDataLogger.ARLogger.shared.session(session, didUpdate: anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        ARDataLogger.ARLogger.shared.session(session, didRemove: anchors)
    }
}

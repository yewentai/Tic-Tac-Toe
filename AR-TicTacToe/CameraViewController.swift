/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's main view controller object.
*/

import UIKit
import AVFoundation
import Vision
import SceneKit
import ARKit
import CoreML

class CameraViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
    
    // UI
    @IBOutlet weak var planeSearchLabel: UILabel!
    @IBOutlet weak var planeSearchOverlay: UIView!
    @IBOutlet weak var gameStateLabel: UILabel!
    @IBAction func didTapStartOver(_ sender: Any) { reset() }
    
    /** create an ARSCNView and for view AR view assignment and loading in ViewController */
    @IBOutlet weak var sceneView: ARSCNView!
    
    // Haptic Feedback Generators
    let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    // State
    private func updatePlaneOverlay() {
        DispatchQueue.main.async {
            self.planeSearchOverlay.isHidden = self.currentPlane != nil
            if self.planeCount == 0 {
                self.planeSearchLabel.text = "Move around to allow the app the find a plane..."
            } else {
                self.planeSearchLabel.text = "Tap on a plane surface to place board..."
            }
        }
    }
    var playerType = [
        GamePlayer.x: GamePlayerType.human,
        GamePlayer.o: GamePlayerType.ai
    ]
    var planeCount = 0 {
        didSet {
            updatePlaneOverlay()
        }
    }
    var currentPlane:SCNNode? {
        didSet {
            updatePlaneOverlay()
            newTurn()
        }
    }
    let board = Board()
    var game:GameState! {
        didSet {
            gameStateLabel.text = game.currentPlayer.rawValue + ":" + playerType[game.currentPlayer]!.rawValue.uppercased() + " to " + game.mode.rawValue
            
            if let winner = game.currentWinner {
                let alert = UIAlertController(title: "Game Over", message: "\(winner.rawValue) wins!!!!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
                    self.reset()
                }))
                present(alert, animated: true, completion: nil)
            } else {
                if currentPlane != nil {
                    newTurn()
                }
            }
        }
    }
    var figures:[String:SCNNode] = [:]
    var lightNode:SCNNode?
    var floorNode:SCNNode?
    var draggingFrom:GamePosition? = nil
    var draggingFromPosition:SCNVector3? = nil
    
    private var currentBuffer: CVPixelBuffer?
    private var lastInteractionDetails: (node: SCNNode, initialPosition: SCNVector3, initialSquare: (Int, Int))?
    let handDetector = HandDetector()
    let touchNode = TouchNode()
    var previewView = UIImageView()
    
    private let videoDataOutputQueue = DispatchQueue(label: "CameraFeedDataOutput", qos: .userInteractive)
    private var cameraFeedSession: AVCaptureSession?
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    
    private var evidenceBuffer = [HandGestureProcessor.PointsPair]()
    private var lastObservationTimestamp = Date()
    
    private var gestureProcessor = HandGestureProcessor()
    
    // MARK: - Configuration
    override func viewDidLoad() {
        super.viewDidLoad()
        game = GameState()
        sceneView.delegate = self
        setupGestureRecognizers()
        configureLighting()
        prepareFeedbackGenerators()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        /** create a session configuration */
        configureARSession()
        /** subview for hand gesture */
        sceneView.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraFeedSession?.stopRunning()
        sceneView.session.pause()
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(panGesture)
        
        handPoseRequest.maximumHandCount = 1
        // Add state change handler to hand gesture processor.
        gestureProcessor.didChangeStateClosure = { [weak self] state in
            self?.handleGestureStateChange(state: state)
        }
    }
    
    private func configureLighting() {
        sceneView.automaticallyUpdatesLighting = false
        sceneView.antialiasingMode = .multisampling4X
    }
    
    private func prepareFeedbackGenerators() {
        selectionFeedbackGenerator.prepare()
        impactFeedbackGenerator.prepare()
    }
    
    private func configureARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        sceneView.session.delegate = self
        sceneView.session.run(configuration)
    }
    
    func setupAVSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            self.gameStateLabel.text = ("Could not find a rear facing camera.")
            return
        }
        guard let deviceInput = try? AVCaptureDeviceInput(device: camera) else {
            self.gameStateLabel.text = ("Could not create video device input.")
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = AVCaptureSession.Preset.high
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            self.gameStateLabel.text = ("Could not add video device input to the session")
            return
        }
        session.addInput(deviceInput)
        
        let dataOutput = AVCaptureVideoDataOutput()
        if session.canAddOutput(dataOutput) {
            session.addOutput(dataOutput)
            // Add a video data output.
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            dataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            self.gameStateLabel.text = ("Could not add video data output to the session")
        }
        session.commitConfiguration()
        cameraFeedSession = session
    }
    
    // MARK: - GameState Management
    private func beginNewGame(_ players:[GamePlayer:GamePlayerType]) {
        playerType = players
        game = GameState()
        removeAllFigures()
        figures.removeAll()
    }
    
    private func removeAllFigures() {
        for (_, figure) in figures {
            figure.removeFromParentNode()
        }
    }
    
    // Reset the game to the initial state
    private func reset() {
        let alert = UIAlertController(title: "Game type", message: "Choose players", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "x:HUMAN vs o:AI", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.human,
                GamePlayer.o: GamePlayerType.ai
            ])
        }))
        alert.addAction(UIAlertAction(title: "x:HUMAN vs o:HUMAN", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.human,
                GamePlayer.o: GamePlayerType.human
            ])
        }))
        alert.addAction(UIAlertAction(title: "x:AI vs o:AI", style: .default, handler: { action in
            self.beginNewGame([
                GamePlayer.x: GamePlayerType.ai,
                GamePlayer.o: GamePlayerType.ai
            ])
        }))
        present(alert, animated: true, completion: nil)
    }
    
    // Method to start a new turn based on the current game state
    private func newTurn() {
        if playerType[game.currentPlayer] == .ai {
            // AI's turn to play
            DispatchQueue.global(qos: .background).async {
                let action = GameAI(game: self.game).bestAction
                DispatchQueue.main.async {
                    guard let newGameState = self.game.perform(action: action) else { fatalError("AI generated invalid action") }
                    self.updateUIForGameState(newGameState) {
                        self.animateGameAction(action, completionHandler: {
                            DispatchQueue.main.async {
                                self.game = newGameState
                            }
                        })
                    }
                }
            }
        } else {
            // Human's turn to play
            if game.mode == .move {
                // If it is human's turn and the mode is 'move', we enable hand detection
                gameStateLabel.text = "finger detection mode"
            }
        }
    }
    // Method to update UI based on the game state changes
    private func updateUIForGameState(_ state: GameState, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            // Update any relevant UI components here
            self.gameStateLabel.text = "\(state.currentPlayer.rawValue): Move"
            completion()
        }
    }
    // Method to handle animations for game actions
    private func animateGameAction(_ action: GameAction, completionHandler: @escaping () -> Void) {
        switch action {
        case .put(let position):
            self.put(piece: Figure.figure(for: self.game.currentPlayer), at: position, completionHandler: completionHandler)
        case .move(let from, let to):
            self.move(from: from, to: to, completionHandler: completionHandler)
        case .remove(from: let from):
            // If removing a piece, animate the removal (e.g., fading out)
            if let piece = figures["\(from.x)x\(from.y)"] {
                let fadeOutAction = SCNAction.fadeOut(duration: 0.5)
                piece.runAction(fadeOutAction) {
                    // After animation completes, remove the piece from the scene and dictionary
                    piece.removeFromParentNode()
                    self.figures.removeValue(forKey: "\(from.x)x\(from.y)")
                    completionHandler()
                }
            } else {
                completionHandler()  // Ensure callback is called even if no piece found
            }
        }
    }
    
    private func restoreGame(at position:SCNVector3) {
        board.node.position = position
        sceneView.scene.rootNode.addChildNode(board.node)
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowRadius = 200
        light.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        light.shadowMode = .deferred
        let constraint = SCNLookAtConstraint(target: board.node)
        lightNode = SCNNode()
        lightNode!.light = light
        lightNode!.position = SCNVector3(position.x + 10, position.y + 10, position.z)
        lightNode!.constraints = [constraint]
        sceneView.scene.rootNode.addChildNode(lightNode!)
        for (key, figure) in figures {
            // yeah yeah, I know I should turn GamePosition into a struct and provide it with
            // Equtable and Hashable then this stupid stringy stuff would be gone. Will do this eventually
            let xyComponents = key.components(separatedBy: "x")
            guard xyComponents.count == 2,
                  let x = Int(xyComponents[0]),
                  let y = Int(xyComponents[1]) else { fatalError() }
            put(piece: figure,
                at: (x: x,
                     y: y))
        }
    }
    
    // MARK: - Gestures
    
    @objc func didPan(_ sender:UIPanGestureRecognizer) {
        guard case .move = game.mode,
              playerType[game.currentPlayer]! == .human else { return }
        
        let location = sender.location(in: sceneView)
        
        switch sender.state {
        case .began:
            print("begin \(location)")
            guard let square = squareFrom(location: location) else { return }
            draggingFrom = (x: square.0.0, y: square.0.1)
            draggingFromPosition = square.1.position
            
        case .cancelled:
            print("cancelled \(location)")
            revertDrag()
            
        case .changed:
            print("changed \(location)")
            guard let draggingFrom = draggingFrom,
                  let groundPosition = groundPositionFrom(location: location) else { return }
            
            let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z), duration: 0.1)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
        case .ended:
            print("ended \(location)")
            
            guard let draggingFrom = draggingFrom,
                  let square = squareFrom(location: location),
                  square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y,
                  let newGameState = game.perform(action: .move(from: draggingFrom, to: (x: square.0.0, y: square.0.1)))
            else { revertDrag()
                return
            }
            
            // move in visual model
            let toSquareId = "\(square.0.0)x\(square.0.1)"
            figures[toSquareId] = figures["\(draggingFrom.x)x\(draggingFrom.y)"]
            figures["\(draggingFrom.x)x\(draggingFrom.y)"] = nil
            self.draggingFrom = nil
            
            // copy pasted insert thingie
            let newPosition = sceneView.scene.rootNode.convertPosition(square.1.position, from: square.1.parent)
            let action = SCNAction.move(to: newPosition, duration: 0.1)
            figures[toSquareId]?.runAction(action) {
                DispatchQueue.main.async {
                    self.game = newGameState
                }
            }
            
        case .failed:
            print("failed \(location)")
            revertDrag()
            
        default: break
        }
    }
    
    @objc func didTap(_ sender:UITapGestureRecognizer) {
        let location = sender.location(in: sceneView)
        
        // tap to place board..
        guard let _ = currentPlane else {
            guard let newPlaneData = anyPlaneFrom(location: location) else { return }
            
            let floor = SCNFloor()
            floor.reflectivity = 0
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.colorBufferWriteMask = SCNColorMask(rawValue: 0)
            floor.materials = [material]
            
            floorNode = SCNNode(geometry: floor)
            floorNode!.position = newPlaneData.1
            sceneView.scene.rootNode.addChildNode(floorNode!)
            
            self.currentPlane = newPlaneData.0
            restoreGame(at: newPlaneData.1)
            
            return
        }
        
        // otherwise tap to place board piece.. (if we're in "put" mode)
        guard case .put = game.mode,
              playerType[game.currentPlayer]! == .human else { return }
        
        if let squareData = squareFrom(location: location),
           let newGameState = game.perform(action: .put(at: (x: squareData.0.0, y: squareData.0.1))) {
            put(piece: Figure.figure(for: game.currentPlayer),
                at: squareData.0) {
                DispatchQueue.main.async {
                    self.game = newGameState
                }
            }
        }
    }
    
    private func move(from:GamePosition, to:GamePosition, completionHandler: (() -> Void)? = nil) {
        
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        guard let piece = figures[fromSquareId],
              let rawDestinationPosition = board.squareToPosition[toSquareId]  else { fatalError() }
        
        // this stuff will change once we stop putting nodes directly in world space..
        let destinationPosition = sceneView.scene.rootNode.convertPosition(rawDestinationPosition, from: board.node)
        
        // update visual game state
        figures[toSquareId] = piece
        figures[fromSquareId] = nil
        
        // create drag and drop animation
        let pickUpAction = SCNAction.move(to: SCNVector3(piece.position.x, piece.position.y + Float(Dimensions.DRAG_LIFTOFF), piece.position.z), duration: 0.25)
        let moveAction = SCNAction.move(to: SCNVector3(destinationPosition.x, destinationPosition.y + Float(Dimensions.DRAG_LIFTOFF), destinationPosition.z), duration: 0.5)
        let dropDownAction = SCNAction.move(to: destinationPosition, duration: 0.25)
        
        // run drag and drop animation
        piece.runAction(pickUpAction) {
            piece.runAction(moveAction) {
                piece.runAction(dropDownAction, completionHandler: completionHandler)
            }
        }
    }
    
    private func put(piece:SCNNode, at position:GamePosition, completionHandler: (() -> Void)? = nil) {
        let squareId = "\(position.x)x\(position.y)"
        guard let squarePosition = board.squareToPosition[squareId] else { fatalError() }
        
        piece.opacity = 0  // initially invisible
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition, from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures[squareId] = piece
        
        let action = SCNAction.fadeIn(duration: 0.5)
        piece.runAction(action, completionHandler: completionHandler)
    }
    
    private func revertDrag() {
        if let draggingFrom = draggingFrom {
            
            let restorePosition = sceneView.scene.rootNode.convertPosition(draggingFromPosition!, from: board.node)
            let action = SCNAction.move(to: restorePosition, duration: 0.3)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
            self.draggingFrom = nil
            self.draggingFromPosition = nil
        }
    }
    
    private func handleGestureStateChange(state: HandGestureProcessor.State) {
        let pointsPair = gestureProcessor.lastProcessedPointsPair
        switch state {
        case .possiblePinch, .possibleApart:
            // "possible": states, collect points in the evidence buffer
            evidenceBuffer.append(pointsPair)
            // show on game label
            self.gameStateLabel.text = "Possible Pinch"
        case .pinched:
            // The user is performing a pinch gesture
            self.gameStateLabel.text = "Pinch State Processing"
            DispatchQueue.main.async {
                self.handlePinchGesture()
            }
        case .apart, .unknown:
            // stopped. Discard any evidence buffer points.
            evidenceBuffer.removeAll()
        }
    }
    
    private func handlePinchGesture() {
        // Check if it's the human's turn
        guard case .move = game.mode, playerType[game.currentPlayer]! == .human else { return }
        // Interact with the game piece
        // for each buffer point in the evidence buffer check interaction with the game piece and the board
        for pointsPair in evidenceBuffer {
            // Calculate the mid-point between the thumb tip and the index tip
            let midPoint = CGPoint.midPoint(p1: pointsPair.thumbTip, p2: pointsPair.indexTip)
            // Convert the mid-point to a 3D point in the AR scene
            guard let midPoint3D = groundPositionFrom(location: midPoint) else { return }
            // Check if the mid-point is within the board
            if let newPosition = board.positionToGamePosition(midPoint3D) {
                // Check if the mid-point interact with a game piece on the board
                if let gamePiece = findGamePieceAt(midPoint3D) {
                    // Original gamePiece game position (row, col)
                    let initialPosition = board.nodeToSquare[gamePiece]!
                    // Move the game piece to the new 3D position
                    moveGamePiece(gamePiece, to: midPoint3D)
                    // Move further to algin new position to node cell on board
                    updateGameState(from: initialPosition, to: newPosition)
                }
            }
            // Do nothing if the mid-point is outside of the baord
        }
        // Clear the evidence buffer.
        evidenceBuffer.removeAll()
    }
    
    // MARK: - Utilities
    
    func updateGameState(from initial: GamePosition, to final: GamePosition) {
        if let newGameState = game.perform(action: .move(from: initial, to: final)) {
            figures["\(final.x)x\(final.y)"] = figures["\(initial.x)x\(initial.y)"]
            figures["\(initial.x)x\(initial.y)"] = nil
            // move further from random x y position to board cell
            let newPosition = sceneView.scene.rootNode.convertPosition(board.squareToPosition["\(final.x)x\(final.y)"]!, from: board.node)
            let action = SCNAction.move(to: newPosition, duration: 0.1)
            figures["\(final.x)x\(final.y)"]?.runAction(action)
            DispatchQueue.main.async {
                // update the game label
                self.gameStateLabel.text = ("Moved from: \(initial.x), \(initial.y) to: \(final.x), \(final.y)")
                self.game = newGameState
            }
        }
    }
    
    // Finds a game piece at the given 3D position using hit testing.
    func findGamePieceAt(_ position: SCNVector3) -> SCNNode? {
        // First, convert the 3D position to 2D screen coordinates
        let screenPosition = sceneView.projectPoint(position)
        let screenCGPoint = CGPoint(x: CGFloat(screenPosition.x), y: CGFloat(screenPosition.y))

        // Now, perform a hit test with these screen coordinates
        let hitResults = sceneView.hitTest(screenCGPoint, options: [SCNHitTestOption.searchMode : SCNHitTestSearchMode.all.rawValue])
        return hitResults.first(where: { $0.node.name == "O" || $0.node.name == "X" })?.node
    }

    
    // Moves the identified game piece to the new position.
    func moveGamePiece(_ gamePiece: SCNNode, to position: SCNVector3) {
        let action = SCNAction.move(to: position, duration: 0.1)
        gamePiece.runAction(action)
    }
    
    func processPoints(thumbTip: CGPoint?, indexTip: CGPoint?) {
        // Check that we have both points.
        guard let thumbPoint = thumbTip, let indexPoint = indexTip else {
            // If there were no observations for more than 2 seconds reset gesture processor.
            if Date().timeIntervalSince(lastObservationTimestamp) > 2 {
                gestureProcessor.reset()
            }
            return
        }
        // Convert points from AVFoundation coordinates to UIKit coordinates
        let screenSize = UIScreen.main.bounds.size
        let thumbPointConverted = CGPoint(x: thumbPoint.x * screenSize.width, y: (1 - thumbPoint.y) * screenSize.height)
        let indexPointConverted = CGPoint(x: indexPoint.x * screenSize.width, y: (1 - indexPoint.y) * screenSize.height)
        // Process new points
        gestureProcessor.processPointsPair((thumbPointConverted, indexPointConverted))
    }
    
    // MARK: - Transformations
    
    // Converts the midpoint to the corresponding 3D position in the AR scene using raycasting.
    func groundPositionFrom(location: CGPoint) -> SCNVector3? {
        guard let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) else { return nil }
        let results = sceneView.session.raycast(query)
        if let result = results.first {
            return SCNVector3.positionFromTransform(result.worldTransform)
        }
        return nil
    }
    
    private func anyPlaneFrom(location: CGPoint) -> (SCNNode, SCNVector3)? {
        guard let query = sceneView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal) else { return nil }
        // Perform the raycast query
        let results = sceneView.session.raycast(query)
        // Check if the raycast returned any results
        if let firstResult = results.first, let anchor = firstResult.anchor as? ARPlaneAnchor {
            // Obtain the SCNNode associated with the ARAnchor
            if let node = sceneView.node(for: anchor) {
                // Return the node and its position translated from the ARKit world transform
                return (node, SCNVector3.positionFromTransform(firstResult.worldTransform))
            }
        }
        return nil
    }
    
    // Handling 2D Touch (Tapping and Panning)
    private func squareFrom(location:CGPoint) -> ((Int, Int), SCNNode)? {
        guard let _ = currentPlane else { return nil }
        // HitTest to find the nodes at the tap/pan location
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false, SCNHitTestOption.rootNode: board.node])
        // Iterate over hit results to find a node that corresponds to a board square
        for result in hitResults {
            if let square = board.nodeToSquare[result.node] {
                return (square, result.node)
            }
        }
        return nil
    }
    // MARK: - ARSessionDelegate and Hand Gesture Integration
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    }

    // MARK: - ARSCNViewDelegate
    private func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }

    // Called when a new node has been mapped to an AR anchor
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            DispatchQueue.main.async {
                // Create a node to visualize the plane using the anchor's geometry
                let planeNode = SCNNode()
                let planeGeometry = ARSCNPlaneGeometry(device: renderer.device!)!
                planeGeometry.update(from: planeAnchor.geometry)
                planeGeometry.firstMaterial?.diffuse.contents = UIColor.blue.withAlphaComponent(0.5)
                planeNode.geometry = planeGeometry
                planeNode.eulerAngles.x = -.pi / 2  // Rotate to lie flat
                
                node.addChildNode(planeNode)
                
                // Optionally, remove the indicator after some time or after the board is placed
            }
        }
        planeCount += 1
    }


    // Called when an existing node has been updated with new AR data
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Handle updates to existing planes or nodes
        // This is often used to update the extent of detected planes.
    }

    // Called when a node has been removed from the scene
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if node == currentPlane {
            removeAllFigures()
            lightNode?.removeFromParentNode()
            lightNode = nil
            floorNode?.removeFromParentNode()
            floorNode = nil
            board.node.removeFromParentNode()
            currentPlane = nil
        }
        
        if planeCount > 0 {
            planeCount -= 1
        }
    }

    // Update the scene at each frame
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // If light estimation is enabled, update the intensity of the model's lights and the environment map
            if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var thumbTip: CGPoint?
        var indexTip: CGPoint?
        
        defer {
            DispatchQueue.main.sync {
                self.processPoints(thumbTip: thumbTip, indexTip: indexTip)
            }
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            // Perform VNDetectHumanHandPoseRequest
            try handler.perform([handPoseRequest])
            // Continue only when a hand was detected in the frame.
            guard let observation = handPoseRequest.results?.first else {
                return
            }
            // Get points for thumb and index finger.
            let thumbPoints = try observation.recognizedPoints(.thumb)
            let indexFingerPoints = try observation.recognizedPoints(.indexFinger)
            // Look for tip points.
            guard let thumbTipPoint = thumbPoints[.thumbTip], let indexTipPoint = indexFingerPoints[.indexTip] else {
                return
            }
            // Ignore low confidence points.
            guard thumbTipPoint.confidence > 0.3 && indexTipPoint.confidence > 0.3 else {
                return
            }
            // Convert points from Vision coordinates to AVFoundation coordinates.
            thumbTip = CGPoint(x: thumbTipPoint.location.x, y: 1 - thumbTipPoint.location.y)
            indexTip = CGPoint(x: indexTipPoint.location.x, y: 1 - indexTipPoint.location.y)
        } catch {
            cameraFeedSession?.stopRunning()
            self.gameStateLabel.text = ("CameraFeedSession Stopped")
        }
    }
}


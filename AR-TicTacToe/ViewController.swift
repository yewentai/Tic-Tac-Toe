//
//  ViewController.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/11/24.
//  Copyright © 2024 Jeffee. All rights reserved.
//
import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class ViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

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
    var recentVirtualObjectDistances = [CGFloat]()
    var previewView = UIImageView()
    

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
                performHandGestureDetection()
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
        sceneView.session.pause()
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(panGesture)
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

    // MARK: - Transformations
    
    func groundPositionFrom(location: CGPoint) -> SCNVector3? {
        /** Convert  2D Touch Coordinates to 3D Scene Coordinates */
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
    
    var currentBuffer: CVPixelBuffer?
    let handDetector = HandDetector()
    let touchNode = TouchNode()
    var lastInteractionDetails: (node: SCNNode, initialPosition: SCNVector3, initialSquare: (Int, Int))?

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else { return }
        currentBuffer = frame.capturedImage
        performHandGestureDetection()
    }
    
    func performHandGestureDetection() {
        // To avoid force unwrap in VNImageRequestHandler
        guard let buffer = currentBuffer else { return }
        handDetector.performDetection(inputBuffer: buffer) { [weak self] outputBuffer, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer {
                    self.currentBuffer = nil  // Reset the buffer for the next frame
                }
                guard let outBuffer = outputBuffer else {
                    self.gameStateLabel.text = ("No output buffer detected")
                    self.touchNode.isHidden = true
                    return
                }
                
                // Update preview image for debugging
                self.previewView.image = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
                self.previewView.isHidden = false
                
                if let tipPoint = outBuffer.searchTopPoint(){
                    // Get image coordinate using coreVideo functions from the normalized point
                    let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                    let currentFingerPosition = CGPoint(x: imageFingerPoint.x, y: imageFingerPoint.y)
                    self.gameStateLabel.text = ("Current Finger Position: \(imageFingerPoint)")

                    let hitResults = self.sceneView.hitTest(currentFingerPosition, options: [SCNHitTestOption.firstFoundOnly: false, SCNHitTestOption.rootNode: self.board.node])
                    
                    // Iterate over hit results to find a node that corresponds to a board square
                    for result in hitResults {
                        if let square = self.board.nodeToSquare[result.node] {
                            self.gameStateLabel.text = "finger and figure node detected"
                            // Position our touchNode slighlty above the plane (0.1cm).
                            self.touchNode.position = result.worldCoordinates
                            self.touchNode.position.y += 0.001
                            self.touchNode.isHidden = false
                            self.gameStateLabel.text = ("Touch node position updated to: \(self.touchNode.position)")
                            if self.touchNode.parent == nil {
                                self.sceneView.scene.rootNode.addChildNode(self.touchNode)
                                self.gameStateLabel.text = ("Touch node added to scene")
                            }
                            // Handling initial interaction setup
                            if self.lastInteractionDetails == nil {
                                self.lastInteractionDetails = (node: result.node, initialPosition: result.worldCoordinates, initialSquare: square)
                            }
                        }
                        // Handling end of interaction when the node is resting
                        if let details = self.lastInteractionDetails, result.node === details.node, result.node.physicsBody?.isResting ?? false {
                            let finalPosition = result.worldCoordinates
                            if let finalSquare = self.board.positionToGamePosition(finalPosition), details.initialSquare != finalSquare {
                                let fromKey = "\(details.initialSquare.0)x\(details.initialSquare.1)"
                                let toKey = "\(finalSquare.x)x\(finalSquare.y)"
                                self.figures[toKey] = self.figures[fromKey]
                                self.figures[fromKey] = nil
                                // Update game state
                                self.updateGameState(from: details.initialSquare, to: finalSquare)
                            }
                            // Clear the interaction details after processing
                            self.lastInteractionDetails = nil
                        }
                    }
                    
                }else{
                    self.gameStateLabel.text = ("No tip finger detected")
                    self.touchNode.isHidden = true
                    return
                }
            }
        }
    }
    
    func updateGameState(from initial: (Int, Int), to final: (Int, Int)) {
        let moveAction = GameAction.move(from: (x: initial.0, y: initial.1), to: (x: final.0, y: final.1))
        if let newGameState = game.perform(action: moveAction) {
            DispatchQueue.main.async {
                self.game = newGameState
            }
        }
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

/**
func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    planeCount += 1
}
 */
/**
func performHandGestureDetection() {
    // To avoid force unwrap in VNImageRequestHandler
    guard let buffer = currentBuffer else { return }
    handDetector.performDetection(inputBuffer: buffer) { outputBuffer, _ in
        // Here we are on a background thread
        var previewImage: UIImage?
        var normalizedFingerTip: CGPoint?
        defer {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.previewView.image = previewImage
                // Release currentBuffer when finished to allow processing next frame
                self.currentBuffer = nil
                self.touchNode.isHidden = true
                guard let tipPoint = normalizedFingerTip else {
                    return
                }
                
                // Get image coordinate using coreVideo functions from the normalized point
                let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                
                /** // HitTest to translate from 2D coordinates to 3D coordinates
                let hitTestResults = self.sceneView.hitTest(imageFingerPoint, types: .existingPlaneUsingExtent)
                guard let hitTestResult = hitTestResults.first else { return }
                 */
                // Perform hitTest to check interaction with SceneKit nodes
                let hitTestResults = self.sceneView.hitTest(CGPoint(x: imageFingerPoint.x, y: imageFingerPoint.y),
                                                            options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all])
                if let firstResult = hitTestResults.first, let square = self.board.nodeToSquare[firstResult.node]
                // Position our touchNode slighlty above the plane (0.1cm).
                self.touchNode.simdTransform = hitTestResult.worldTransform
                self.touchNode.position.y += 0.001
                self.touchNode.isHidden = false
            }
        }
        guard let outBuffer = outputBuffer else {
            return
        }
        
        // Create UIImage from CVPixelBuffer
        previewImage = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
        normalizedFingerTip = outBuffer.searchTopPoint()
    }
}
 */
/**
// Calculate and apply movement vector if there's a previous finger position
if let lastPos = self.lastFingerPosition {
    let dx = currentFingerPosition.x - lastPos.x
    let dy = currentFingerPosition.y - lastPos.y
    let movementVector = SCNVector3(x: Float(dx) * 0.8, y: 0, z: Float(dy) * 0.8) // Scale factor for sensitivity adjustment
    
    if let physicsBody = hitTestResult.node.physicsBody {
        physicsBody.applyForce(movementVector, asImpulse: true)
    }
}
// Update lastFingerPosition for the next frame
self.lastFingerPosition = currentFingerPosition

 */
/**
func calculateMovementVector(currentPosition: SCNVector3, lastPosition: SCNVector3?) -> SCNVector3 {
    guard let lastPos = lastPosition else { return SCNVector3Zero }
    return SCNVector3(x: currentPosition.x - lastPos.x, y: currentPosition.y - lastPos.y, z: currentPosition.z - lastPos.z)
}
*/


/**
    func performHandGestureDetection() {
        guard let buffer = currentBuffer else { return }
        handDetector.performDetection(inputBuffer: buffer) { [weak self] outputBuffer, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentBuffer = nil  // Always reset the buffer for the next frame
                guard let outBuffer = outputBuffer, let tipPoint = outBuffer.searchTopPoint() else {
                    self.touchNode.isHidden = true  // Hide if no detection
                    return
                }
                
                guard let outBuffer = outputBuffer, let tipPoint = outBuffer.searchTopPoint() else {
                    return
                }
                
                // Update preview image for debugging
                self.previewView.image = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
                self.previewView.isHidden = false  // Make sure it's visible
                
                // Convert normalized fingertip point to screen coordinates
                let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                let currentFingerPosition = CGPoint(x: imageFingerPoint.x, y: imageFingerPoint.y)
                
                // Perform a hit test at the converted point
                let hitTestResults = self.sceneView.hitTest(currentFingerPosition, options: nil)
                guard let hitTestResult = hitTestResults.first else {
                    self.previewView.isHidden = true
                    return }
                
                // Check if the node that was hit is part of the current game
                if let nodeName = hitTestResult.node.name, ["X", "O"].contains(nodeName) {
                    if hitTestResult.node.name == Figure.figure(for: self.game.currentPlayer).name {
                        self.touchNode.position = hitTestResult.worldCoordinates
                        if self.touchNode.parent == nil {
                            self.sceneView.scene.rootNode.addChildNode(self.touchNode)
                        }
                        // Handling initial interaction setup
                        if self.lastInteractionDetails == nil {
                            if let initialSquare = self.board.nodeToSquare[hitTestResult.node] {
                                self.lastInteractionDetails = (node: hitTestResult.node, initialPosition: hitTestResult.worldCoordinates, initialSquare: initialSquare)
                            }
                        }
                    }
                }// Handling end of interaction when the node is resting
                if let details = self.lastInteractionDetails, hitTestResult.node === details.node, hitTestResult.node.physicsBody?.isResting ?? false {
                    let finalPosition = hitTestResult.worldCoordinates
                    if let finalSquare = self.board.positionToGamePosition(finalPosition), details.initialSquare != finalSquare {
                        let fromKey = "\(details.initialSquare.0)x\(details.initialSquare.1)"
                        let toKey = "\(finalSquare.x)x\(finalSquare.y)"
                        self.figures[toKey] = self.figures[fromKey]
                        self.figures[fromKey] = nil
                        // Update game state
                        self.updateGameState(from: details.initialSquare, to: finalSquare)
                    }
                    // Clear the interaction details after processing
                    self.lastInteractionDetails = nil
                }
            }
        }
    }
    */

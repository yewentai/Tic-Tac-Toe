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
    private var figures:[String:SCNNode] = [:]
    private var lightNode:SCNNode?
    private var floorNode:SCNNode?
    private var draggingFrom:GamePosition? = nil
    private var draggingFromPosition:SCNVector3? = nil
    
    private var currentBuffer: CVPixelBuffer?
    private var lastInteractionDetails: (node: SCNNode, initialPosition: SCNVector3, initialSquare: (Int, Int))?
    let handDetector = HandDetector()
    let touchNode = TouchNode()
    var previewView = UIImageView()
    
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
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else { return }
        currentBuffer = frame.capturedImage
        performHandGestureDetection()
    }

    func performHandGestureDetection() {
        // To avoid force unwrap in VNImageRequestHandler
        guard let buffer = currentBuffer else { return }
        // Always show the touch node for debugging
        touchNode.isHidden = false
        // Perform hand gesture detection using the HandDetector class
        handDetector.performDetection(inputBuffer: buffer) { [weak self] outputBuffer, _ in
            // on Background thread for processing
            DispatchQueue.main.async {
                // 1. Unwrap self and output buffer
                guard let self = self else { return }
                // 2. reset the buffer for the next frame when finished (defer block)
                defer {
                    self.currentBuffer = nil  // Reset the buffer for the next frame
                }
                guard let outBuffer = outputBuffer else {
                    self.gameStateLabel.text = ("No output buffer detected")
                    return
                }
                // 3. Update preview image for debugging
                self.previewView.image = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
                self.previewView.isHidden = false
                // 4. Search for the top point of the hand
                if let tipPoint = outBuffer.searchTopPoint(){
                    // 6. Obtain the image coordinate using coreVideo functions from the normalized point
                    let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                    // update game label text with tip finger position rounded to integer
                    self.gameStateLabel.text = ("Tip finger position: \(Int(imageFingerPoint.x)), \(Int(imageFingerPoint.y))")
                    // 7. Check for interaction with SceneKit nodes (game pieces: Figure O and X on the board)
                    /**
                    let hitTestResults = self.sceneView.hitTest(CGPoint(x: imageFingerPoint.x, y: imageFingerPoint.y), options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all]) 
                    */
                    let hitTestResults = self.sceneView.hitTest(imageFingerPoint, options: [SCNHitTestOption.firstFoundOnly: false, SCNHitTestOption.rootNode: self.board.node])
                    // Iterate over hit results to find a node that corresponds to a board square
                    for result in hitTestResults {
                        if let finalSquare = self.board.nodeToSquare[result.node] {
                            // position the touch node slightly above the plane (0.1cm)
                            let finalPosition = result.worldCoordinates
                            self.touchNode.simdPosition = SIMD3<Float>(finalPosition.x, finalPosition.y, finalPosition.z)
                            self.touchNode.position.y += 0.001
                            // update game label text with the square position rounded to integer
                            self.gameStateLabel.text = ("Node detected at: \(finalSquare.0), \(finalSquare.1)")
                            // let force vector be the difference between the board node position and the tip point
                            let forceMultiplier: Float = 2.0  // Adjust this value to increase or decrease the force
                            var forceVector = SCNVector3(x: Float(finalPosition.x - self.board.node.position.x) * forceMultiplier, y: Float(finalPosition.y - self.board.node.position.y) * forceMultiplier, z: 0)
                            // Handling initial interaction setup
                            if self.lastInteractionDetails == nil {
                                self.lastInteractionDetails = (node: result.node, initialPosition: finalPosition, initialSquare: finalSquare)
                                // Provide haptic feedback on initial interaction
                                self.selectionFeedbackGenerator.selectionChanged()
                                self.impactFeedbackGenerator.impactOccurred()
                            } else{
                                // Handling end of interaction when the node is resting
                                if self.lastInteractionDetails?.node === result.node {
                                    // update game label text with the final position rounded to integer
                                    self.gameStateLabel.text = ("Node resting at: \(Int(finalPosition.x)), \(Int(finalPosition.y))")
                                    if self.lastInteractionDetails!.initialSquare != finalSquare {
                                        // Calculate the force vector based on the difference between the initial and final positions
                                        forceVector = SCNVector3(x: Float(finalPosition.x - self.lastInteractionDetails!.initialPosition.x) * forceMultiplier, y: Float(finalPosition.y - self.lastInteractionDetails!.initialPosition.y) * forceMultiplier, z: 0)
                                    }
                                }
                            }
                            // Let touchnode collide with the game piece to push it around
                            result.node.physicsBody?.applyForce(forceVector, asImpulse: true)
                            // Update game label text alerting the force applied
                            self.gameStateLabel.text = ("Force applied to node")
                            // Update the figures dictionary, game state, the UI, and the last interaction details
                            let fromKey = "\(self.lastInteractionDetails!.initialSquare.0)x\(self.lastInteractionDetails!.initialSquare.1)"
                            let toKey = "\(finalSquare.0)x\(finalSquare.1)"
                            self.figures[toKey] = self.figures[fromKey]
                            self.figures[fromKey] = nil
                            self.updateGameState(from: self.lastInteractionDetails!.initialSquare, to: finalSquare)
                            // Update the last interaction details for the next interaction
                            self.lastInteractionDetails = (node: result.node, initialPosition: finalPosition, initialSquare: finalSquare)
                            
                            break
                        }
                    }
                    // no interaction detected

                }
                // 5. If no tip finger detected, alert on game lable (show touch node for debugging)
                else{
                    self.gameStateLabel.text = ("No tip finger detected")
                    return
                }
            }
        }
    }
    
    func updateGameState(from initial: (Int, Int), to final: (Int, Int)) {
        // 13. Update the game state based on the initial and final square positions
        let moveAction = GameAction.move(from: (x: initial.0, y: initial.1), to: (x: final.0, y: final.1))
        if let newGameState = game.perform(action: moveAction) {
            let newPosition = sceneView.scene.rootNode.convertPosition(board.squareToPosition["\(final.0)x\(final.1)"]!, from: board.node)
            let action = SCNAction.move(to: newPosition, duration: 0.1)
            figures["\(final.0)x\(final.1)"]?.runAction(action)
            DispatchQueue.main.async {
                // update the game label
                self.gameStateLabel.text = ("Moved from: \(initial.0), \(initial.1) to: \(final.0), \(final.1)")
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


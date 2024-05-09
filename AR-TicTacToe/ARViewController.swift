//
//  ARViewController.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/9/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class ARViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {
    
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
    var game: GameState! {
        didSet {
            updateGameState(with: game)
        }
    }
    var figures:[String:SCNNode] = [:]
    var lightNode:SCNNode?
    var floorNode:SCNNode?
    var draggingFrom:GamePosition? = nil
    var draggingFromPosition:SCNVector3? = nil
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [CGFloat]()
    
    var previewView = UIImageView()
    
    override func viewDidLoad() {
        /** load the view */
        super.viewDidLoad()
        // Create new game
        game = GameState()
        // Prepare the generators (optional but helps reduce latency when triggering)
        selectionFeedbackGenerator.prepare()
        impactFeedbackGenerator.prepare()
        // The delegate is used to receive ARAnchors when they are detected.
        sceneView.delegate = self
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        sceneView.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        sceneView.addGestureRecognizer(pan)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        /** create a session configuration */
        let configuration = ARWorldTrackingConfiguration()
        // Enable Horizontal plane detection
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        // We want to receive the frames from the video
        sceneView.session.delegate = self
        sceneView.session.run(configuration)
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
    
    private func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
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
    
    private func beginNewGame(_ players:[GamePlayer:GamePlayerType]) {
        playerType = players
        game = GameState()
        removeAllFigures()
        figures.removeAll()
    }
    
    private func updateGameState(with newGameState: GameState) {
        DispatchQueue.main.async {
            // Update the UI to reflect the current game state.
            self.gameStateLabel.text = "\(newGameState.currentPlayer.rawValue): \(self.playerType[newGameState.currentPlayer]!.rawValue.uppercased()) to \(newGameState.mode.rawValue)"
            // Handle game completion scenario.
            if let winner = newGameState.currentWinner {
                self.handleGameEnd(withWinner: winner)
            } else {
                // Update game state
                self.game = newGameState
                // Prepare for the next player's turn if the game continues.
                if self.currentPlane != nil && self.playerType[newGameState.currentPlayer]! == .human {
                    self.newTurn()
                }
            }
        }
    }
    
    private func handleGameEnd(withWinner winner: GamePlayer) {
        let alert = UIAlertController(title: "Game Over", message: "\(winner.rawValue) wins!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.reset()
        }))
        present(alert, animated: true, completion: nil)
    }
    
    private func newTurn() {
        guard playerType[game.currentPlayer]! == .ai else { return }
        DispatchQueue.global(qos: .background).async {
            let action = GameAI(game: self.game).bestAction
            DispatchQueue.main.async {
                guard let newGameState = self.game.perform(action: action) else {
                    print("AI produced an invalid action")
                    return
                }
                self.animateAction(action, gameState: newGameState)
            }
        }
    }
    
    private func animateAction(_ action: GameAction, gameState: GameState) {
        switch action {
        case .put(let at):
            self.put(piece: Figure.figure(for: self.game.currentPlayer), at: at) {
                self.updateGameState(with: gameState)
            }
        case .move(let from, let to):
            self.movePiece(from: from, to: to) {
                self.updateGameState(with: gameState)
            }
        }
    }
    
    private func removeAllFigures() {
        for (_, figure) in figures {
            figure.removeFromParentNode()
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
        // Create a raycast query from the tap location, targeting the geometry of existing planes
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
    
    private func squareFrom(location:CGPoint) -> ((Int, Int), SCNNode)? {
        /** maps a 2D touch point to a specific square on the game board */
        guard let _ = currentPlane else { return nil }
        // To transform our 2D Screen coordinates to 3D screen coordinates we use hitTest function
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false, SCNHitTestOption.rootNode:       board.node])
        for result in hitResults {
            if let square = board.nodeToSquare[result.node] {
                return (square, result.node)
            }
        }
        return nil
    }
    
    private func sceneToGamePosition(_ position: SCNVector3) -> GamePosition? {
        /** Converting Scene Coordinates (SCNVector3) to Game Position */
        return board.positionToGamePosition(position)
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
    
    // MARK: - Unified Movement Function
    private func movePiece(from: GamePosition, to: GamePosition, completionHandler: (() -> Void)? = nil) {
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        guard let piece = figures[fromSquareId],
              let destinationPosition = board.squareToPosition[toSquareId] else {
            print("Failed to locate the piece or destination.")
            return
        }
        figures[toSquareId] = piece
        figures[fromSquareId] = nil
        // Adjust position slightly above the plane to avoid z-fighting
        let newPosition = SCNVector3(destinationPosition.x, destinationPosition.y + Float(Dimensions.DRAG_LIFTOFF), destinationPosition.z)
        let moveActions = SCNAction.sequence([
            SCNAction.move(to: newPosition, duration: 0.5),
            SCNAction.run { _ in completionHandler?() }
        ])
        piece.runAction(moveActions) {
            self.impactFeedbackGenerator.impactOccurred()
        }
    }
    
    private func completeMove(from: GamePosition, to: GamePosition) {
        if let newGameState = game.perform(action: .move(from: from, to: to)) {
            updateGameState(with: newGameState)
        }
    }
    
    /// Renders user and AI insert of piece with enhancements
    private func put(piece: SCNNode, at position: GamePosition, fadeInDuration: TimeInterval = 0.5, completionHandler: (() -> Void)? = nil) {
        let squareId = "\(position.x)x\(position.y)"
        guard let squarePosition = board.squareToPosition[squareId] else {
            fatalError("Failed to locate the position on the board.")
        }
        // Setup piece properties
        piece.opacity = 0
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition, from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures[squareId] = piece
        // Fade in the piece to give a smooth appearance on the board
        let fadeInAction = SCNAction.fadeIn(duration: fadeInDuration)
        piece.runAction(fadeInAction) {
            completionHandler?()
        }
    }
    
    // MARK: - Gesture Handling Modification
    @objc func didPan(_ sender: UIPanGestureRecognizer) {
        guard case .move = game.mode, playerType[game.currentPlayer]! == .human else { return }
        let location = sender.location(in: sceneView)

        switch sender.state {
        case .began:
            if let squareData = squareFrom(location: location) {
                draggingFrom = squareData.0
                draggingFromPosition = squareData.1.position
            }
        case .changed, .ended:
            if let newPosition = groundPositionFrom(location: location), let draggingFrom = draggingFrom {
                if let newGamePosition = board.positionToGamePosition(newPosition) {
                    movePiece(from: draggingFrom, to: newGamePosition) {
                        if sender.state == .ended {
                            self.completeMove(from: draggingFrom, to: newGamePosition)
                        }
                    }
                }
            }
        default:
            revertDrag()
        }
    }

    @objc func didTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: sceneView)
        // Handle initial plane setup if not already present
        if currentPlane == nil {
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
            currentPlane = newPlaneData.0
            restoreGame(at: newPlaneData.1)
            return
        }
        // Place piece if game mode allows
        if case .put = game.mode, playerType[game.currentPlayer]! == .human {
            if let squareData = squareFrom(location: location),
               let newGameState = game.perform(action: .put(at: (x: squareData.0.0, y: squareData.0.1))) {
                put(piece: Figure.figure(for: game.currentPlayer), at: squareData.0) {
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
                }
            }
        }
    }
    
    // MARK: - ARSessionDelegate and Hand Gesture Integration
    
    var currentBuffer: CVPixelBuffer?
    let handDetector = HandDetector()
    let touchNode = TouchNode()
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else { return }
        currentBuffer = frame.capturedImage
        performHandGestureDetection()
    }
    
    private func performHandGestureDetection() {
        guard let buffer = currentBuffer else { return }
        handDetector.performDetection(inputBuffer: buffer) { [weak self] outputBuffer, error in
            guard let strongSelf = self, let outputBuffer = outputBuffer, let tipPoint = outputBuffer.searchTopPoint() else { return }
            DispatchQueue.main.async {
                strongSelf.updateGamePiecePosition(with: tipPoint)
                strongSelf.currentBuffer = nil
            }
        }
    }
    
    private func updateGamePiecePosition(with tipPoint: CGPoint) {
        // Convert the normalized finger point to image coordinates
        let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(view.bounds.size.width), Int(view.bounds.size.height))
        
        // Compute near and far points to create a ray in 3D space
        let nearVector = SCNVector3(x: Float(imageFingerPoint.x), y: Float(imageFingerPoint.y), z: 0)
        let nearScenePoint = sceneView.unprojectPoint(nearVector)
        let farVector = SCNVector3(x: Float(imageFingerPoint.x), y: Float(imageFingerPoint.y), z: 1)
        let farScenePoint = sceneView.unprojectPoint(farVector)
        
        // Compute the view vector by subtracting the far point from the near point
        let viewVector = SCNVector3(x: farScenePoint.x - nearScenePoint.x,
                                    y: farScenePoint.y - nearScenePoint.y,
                                    z: farScenePoint.z - nearScenePoint.z)
        
        // Normalize the view vector
        let vectorLength = sqrt(viewVector.x * viewVector.x + viewVector.y * viewVector.y + viewVector.z * viewVector.z)
        let normalizedViewVector = SCNVector3(x: viewVector.x / vectorLength, y: viewVector.y / vectorLength, z: viewVector.z / vectorLength)
        
        // Use raycasting to find intersections with the board's plane
        let hitResults = sceneView.hitTest(CGPoint(x: CGFloat(imageFingerPoint.x), y: CGFloat(imageFingerPoint.y)), options: nil)
        if let hitResult = hitResults.first {
            // Ensure the hit node is part of the game board
            if let gamePosition = board.nodeToSquare[hitResult.node] {
                // Now use the actual GamePosition to simulate the game action
                movePiece(from: gamePosition, to: gamePosition) {
                    // After moving the piece, update the game state and check if it's the AI's turn
                    if let newGameState = self.game.perform(action: .move(from: gamePosition, to: gamePosition)) {
                        self.updateGameState(with: newGameState)
                    }
                }
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    // did at plane(?)
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // notified when the ARSCNView detects an ARAnchor with its assigned SCNNode
        planeCount += 1
    }
    
    // did update plane?
    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {

    }
    
    // did remove plane?
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
            // update lighting or other continuous effects here.
            if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
    
}


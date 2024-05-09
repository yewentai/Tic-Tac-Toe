//
//  ARViewController_Unified.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/10/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class ARViewController_Unified: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

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
        super.viewDidLoad()
        game = GameState()
        setupGestureRecognizers()
        configureLighting()
        prepareFeedbackGenerators()
        configureARSession()
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

    @objc func didTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: sceneView)
        handleInput(at: location)
    }

    @objc func didPan(_ sender: UIPanGestureRecognizer) {
        let location = sender.location(in: sceneView)
        handleInput(at: location, gestureState: sender.state)
    }

    private func handleInput(at point: CGPoint, gestureState: UIGestureRecognizer.State = .changed) {
        if let gamePosition = detectGamePosition(from: point), gestureState == .began || gestureState == .changed {
            // Determine if there's a piece at this position to start a move or to place a new piece
            let action: GameAction = game.mode == .put ? .put(at: gamePosition) : .move(from: draggingFrom ?? gamePosition, to: gamePosition)
            if gestureState == .began {
                draggingFrom = gamePosition
            } else if gestureState == .ended || gestureState == .changed {
                draggingFrom = nil
                if let newGameState = game.perform(action: action) {
                    animateAction(action, gameState: newGameState)
                }
            }
        }
    }

    // This function processes touch input to convert screen coordinates to game board coordinates
    private func detectGamePosition(from point: CGPoint) -> GamePosition? {
        let hitResults = sceneView.hitTest(point, types: [.featurePoint])
        if let hitResult = hitResults.first {
            let position = SCNVector3(hitResult.worldTransform.columns.3.x, hitResult.worldTransform.columns.3.y, hitResult.worldTransform.columns.3.z)
            return board.positionToGamePosition(position)
        }
        return nil
    }


    // Method to start a new turn based on the current game state
    private func newTurn() {
        guard let currentPlayerType = playerType[game.currentPlayer] else { return }
        if currentPlayerType == .ai {
            DispatchQueue.global(qos: .background).async {
                let action = GameAI(game: self.game).bestAction
                DispatchQueue.main.async {
                    if let newGameState = self.game.perform(action: action) {
                        self.animateAction(action, gameState: newGameState)
                    }
                }
            }
        }
    }
    
    // Animate the movement of game pieces
    func animateAction(_ action: GameAction, gameState: GameState) {
        DispatchQueue.main.async {
            switch action {
            case .move(let from, let to):
                self.movePiece(from: from, to: to) {
                    self.updateGameState(with: gameState)
                }
            case .put(let at):
                self.put(piece: Figure.figure(for: gameState.currentPlayer), at: at)
                self.updateGameState(with: gameState)
            }
        }
    }
    
    // General method to move a piece on the board
    private func movePiece(from: GamePosition, to: GamePosition, completionHandler: @escaping () -> Void) {
        guard let pieceNode = figures["\(from.x)x\(from.y)"],
              let destinationPosition = board.squareToPosition["\(to.x)x\(to.y)"] else {
            return
        }
        
        let moveAction = SCNAction.move(to: destinationPosition, duration: 0.5)
        pieceNode.runAction(moveAction) {
            self.figures.removeValue(forKey: "\(from.x)x\(from.y)")
            self.figures["\(to.x)x\(to.y)"] = pieceNode
            completionHandler()
        }
    }

    // Render user and AI insert of piece with enhancements
    func put(piece: SCNNode, at position: GamePosition) {
        guard let squarePosition = board.squareToPosition["\(position.x)x\(position.y)"] else { return }
        piece.opacity = 0
        piece.position = squarePosition
        sceneView.scene.rootNode.addChildNode(piece)
        figures["\(position.x)x\(position.y)"] = piece
        let fadeInAction = SCNAction.fadeIn(duration: 0.5)
        piece.runAction(fadeInAction)
    }


    private func updateGameState(with gameState: GameState) {
        DispatchQueue.main.async {
            self.updateGameStateLabel()
            if let winner = gameState.currentWinner {
                self.handleGameEnd(withWinner: winner)
            } else {
                self.game = gameState
                self.checkForAITurn()
            }
        }
    }
    
    private func updateGameStateLabel() {
        DispatchQueue.main.async {
            self.gameStateLabel.text = "\(self.game.currentPlayer.rawValue): \(self.playerType[self.game.currentPlayer]?.rawValue.uppercased() ?? "") to \(self.game.mode.rawValue)"
        }
    }

    private func checkForAITurn() {
        if playerType[game.currentPlayer]! == .ai {
            DispatchQueue.global(qos: .background).async {
                let action = GameAI(game: self.game).bestAction
                DispatchQueue.main.async {
                    if let newGameState = self.game.perform(action: action) {
                        self.updateGameState(with: newGameState)
                    }
                }
            }
        }
    }

    // Handle the end of the game and reset if necessary
    private func handleGameEnd(withWinner winner: GamePlayer) {
        let message = "\(winner.rawValue) wins!"
        let alert = UIAlertController(title: "Game Over", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reset", style: .default) { _ in
            self.reset()
        })
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }
    
    // Reset the game to the initial state
    private func reset() {
        figures.forEach { $1.removeFromParentNode() }
        figures.removeAll()
        game = GameState()
        updateGameStateLabel()
    }
    // MARK: - ARSessionDelegate and Hand Gesture Integration
    
    var currentBuffer: CVPixelBuffer?
    let handDetector = HandDetector()
    
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

    // Called when a new node has been mapped to an AR anchor
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let planeAnchor = anchor as? ARPlaneAnchor {
            let planeGeometry = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
            planeGeometry.materials.first?.diffuse.contents = UIColor.blue.withAlphaComponent(0.5)
            let planeNode = SCNNode(geometry: planeGeometry)
            planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
            planeNode.transform = SCNMatrix4MakeRotation(-Float.pi / 2, 1, 0, 0)
            node.addChildNode(planeNode)
            updatePlaneOverlay()
        }
    }

    // Called when an existing node has been updated with new AR data
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Handle updates to existing planes or nodes
        // This is often used to update the extent of detected planes.
    }

    // Called when a node has been removed from the scene
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        // Handle removal of nodes, such as when ARKit refines its understanding of the environment
    }

    // Update the scene at each frame
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // You might update lighting or other continuous effects here.
        DispatchQueue.main.async {
            self.updateLightingBasedOnEnvironment(renderer: renderer)
        }
    }

    // Update lighting in the scene based on environmental light estimation
    private func updateLightingBasedOnEnvironment(renderer: SCNSceneRenderer) {
        if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
            let ambientIntensity = lightEstimate.ambientIntensity
            let lightingEnvironment = sceneView.scene.lightingEnvironment
            lightingEnvironment.intensity = ambientIntensity / 50.0 // Adjust intensity to match ambient light
        }
    }
}



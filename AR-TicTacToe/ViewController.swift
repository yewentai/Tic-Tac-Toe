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
    
    // MARK: - UI Components
    // Label indicating the search for a plane in AR.
    @IBOutlet private weak var planeSearchLabel: UILabel!
    // Overlay view that appears while searching for planes.
    @IBOutlet private weak var planeSearchOverlay: UIView!
    // Displays current game state information.
    @IBOutlet private weak var gameStateLabel: UILabel!
    // The AR scene view where the game is rendered.
    @IBOutlet private weak var sceneView: ARSCNView!
    // Preview view for displaying processed images from hand gesture recognition.
    private var previewView = UIImageView()
    
    // Reset button to start a new game.
    @IBAction func didTapStartOver(_ sender: Any) { reset() }
    
    // MARK: - Haptic Feedback Generators
    // Provides a tactile response to selections.
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    // Provides a medium impact tactile response.
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)


    
    // MARK: - State and Data Management Variables
    // Maps players to their types (Human or AI).
    private var playerType = [
        GamePlayer.x: GamePlayerType.human,
        GamePlayer.o: GamePlayerType.ai
    ]
    // References the current plane detected in AR.
    private var currentPlane: SCNNode? {
        didSet {
            updatePlaneOverlay()
            newTurn()
        }
    }
    // Counts the number of detected planes.
    var planeCount = 0 {
        didSet {
            updatePlaneOverlay()
        }
    }
    private var game:GameState! {
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
    // Tracks nodes corresponding to game pieces.
    private var figures: [String: SCNNode] = [:]
    // Used to track initial positions for game interactions.
    private var draggingFrom: GamePosition? = nil
    private var draggingFromPosition: SCNVector3? = nil
    private var lightNode: SCNNode?
    private var floorNode: SCNNode?
    private var lastInteractionDetails: (node: SCNNode, initialPosition: SCNVector3, initialSquare: (Int, Int))?

    // MARK: - Session & Scene Management Variables
    private var currentBuffer: CVPixelBuffer?
    private var restingStateTimer: Timer?
    
    // MARK: - Constants
    // Game board instance managing board-related functionalities.
    let board = Board()
    // Hand gesture detection utility.
    let handDetector = HandDetector()
    // Visual node representing touch interactions.
    let touchNode = TouchNode()
    
    // MARK: - Configuration and Setup
    override func viewDidLoad() {
        super.viewDidLoad()
        game = GameState()
        sceneView.delegate = self
        configureLighting()
        prepareFeedbackGenerators()
        setupGestureRecognizers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // create a session configuration
        configureARSession()
        // subview for hand gesture
        sceneView.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    private func configureLighting() {
        sceneView.automaticallyUpdatesLighting = false
        sceneView.antialiasingMode = .multisampling4X
    }
    
    private func prepareFeedbackGenerators() {
        selectionFeedbackGenerator.prepare()
        impactFeedbackGenerator.prepare()
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(panGesture)
    }
    
    private func configureARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        sceneView.session.delegate = self
        sceneView.session.run(configuration)
    }
    
    // MARK: - UI Updates and Handlers
    // Updates the visibility of plane search overlays based on detected planes.
    private func updatePlaneOverlay() {
        DispatchQueue.main.async {
            self.planeSearchOverlay.isHidden = self.currentPlane != nil
            self.planeSearchLabel.text = self.planeCount == 0 ? "Move around to allow the app the find a plane..." : "Tap on a plane surface to place board..."
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
    
    // MARK: - GameState Management
    private func beginNewGame(_ players:[GamePlayer:GamePlayerType]) {
        playerType = players
        game = GameState()
        removeAllFigures()
    }
    
    // Removes all game figures from the scene.
    private func removeAllFigures() {
        for (_, figure) in figures {
            figure.removeFromParentNode()
        }
        figures.removeAll()
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
    
    // Initiates a new turn based on the current game state.
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
                performHandGestureDetection()
            }
        }
    }
    
    // Animates game actions such as piece placement and removal.
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
    
    // Restores the game by repositioning the board and readding pieces.
    private func restoreGame(at position: SCNVector3) {
        board.node.position = position
        sceneView.scene.rootNode.addChildNode(board.node)
        setupLightNode(at: position)
        for (key, figure) in figures {
            let components = key.components(separatedBy: "x").compactMap(Int.init)
            guard components.count == 2 else { fatalError("Invalid key format") }
            put(piece: figure, at: (x: components[0], y: components[1]))
        }
    }
    
    // Sets up directional lighting for the scene.
    private func setupLightNode(at position: SCNVector3) {
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        light.shadowRadius = 200
        light.shadowColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        light.shadowMode = .deferred
        lightNode = SCNNode()
        lightNode!.light = light
        lightNode!.position = SCNVector3(x: position.x + 10, y: position.y + 10, z: position.z)
        lightNode!.constraints = [SCNLookAtConstraint(target: board.node)]
        sceneView.scene.rootNode.addChildNode(lightNode!)
    }
    
    // MARK: - ARSCNViewDelegate
    // Responds to the addition of new AR nodes by visualizing detected planes.
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
    
    // Handles updates to existing AR nodes.
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // This method is often used to update the extent of detected planes.
    }
    
    // Cleans up after nodes are removed from the scene.
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if node == currentPlane {
            currentPlaneRemovedCleanup()
        }
        if planeCount > 0 {
            planeCount -= 1
        }
    }
    
    // Performs necessary cleanup when the current plane node is removed.
    private func currentPlaneRemovedCleanup() {
        removeAllFigures()
        lightNode?.removeFromParentNode()
        lightNode = nil
        floorNode?.removeFromParentNode()
        floorNode = nil
        board.node.removeFromParentNode()
        currentPlane = nil
    }
    
    // Updates the scene for each frame, adjusting lighting and checking game boundaries.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.checkGamePiecesBoundaries()
            self.adjustLightingBasedOnEnvironment()
        }
    }

    // Adjusts scene lighting based on the current light estimation.
    private func adjustLightingBasedOnEnvironment() {
        if let lightEstimate = sceneView.session.currentFrame?.lightEstimate {
            enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
        } else {
            enableEnvironmentMapWithIntensity(25)
        }
    }
    
    // MARK: - AR & SceneKit Interaction
    // Handles pan gestures to interact with game pieces.
    @objc func didPan(_ sender: UIPanGestureRecognizer) {
        guard case .move = game.mode, playerType[game.currentPlayer]! == .human else { return }
        handlePanGesture(sender)
    }

    // Processes pan gestures to move game pieces.
    private func handlePanGesture(_ sender: UIPanGestureRecognizer) {
        let location = sender.location(in: sceneView)
        switch sender.state {
        case .began:
            handleGestureBegan(at: location)
        case .cancelled:
            revertDrag()
        case .changed:
            handleGestureChanged(at: location)
        case .ended:
            handleGestureEnded(at: location)
        case .failed:
            revertDrag()
        default: break
        }
    }

    // Handles initial interaction with the game board at the start of a gesture.
    private func handleGestureBegan(at location: CGPoint) {
        guard let square = squareFrom(location: location) else { return }
        draggingFrom = (x: square.0.0, y: square.0.1)
        draggingFromPosition = square.1.position
    }

    // Updates the position of a game piece being dragged.
    private func handleGestureChanged(at location: CGPoint) {
        guard let draggingFrom = draggingFrom,
              let groundPosition = groundPositionFrom(location: location) else { return }
        let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z), duration: 0.1)
        figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
    }

    // Finalizes the position of a game piece after a drag operation.
    private func handleGestureEnded(at location: CGPoint) {
        guard let draggingFrom = draggingFrom,
              let square = squareFrom(location: location),
              square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y,
              let newGameState = game.perform(action: .move(from: draggingFrom, to: (x: square.0.0, y: square.0.1))) else {
            revertDrag()
            return
        }
        moveVisualGamePiece(from: draggingFrom, to: square.0, gameState: newGameState)
    }

    // Moves a game piece visually and updates the game state.
    private func moveVisualGamePiece(from: GamePosition, to: GamePosition, gameState: GameState) {
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        figures[toSquareId] = figures[fromSquareId]
        figures[fromSquareId] = nil
        let newPosition = sceneView.scene.rootNode.convertPosition(board.squareToPosition[toSquareId]!, from: board.node)
        let action = SCNAction.move(to: newPosition, duration: 0.1)
        figures[toSquareId]?.runAction(action) {
            DispatchQueue.main.async {
                self.game = gameState
            }
        }
        self.draggingFrom = nil
    }
    
    // Handles tap gestures to place game pieces or interact with the game board.
    @objc func didTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: sceneView)
        handleTapGesture(at: location)
    }

    // Processes tap gestures based on the current game state.
    private func handleTapGesture(at location: CGPoint) {
        guard let currentPlane = currentPlane else {
            attemptToPlaceBoard(at: location)
            return
        }
        if case .put = game.mode, playerType[game.currentPlayer]! == .human {
            attemptToPlaceGamePiece(at: location)
        }
    }

    // Attempts to place the game board if no current plane is detected.
    private func attemptToPlaceBoard(at location: CGPoint) {
        guard let newPlaneData = anyPlaneFrom(location: location) else { return }
        let floorNode = createFloorNode(at: newPlaneData.1)
        sceneView.scene.rootNode.addChildNode(floorNode)
        self.floorNode = floorNode
        self.currentPlane = newPlaneData.0
        restoreGame(at: newPlaneData.1)
    }

    // Creates a floor node for visualizing the detected plane.
    private func createFloorNode(at position: SCNVector3) -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.colorBufferWriteMask = SCNColorMask(rawValue: 0)
        floor.materials = [material]
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = position
        return floorNode
    }

    // Attempts to place a game piece based on the current player's turn.
    private func attemptToPlaceGamePiece(at location: CGPoint) {
        guard let squareData = squareFrom(location: location),
              let newGameState = game.perform(action: .put(at: (x: squareData.0.0, y: squareData.0.1))) else { return }
        put(piece: Figure.figure(for: game.currentPlayer), at: squareData.0) {
            DispatchQueue.main.async {
                self.game = newGameState
            }
        }
    }
    
    // MARK: - AR & SceneKit Transformations
    // Converts 2D touch coordinates to 3D scene coordinates.
    func groundPositionFrom(location: CGPoint) -> SCNVector3? {
        guard let query = sceneView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) else { return nil }
        let results = sceneView.session.raycast(query)
        if let result = results.first {
            return SCNVector3.positionFromTransform(result.worldTransform)
        }
        return nil
    }
    
    // Looks up the AR plane at a given location and returns the associated node and position.
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
    
    // Determines the board square at a given 2D location.
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
    
    // MARK: - ARSessionDelegate and Game Piece Manipulation
    // Updates processing when new AR frame data is available.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else { return }
        currentBuffer = frame.capturedImage
        performHandGestureDetection()
    }

    // Monitors the resting state of game pieces to finalize their position.
    @objc func checkRestingState() {
        guard let lastDetails = lastInteractionDetails, lastDetails.node.physicsBody?.isResting ?? false else {
            DispatchQueue.main.async { self.gameStateLabel.text = "No last interacted piece" }
            return
        }
        DispatchQueue.main.async {
            self.gameStateLabel.text = "Checking bounds"
            if let finalPosition = self.board.positionToGamePosition(lastDetails.node.position) {
                self.gameStateLabel.text = "Updating game state"
                self.updateGameState(from: lastDetails.initialSquare, to: finalPosition, with: lastDetails.node)
            } else {
                self.gameStateLabel.text = "Piece out of bounds"
            }
            self.lastInteractionDetails = nil
        }
    }
    
    // Checks the boundaries for all game pieces and updates their states accordingly.
    private func checkGamePiecesBoundaries() {
        DispatchQueue.main.async {
            var piecesToRemove = [String]()
            var finalState = self.game
            for (key, figure) in self.figures {
                guard let gamePos = self.board.positionToGamePosition(figure.position) else { continue }
                if let initialGamePos = self.gamePositionFromKey(key), let newGameState = self.game.perform(action: .remove(from: initialGamePos)) {
                    finalState = newGameState
                }
                figure.removeFromParentNode()
                piecesToRemove.append(key)
            }
            piecesToRemove.forEach { self.figures.removeValue(forKey: $0) }
            self.game = finalState
        }
    }
    
    // Extracts a game position from a key formatted as "x:y".
    private func gamePositionFromKey(_ key: String) -> GamePosition? {
        let components = key.split(separator: "x").map { Int($0) }
        if components.count == 2, let x = components[0], let y = components[1] {
            return (x, y)
        }
        return nil
    }
    
    // Updates the game state after moving a piece.
    private func updateGameState(from initial: (Int, Int), to final: (Int, Int), with piece: SCNNode) {
        let moveAction = GameAction.move(from: initial, to: final)
        if let newGameState = game.perform(action: moveAction) {
            let newPosition = sceneView.scene.rootNode.convertPosition(board.squareToPosition["\(final.0)x\(final.1)"]!, from: piece.parent)
            figures["\(final.0)x\(final.1)"] = piece
            figures["\(initial.0)x\(initial.1)"] = nil
            piece.runAction(SCNAction.move(to: newPosition, duration: 0.1)) {
                DispatchQueue.main.async {
                    self.gameStateLabel.text = "Node Moved"
                    self.game = newGameState
                }
            }
        }
    }
    
    // MARK: - Gesture
    // Processes hand gestures for game interaction.
    func performHandGestureDetection() {
        guard case .move = game.mode, playerType[game.currentPlayer]! == .human, let buffer = currentBuffer else { return }
        handDetector.performDetection(inputBuffer: buffer) { [weak self] outputBuffer, _ in
            guard let self = self, let outBuffer = outputBuffer else { return }
            DispatchQueue.main.async {
                self.previewView.image = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
                self.previewView.isHidden = false
                guard let tipPoint = outBuffer.searchTopPoint() else { return }
                let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))
                if let onBoardPlanePosition3D = self.groundPositionFrom(location: imageFingerPoint) {
                    self.updateTouchNodePosition(to: onBoardPlanePosition3D)
                    if let touchedSquare = self.squareFrom(location: imageFingerPoint), let gamePiece = self.figures["\(touchedSquare.0.0)x\(touchedSquare.0.1)"] {
                        self.lastInteractionDetails = (node: gamePiece, initialPosition: gamePiece.position, initialSquare: touchedSquare.0)
                        self.selectionFeedbackGenerator.selectionChanged()
                        self.impactFeedbackGenerator.impactOccurred()
                    }
                }
                self.currentBuffer = nil
                self.resetRestingStateTimer()
            }
        }
    }

    // Updates the position of the touch node to reflect the current interaction point.
    private func updateTouchNodePosition(to position: SCNVector3) {
        touchNode.simdPosition = SIMD3<Float>(position.x, position.y + Float(Dimensions.DRAG_LIFTOFF), position.z)
        if touchNode.parent == nil {
            sceneView.scene.rootNode.addChildNode(touchNode)
        }
        touchNode.isHidden = false
    }

    // Resets the timer that checks for the resting state of interactive elements.
    private func resetRestingStateTimer() {
        restingStateTimer?.invalidate()
        restingStateTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(checkRestingState), userInfo: nil, repeats: false)
    }
    
    // Moves a game piece from one position to another, handling both the visual and game state updates.
    private func move(from: GamePosition, to: GamePosition, completionHandler: (() -> Void)? = nil) {
        guard let piece = figures["\(from.x)x\(from.y)"] else {
            checkGamePiecesBoundaries()
            return
        }
        let destinationPosition = board.squareToPosition["\(to.x)x\(to.y)"].map { sceneView.scene.rootNode.convertPosition($0, from: board.node) }
        guard let newPosition = destinationPosition else {
            checkGamePiecesBoundaries()
            return
        }
        figures["\(to.x)x\(to.y)"] = piece
        figures["\(from.x)x\(from.y)"] = nil
        piece.runAction(SCNAction.sequence([
            // pickup
            SCNAction.move(to: SCNVector3(newPosition.x, newPosition.y + Float(Dimensions.DRAG_LIFTOFF), newPosition.z + Float(Dimensions.DRAG_LIFTOFF)), duration: 0.25),
            // move & drop down
            SCNAction.move(to: newPosition, duration: 0.25)
        ]), completionHandler: completionHandler)
    }
    
    // Places a game piece at a specific position on the board.
    private func put(piece: SCNNode, at position: GamePosition, completionHandler: (() -> Void)? = nil) {
        guard let squarePosition = board.squareToPosition["\(position.x)x\(position.y)"] else {
            checkGamePiecesBoundaries()
            return
        }
        piece.opacity = 0
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition, from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures["\(position.x)x\(position.y)"] = piece
        piece.runAction(SCNAction.fadeIn(duration: 0.5), completionHandler: completionHandler)
    }
    
    // Reverts a drag operation, restoring the piece to its original position.
    private func revertDrag() {
        guard let draggingFrom = draggingFrom, let originalPosition = draggingFromPosition else { return }
        let restorePosition = sceneView.scene.rootNode.convertPosition(originalPosition, from: board.node)
        figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(SCNAction.move(to: restorePosition, duration: 0.3))
        self.draggingFrom = nil
        self.draggingFromPosition = nil
    }
    
    // MARK: - Miscellaneous
    private func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
}

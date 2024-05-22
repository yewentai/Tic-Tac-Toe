//
//  ViewController.swift
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate {
    
    // MARK: - UI Outlets
    @IBOutlet weak var planeSearchLabel: UILabel!
    @IBOutlet weak var planeSearchOverlay: UIView!
    @IBOutlet weak var gameStateLabel: UILabel!
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var sizeSlider: UISlider!
    
    // MARK: - UI Actions
    @IBAction func didTapStartOver(_ sender: Any) { reset() }
    @IBAction func sliderValueChanged(_ sender: UISlider) {
        adjustBoardSize(to: sender.value)
    }
    
    // MARK: - State Variables
    var playerType = [
        GamePlayer.x: GamePlayerType.human,
        GamePlayer.o: GamePlayerType.ai
    ]
    var planeCount = 0 {
        didSet {
            updatePlaneOverlay()
        }
    }
    var currentPlane: SCNNode? {
        didSet {
            updatePlaneOverlay()
            newTurn()
        }
    }
    let board = Board()
    var game: GameState! {
        didSet {
            gameStateLabel.text = "\(game.currentPlayer.rawValue): \(playerType[game.currentPlayer]!.rawValue.uppercased()) to \(game.mode.rawValue)"
            
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
    var figures: [String: SCNNode] = [:]
    var lightNode: SCNNode?
    var floorNode: SCNNode?
    var draggingFrom: GamePosition? = nil
    var draggingFromPosition: SCNVector3? = nil
    
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [CGFloat]()
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        game = GameState()  // Create a new game
        
        sceneView.delegate = self
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        sceneView.addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        sceneView.addGestureRecognizer(pan)
        
        setupSlider()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        configuration.isLightEstimationEnabled = true
        
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    // MARK: - UI Setup
    func setupSlider() {
        sizeSlider.minimumValue = 0.5  // Minimum size factor
        sizeSlider.maximumValue = 2.0  // Maximum size factor
        sizeSlider.value = 1.0         // Default size factor
    }
    
    func adjustBoardSize(to scale: Float) {
        let scaleFactor = CGFloat(scale)
        board.node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        for figure in figures.values {
            figure.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        }
    }

    // MARK: - Game Management
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
    
    private func beginNewGame(_ players: [GamePlayer: GamePlayerType]) {
        playerType = players
        game = GameState()
        
        removeAllFigures()
        figures.removeAll()
    }
    
    private func newTurn() {
        guard playerType[game.currentPlayer]! == .ai else { return }
        
        // Run AI on background thread
        DispatchQueue.global(qos: .background).async {
            // Let the AI determine which action to perform
            let action = GameAI(game: self.game).bestAction
            
            // Once an action has been determined, perform it on main thread
            DispatchQueue.main.async {
                // Perform action or crash (game AI should never return an invalid action!)
                guard let newGameState = self.game.perform(action: action) else { fatalError() }
                
                // Block to execute after we have updated/animated the visual state of the game
                let updateGameState = {
                    // For some reason we have to put this in a main.async block in order to actually
                    // get to main thread. It appears that SceneKit animations do not return on main thread.
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
                }
                
                // Animate action
                switch action {
                case .put(let at):
                    self.put(piece: Figure.figure(for: self.game.currentPlayer),
                             at: at,
                             completionHandler: updateGameState)
                    
                case .move(let from, let to):
                    self.move(from: from,
                              to: to,
                              completionHandler: updateGameState)
                }
            }
        }
    }
    
    // MARK: - Plane and Board Management
    private func updatePlaneOverlay() {
        DispatchQueue.main.async {
            self.planeSearchOverlay.isHidden = self.currentPlane != nil
            
            if self.planeCount == 0 {
                self.planeSearchLabel.text = "Move around to allow the app to find a plane..."
            } else {
                self.planeSearchLabel.text = "Tap on a plane surface to place board..."
            }
        }
    }
    
    private func removeAllFigures() {
        for (_, figure) in figures {
            figure.removeFromParentNode()
        }
    }
    
    private func restoreGame(at position: SCNVector3) {
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
            let xyComponents = key.components(separatedBy: "x")
            guard xyComponents.count == 2,
                  let x = Int(xyComponents[0]),
                  let y = Int(xyComponents[1]) else { fatalError() }
            put(piece: figure, at: (x: x, y: y))
        }
    }
    
    private func groundPositionFrom(location: CGPoint) -> SCNVector3? {
        let results = sceneView.hitTest(location, types: .existingPlaneUsingExtent)
        guard results.count > 0 else { return nil }
        return SCNVector3.positionFromTransform(results[0].worldTransform)
    }
    
    private func anyPlaneFrom(location: CGPoint) -> (SCNNode, SCNVector3)? {
        let results = sceneView.hitTest(location, types: .existingPlaneUsingExtent)
        guard results.count > 0, let anchor = results[0].anchor, let node = sceneView.node(for: anchor) else { return nil }
        return (node, SCNVector3.positionFromTransform(results[0].worldTransform))
    }
    
    private func squareFrom(location: CGPoint) -> ((Int, Int), SCNNode)? {
        guard let _ = currentPlane else { return nil }
        
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false, SCNHitTestOption.rootNode: board.node])
        
        for result in hitResults {
            if let square = board.nodeToSquare[result.node] {
                return (square, result.node)
            }
        }
        return nil
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
    
    // MARK: - Gesture Handlers
    @objc func didPan(_ sender: UIPanGestureRecognizer) {
        guard case .move = game.mode, playerType[game.currentPlayer]! == .human else { return }
        
        let location = sender.location(in: sceneView)
        
        switch sender.state {
        case .began:
            guard let square = squareFrom(location: location) else { return }
            draggingFrom = (x: square.0.0, y: square.0.1)
            draggingFromPosition = square.1.position
            
        case .cancelled, .failed:
            revertDrag()
            
        case .changed:
            guard let draggingFrom = draggingFrom, let groundPosition = groundPositionFrom(location: location) else { return }
            let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z), duration: 0.1)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
        case .ended:
            guard let draggingFrom = draggingFrom, let square = squareFrom(location: location), square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y, let newGameState = game.perform(action: .move(from: draggingFrom, to: (x: square.0.0, y: square.0.1))) else {
                revertDrag()
                return
            }
            let toSquareId = "\(square.0.0)x\(square.0.1)"
            figures[toSquareId] = figures["\(draggingFrom.x)x\(draggingFrom.y)"]
            figures["\(draggingFrom.x)x\(draggingFrom.y)"] = nil
            self.draggingFrom = nil
            
            let newPosition = sceneView.scene.rootNode.convertPosition(square.1.position, from: square.1.parent)
            let action = SCNAction.move(to: newPosition, duration: 0.1)
            figures[toSquareId]?.runAction(action) {
                DispatchQueue.main.async {
                    self.game = newGameState
                }
            }
            
        default: break
        }
    }
    
    @objc func didTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: sceneView)
        
        // Tap to place board
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
        
        // Otherwise, tap to place board piece (if in "put" mode)
        guard case .put = game.mode, playerType[game.currentPlayer]! == .human else { return }
        
        if let squareData = squareFrom(location: location), let newGameState = game.perform(action: .put(at: (x: squareData.0.0, y: squareData.0.1))) {
            put(piece: Figure.figure(for: game.currentPlayer), at: squareData.0) {
                DispatchQueue.main.async {
                    self.game = newGameState
                }
            }
        }
    }
    
    // MARK: - Game Actions
    private func move(from: GamePosition, to: GamePosition, completionHandler: (() -> Void)? = nil) {
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        guard let piece = figures[fromSquareId], let rawDestinationPosition = board.squareToPosition[toSquareId] else { fatalError() }
        
        let destinationPosition = sceneView.scene.rootNode.convertPosition(rawDestinationPosition, from: board.node)
        
        figures[toSquareId] = piece
        figures[fromSquareId] = nil
        
        let pickUpAction = SCNAction.move(to: SCNVector3(piece.position.x, piece.position.y + Float(Dimensions.DRAG_LIFTOFF), piece.position.z), duration: 0.25)
        let moveAction = SCNAction.move(to: SCNVector3(destinationPosition.x, destinationPosition.y + Float(Dimensions.DRAG_LIFTOFF), destinationPosition.z), duration: 0.5)
        let dropDownAction = SCNAction.move(to: destinationPosition, duration: 0.25)
        
        piece.runAction(pickUpAction) {
            piece.runAction(moveAction) {
                piece.runAction(dropDownAction, completionHandler: completionHandler)
            }
        }
    }
    
    private func put(piece: SCNNode, at position: GamePosition, completionHandler: (() -> Void)? = nil) {
        let squareId = "\(position.x)x\(position.y)"
        guard let squarePosition = board.squareToPosition[squareId] else { fatalError() }
        
        piece.opacity = 0  // Initially invisible
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition, from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures[squareId] = piece
        
        let action = SCNAction.fadeIn(duration: 0.5)
        piece.runAction(action, completionHandler: completionHandler)
    }
    
    // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Update the intensity of the model's lights and the environment map
            if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        planeCount += 1
    }
    
    func renderer(_ renderer: SCNSceneRenderer, willUpdate node: SCNNode, for anchor: ARAnchor) {
        // Implement any updates needed when a plane is updated
    }
    
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
    
    // MARK: - Environment Map
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
}

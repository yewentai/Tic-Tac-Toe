//
//  ViewController.swift
//  AR-TicTacToe
//
//  Created by Bjarne Møller Lundgren on 20/06/2017.
//  Copyright © 2017 Bjarne Møller Lundgren. All rights reserved.
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
    
    // from demo APP
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [CGFloat]()
    
    override func viewDidLoad() {
        /** load the view */
        super.viewDidLoad()
        
        game = GameState()  // create new game

        // The delegate is used to receive ARAnchors when they are detected.
        sceneView.delegate = self
        //sceneView.showsStatistics = true
        //sceneView.antialiasingMode = .multisampling4X
        //sceneView.preferredFramesPerSecond = 60
        //sceneView.contentScaleFactor = 1.3
        sceneView.antialiasingMode = .multisampling4X
        
        sceneView.automaticallyUpdatesLighting = false
        
        let tap = UITapGestureRecognizer()
        tap.addTarget(self, action: #selector(didTap))
        sceneView.addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer()
        pan.addTarget(self, action: #selector(didPan))
        sceneView.addGestureRecognizer(pan)
    }

    // from APples app
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Media.scnassets/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    var previewView = UIImageView()
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
    
    private func newTurn() {
        guard playerType[game.currentPlayer]! == .ai else { return }
        
        //run AI on background thread
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {
            // let the AI determine which action to perform
            let action = GameAI(game: self.game).bestAction
                
            // once an action has been determined, perform it on main thread
            DispatchQueue.main.async {
                // perform action or crash (game AI should never return an invalid action!)
                guard let newGameState = self.game.perform(action: action) else { fatalError() }
                    
                // block to execute after we have updated/animated the visual state of the game
                let updateGameState = {
                    // for some reason we have to put this in a main.async block in order to actually
                    // get to main thread. It appears that SceneKit animations do not return on mainthread..
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
                }
                
                // animate action
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
        // lightNode!.eulerAngles = SCNVector3(45.0.degreesToRadians, 0, 0)
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
    
    
    private func groundPositionFrom(location: CGPoint) -> SCNVector3? {
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
        guard let _ = currentPlane else { return nil }
        // To transform our 2D Screen coordinates to 3D screen coordinates we use hitTest function
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false,
                                                               SCNHitTestOption.rootNode:       board.node])
        
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
            
            let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z),
                                        duration: 0.1)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
        case .ended:
            print("ended \(location)")
            
            guard let draggingFrom = draggingFrom,
                let square = squareFrom(location: location),
                square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y,
                let newGameState = game.perform(action: .move(from: draggingFrom,
                                                              to: (x: square.0.0, y: square.0.1))) else {
                    revertDrag()
                    return
            }
            
            
            
            // move in visual model
            let toSquareId = "\(square.0.0)x\(square.0.1)"
            figures[toSquareId] = figures["\(draggingFrom.x)x\(draggingFrom.y)"]
            figures["\(draggingFrom.x)x\(draggingFrom.y)"] = nil
            self.draggingFrom = nil
            
            // copy pasted insert thingie
            let newPosition = sceneView.scene.rootNode.convertPosition(square.1.position,
                                                                       from: square.1.parent)
            let action = SCNAction.move(to: newPosition,
                                        duration: 0.1)
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
            
            // https://stackoverflow.com/questions/30975695/scenekit-is-it-possible-to-cast-an-shadow-on-an-transparent-object/44799498#44799498
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
           let newGameState = game.perform(action: .put(at: (x: squareData.0.0,
                                                             y: squareData.0.1))) {
            
            put(piece: Figure.figure(for: game.currentPlayer),
                at: squareData.0) {
                    DispatchQueue.main.async {
                        self.game = newGameState
                    }
            }
            
            
        }
    }
    
    /// animates AI moving a piece
    private func move(from:GamePosition,
                      to:GamePosition,
                      completionHandler: (() -> Void)? = nil) {
        
        let fromSquareId = "\(from.x)x\(from.y)"
        let toSquareId = "\(to.x)x\(to.y)"
        guard let piece = figures[fromSquareId],
              let rawDestinationPosition = board.squareToPosition[toSquareId]  else { fatalError() }
        
        // this stuff will change once we stop putting nodes directly in world space..
        let destinationPosition = sceneView.scene.rootNode.convertPosition(rawDestinationPosition,
                                                                           from: board.node)
        
        // update visual game state
        figures[toSquareId] = piece
        figures[fromSquareId] = nil
        
        // create drag and drop animation
        let pickUpAction = SCNAction.move(to: SCNVector3(piece.position.x, piece.position.y + Float(Dimensions.DRAG_LIFTOFF), piece.position.z),
                                          duration: 0.25)
        let moveAction = SCNAction.move(to: SCNVector3(destinationPosition.x, destinationPosition.y + Float(Dimensions.DRAG_LIFTOFF), destinationPosition.z),
                                        duration: 0.5)
        let dropDownAction = SCNAction.move(to: destinationPosition,
                                            duration: 0.25)
        
        // run drag and drop animation
        piece.runAction(pickUpAction) {
            piece.runAction(moveAction) {
                piece.runAction(dropDownAction,
                                completionHandler: completionHandler)
            }
        }
    }
    
    /// renders user and AI insert of piece
    private func put(piece:SCNNode,
                     at position:GamePosition,
                     completionHandler: (() -> Void)? = nil) {
        let squareId = "\(position.x)x\(position.y)"
        guard let squarePosition = board.squareToPosition[squareId] else { fatalError() }
        
        piece.opacity = 0  // initially invisible
        // // https://stackoverflow.com/questions/30392579/convert-local-coordinates-to-scene-coordinates-in-scenekit
        piece.position = sceneView.scene.rootNode.convertPosition(squarePosition,
                                                                  from: board.node)
        sceneView.scene.rootNode.addChildNode(piece)
        figures[squareId] = piece
        
        let action = SCNAction.fadeIn(duration: 0.5)
        piece.runAction(action,
                        completionHandler: completionHandler)
    }
    
    // MARK: - ARSessionDelegate
    
    var currentBuffer: CVPixelBuffer?
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // This is where we will analyse our frame
        // read the capturedImage from ARFrame (CVPixelBuffer)
        // return if currentBuffer is not nil or the tracking state of camera is not normal
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            // currentBuffer being nil indicates that Core ML request has not finished processing yet and we shouldn’t start another.
            return
        }
        // Retain the image buffer for Vision processing.
        currentBuffer = frame.capturedImage

        startDetection()
    }

    // MARK: - Private functions

    let handDetector = HandDetector()
    let touchNode = TouchNode()

    private func startDetection() {
        // To avoid force unwrap in VNImageRequestHandler
        guard let buffer = currentBuffer else { return }

        handDetector.performDetection(inputBuffer: buffer) { outputBuffer, _ in
            // Here we are on a background thread
            var previewImage: UIImage?
            var normalizedFingerTip: CGPoint?

            defer {
                DispatchQueue.main.async {
                    self.previewView.image = previewImage
                    // Release currentBuffer when finished to allow processing next frame
                    self.currentBuffer = nil
                    
                    self.touchNode.isHidden = true
                    
                    guard let tipPoint = normalizedFingerTip else {
                        return
                    }
                    // We use a coreVideo function to get the image coordinate from the normalized point
                    let imageFingerPoint = VNImagePointForNormalizedPoint(tipPoint, Int(self.view.bounds.size.width), Int(self.view.bounds.size.height))

                    // And here again we need to hitTest to translate from 2D coordinates to 3D coordinates
                    let hitTestResults = self.sceneView.hitTest(imageFingerPoint, types: .existingPlaneUsingExtent)
                    guard let hitTestResult = hitTestResults.first else { return }

                    // We position our touchNode slighlty above the plane (1cm).
                    self.touchNode.simdTransform = hitTestResult.worldTransform
                    self.touchNode.position.y += 0.01
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
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        // from apples app
        DispatchQueue.main.async {
            // If light estimation is enabled, update the intensity of the model's lights and the environment map
            if let lightEstimate = self.sceneView.session.currentFrame?.lightEstimate {
                
                // Apple divived the ambientIntensity by 40, I find that, atleast with the materials used
                // here that it's a big too bright, so I increased to to 50..
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 50)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
    
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
    
}


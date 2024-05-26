//
//  Board.swift
//

import Foundation
import SceneKit

class Board {
    let node:SCNNode
    let nodeToSquare:[SCNNode:(Int,Int)]
    let squareToPosition:[String:SCNVector3]
    
    init() {
        node = SCNNode()
        var nodeToSquare = [SCNNode:(Int,Int)]()
        var squareToPosition = [String:SCNVector3]()
        
        
        let length = Dimensions.SQUARE_SIZE * 4
        let height:CGFloat = Dimensions.BOARD_GRID_HEIGHT
        let width:CGFloat = Dimensions.BOARD_GRID_WIDTH

        // Adding a physics body for collision boundaries
        let boardGeometry = SCNBox(width: CGFloat(Dimensions.SQUARE_SIZE * 3), height: 0.01, length: CGFloat(Dimensions.SQUARE_SIZE * 3), chamferRadius: 0)
        let boardShape = SCNPhysicsShape(geometry: boardGeometry, options: nil)
        let boardPhysicsBody = SCNPhysicsBody(type: .static, shape: boardShape)
        boardPhysicsBody.restitution = 0.1
        boardPhysicsBody.friction = 0.5
        
        node.physicsBody = boardPhysicsBody
        
        
        // Loop through each row of the board
        for l in 0..<4 {
            let lineOffset = length * 0.5 - (CGFloat(l + 1) * Dimensions.SQUARE_SIZE - Dimensions.SQUARE_SIZE * 0.5)
            
            // squares
            if l > 0 {
                for r in 0..<3 {
                    let position = SCNVector3(lineOffset + Dimensions.SQUARE_SIZE * 0.5,
                                              0.01,
                                              //TODO: do a rowOffset like above for this, this is ugly!
                        CGFloat(r - 1) * Dimensions.SQUARE_SIZE)
                    let square = (l - 1, r)
                    
                    let geometry = SCNPlane(width: Dimensions.SQUARE_SIZE,
                                            height: Dimensions.SQUARE_SIZE)
                    geometry.firstMaterial!.diffuse.contents = UIColor.clear
                    //geometry.firstMaterial!.specular.contents = UIColor.white
                    
                    let squareNode = SCNNode(geometry: geometry)
                    squareNode.position = position
                    squareNode.eulerAngles = SCNVector3(-90.0.degreesToRadians, 0, 0)
                    
                    node.addChildNode(squareNode)
                    nodeToSquare[squareNode] = square
                    squareToPosition["\(square.0)x\(square.1)"] = position
                }
            }
            
            
            // grid lines..
            let geometry = SCNBox(width: width,
                                  height: height,
                                  length: length,
                                  chamferRadius: height * 0.1)
            geometry.firstMaterial?.lightingModel = .physicallyBased
            geometry.firstMaterial?.diffuse.contents = UIImage(named: "Media.scnassets/scuffed-plastic2-alb.png")
            geometry.firstMaterial?.roughness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-rough.png")
            geometry.firstMaterial?.metalness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-metal.png")
            geometry.firstMaterial?.normal.contents = UIImage(named: "Media.scnassets/scuffed-plastic-normal.png")
            geometry.firstMaterial?.ambientOcclusion.contents = UIImage(named: "Media.scnassets/scuffed-plastic-ao.png")
            
            let horizontalLineNode = SCNNode(geometry: geometry)
            horizontalLineNode.position = SCNVector3(lineOffset, height * 0.5, 0)
            node.addChildNode(horizontalLineNode)
            
            let verticalLineNode = SCNNode(geometry: geometry)
            verticalLineNode.eulerAngles = SCNVector3(0, 90.0.degreesToRadians, 0)
            verticalLineNode.position = SCNVector3(0, height * 0.5, lineOffset)
            node.addChildNode(verticalLineNode)
        }
        
        self.nodeToSquare = nodeToSquare
        self.squareToPosition = squareToPosition
    }
    
    func positionToGamePosition(_ position: SCNVector3) -> GamePosition? {
        // Mapping 3D Scene Coordinates to Game Grid Positions
        // Assuming the center of the board is at (0,0,0) and spans equally in all directions
        let boardCenter = node.position
        
        // Calculate relative positions, converting CGFloat to Float if necessary
        let relativeX = position.x - Float(boardCenter.x)
        let relativeZ = position.z - Float(boardCenter.z)

        // Convert Dimensions.SQUARE_SIZE to Float if it's defined as CGFloat
        let squareSize = Float(Dimensions.SQUARE_SIZE)
        let offset = squareSize * 1.5
        let columnPosition = relativeX + offset
        let rowPosition = relativeZ + offset

        // Calculate column and row indices
        let columnIndex = Int(floor(columnPosition / squareSize))
        let rowIndex = Int(floor(rowPosition / squareSize))

        // Check if the calculated position is within the bounds of the board
        let isValidColumn = columnIndex >= 0 && columnIndex < 3
        let isValidRow = rowIndex >= 0 && rowIndex < 3

        if isValidColumn && isValidRow {
            return (rowIndex, columnIndex)
        }

        return nil // Return nil if the position is outside the game board
    }
}

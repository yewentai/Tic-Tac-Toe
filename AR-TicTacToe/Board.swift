//
//  Board.swift
//

import Foundation
import SceneKit

class Board {
    let node: SCNNode
    let nodeToSquare: [SCNNode: (Int, Int)]
    let squareToPosition: [String: SCNVector3]
    
    init() {
        node = SCNNode()
        var nodeToSquare = [SCNNode: (Int, Int)]()
        var squareToPosition = [String: SCNVector3]()
        
        let length = Dimensions.SQUARE_SIZE * 4
        let height: CGFloat = Dimensions.BOARD_GRID_HEIGHT
        let width: CGFloat = Dimensions.BOARD_GRID_WIDTH
        
        // Create the board squares and grid lines
        for l in 0..<4 {
            let lineOffset = length * 0.5 - (CGFloat(l + 1) * Dimensions.SQUARE_SIZE - Dimensions.SQUARE_SIZE * 0.5)
            
            // Create squares for the game board
            if l > 0 {
                for r in 0..<3 {
                    let position = SCNVector3(lineOffset + Dimensions.SQUARE_SIZE * 0.5, 0.01, CGFloat(r - 1) * Dimensions.SQUARE_SIZE)
                    let square = (l - 1, r)
                    
                    let geometry = SCNPlane(width: Dimensions.SQUARE_SIZE, height: Dimensions.SQUARE_SIZE)
                    geometry.firstMaterial!.diffuse.contents = UIColor.clear
                    
                    let squareNode = SCNNode(geometry: geometry)
                    squareNode.position = position
                    squareNode.eulerAngles = SCNVector3(-90.0.degreesToRadians, 0, 0)
                    
                    node.addChildNode(squareNode)
                    nodeToSquare[squareNode] = square
                    squareToPosition["\(square.0)x\(square.1)"] = position
                }
            }
            
            // Create horizontal and vertical grid lines
            let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: height * 0.1)
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
}

//
//  Board.swift
//  TicTacToe
//
//  Created by Wentai Ye on Apr 24 2024
//  Copyright © 2024 Wentai Ye. All rights reserved.
//

import Foundation
import SceneKit

class Board {
    // SCNNode representing the entire board
    let node:SCNNode
    // Dictionary mapping square nodes to their corresponding (row, column) indices
    let nodeToSquare:[SCNNode:(Int,Int)]
    // Dictionary mapping square positions (in string format) to their SCNVector3 positions
    let squareToPosition:[String:SCNVector3]
    
    init() {
        // Initialize the board node
        node = SCNNode()
        // Initialize dictionaries to map square nodes to their indices and positions
        var nodeToSquare = [SCNNode:(Int,Int)]()
        var squareToPosition = [String:SCNVector3]()
        
        // Dimensions of the board
        let length = Dimensions.SQUARE_SIZE * 4
        let height:CGFloat = Dimensions.BOARD_GRID_HEIGHT
        let width:CGFloat = Dimensions.BOARD_GRID_WIDTH
        
        // Loop through each row of the board
        for l in 0..<4 {
            let lineOffset = length * 0.5 - (CGFloat(l + 1) * Dimensions.SQUARE_SIZE - Dimensions.SQUARE_SIZE * 0.5)
            
            // Create squares for each row (except the first row)
            if l > 0 {
                for r in 0..<3 {
                    // Calculate position for each square
                    let position = SCNVector3(lineOffset + Dimensions.SQUARE_SIZE * 0.5,
                                              0.01,
                                              CGFloat(r - 1) * Dimensions.SQUARE_SIZE)
                    let square = (l - 1, r)
                    
                    // Create square geometry
                    let geometry = SCNPlane(width: Dimensions.SQUARE_SIZE,
                                            height: Dimensions.SQUARE_SIZE)
                    geometry.firstMaterial!.diffuse.contents = UIColor.clear
                    
                    // Create SCNNode for the square and set its position
                    let squareNode = SCNNode(geometry: geometry)
                    squareNode.position = position
                    squareNode.eulerAngles = SCNVector3(-90.0.degreesToRadians, 0, 0)
                    
                    // Add square node to the board node and update dictionaries
                    node.addChildNode(squareNode)
                    nodeToSquare[squareNode] = square
                    squareToPosition["\(square.0)x\(square.1)"] = position
                }
            }
            
            // Create horizontal and vertical grid lines for the current row
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
            
            // Create horizontal line node and set its position
            let horizontalLineNode = SCNNode(geometry: geometry)
            horizontalLineNode.position = SCNVector3(lineOffset, height * 0.5, 0)
            node.addChildNode(horizontalLineNode)
            
            // Create vertical line node and set its position
            let verticalLineNode = SCNNode(geometry: geometry)
            verticalLineNode.eulerAngles = SCNVector3(0, 90.0.degreesToRadians, 0)
            verticalLineNode.position = SCNVector3(0, height * 0.5, lineOffset)
            node.addChildNode(verticalLineNode)
        }
        
        // Assign dictionaries to properties
        self.nodeToSquare = nodeToSquare
        self.squareToPosition = squareToPosition
    }
}

extension Board {
    func positionToGamePosition(_ position: SCNVector3) -> GamePosition? {
        /** Mapping 3D Scene Coordinates to Game Grid Positions */
        // Assuming the center of the board is at (0,0,0) and spans equally in all directions
        let boardCenter = node.position
        let relativeX = position.x - boardCenter.x
        let relativeZ = position.z - boardCenter.z

        // Calculate which square the position corresponds to
        let columnIndex = Int(floor((relativeX + Dimensions.SQUARE_SIZE * 1.5) / Dimensions.SQUARE_SIZE))
        let rowIndex = Int(floor((relativeZ + Dimensions.SQUARE_SIZE * 1.5) / Dimensions.SQUARE_SIZE))

        // Validate if the calculated indices are within the bounds of the board
        if rowIndex >= 0, rowIndex < 3, columnIndex >= 0, columnIndex < 3 {
            return (rowIndex, columnIndex)
        }
        
        return nil // Return nil if the position is outside the game board
    }
}

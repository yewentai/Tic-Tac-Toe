//
//  Figure.swift
//

import Foundation
import SceneKit

class Figure {
    // Returns the appropriate figure node for the given player
    class func figure(for player: GamePlayer) -> SCNNode {
        switch player {
        case .x:
            return xFigure() // Return an "X" figure node
        case .o:
            return oFigure() // Return an "O" figure node
        }
    }
    
    // Creates and returns the "X" figure node
    class func xFigure() -> SCNNode {
        let geometry = SCNCylinder(radius: Dimensions.FIGURE_RADIUS, height: Dimensions.SQUARE_SIZE)
        
        // Configure the material for physically-based rendering
        geometry.firstMaterial?.lightingModel = .physicallyBased
        geometry.firstMaterial?.diffuse.contents = UIImage(named: "Media.scnassets/scuffed-plastic6-alb.png")
        geometry.firstMaterial?.roughness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-rough.png")
        geometry.firstMaterial?.metalness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-metal.png")
        geometry.firstMaterial?.normal.contents = UIImage(named: "Media.scnassets/scuffed-plastic-normal.png")
        geometry.firstMaterial?.ambientOcclusion.contents = UIImage(named: "Media.scnassets/scuffed-plastic-ao.png")
        
        // Create the first cylinder node for the "X" figure, rotated and positioned
        let cylinderNode1 = SCNNode(geometry: geometry)
        cylinderNode1.eulerAngles = SCNVector3(-90.0.degreesToRadians, 45.0.degreesToRadians, 0)
        cylinderNode1.position = SCNVector3(0, Dimensions.FIGURE_RADIUS * 0.5, 0)
        
        // Create the second cylinder node for the "X" figure, rotated and positioned
        let cylinderNode2 = SCNNode(geometry: geometry)
        cylinderNode2.eulerAngles = SCNVector3(-90.0.degreesToRadians, -45.0.degreesToRadians, 0)
        cylinderNode2.position = SCNVector3(0, Dimensions.FIGURE_RADIUS * 0.5, 0)
        
        // Combine the two cylinder nodes into one node representing the "X" figure
        let node = SCNNode()
        node.addChildNode(cylinderNode1)
        node.addChildNode(cylinderNode2)
        return node
    }
    
    // Creates and returns the "O" figure node
    class func oFigure() -> SCNNode {
        let geometry = SCNTorus(ringRadius: Dimensions.SQUARE_SIZE * 0.3, pipeRadius: Dimensions.FIGURE_RADIUS)
        
        // Configure the material for physically-based rendering
        geometry.firstMaterial?.lightingModel = .physicallyBased
        geometry.firstMaterial?.diffuse.contents = UIImage(named: "Media.scnassets/scuffed-plastic4-alb.png")
        geometry.firstMaterial?.roughness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-rough.png")
        geometry.firstMaterial?.metalness.contents = UIImage(named: "Media.scnassets/scuffed-plastic-metal.png")
        geometry.firstMaterial?.normal.contents = UIImage(named: "Media.scnassets/scuffed-plastic-normal.png")
        geometry.firstMaterial?.ambientOcclusion.contents = UIImage(named: "Media.scnassets/scuffed-plastic-ao.png")
        
        // Create the torus node for the "O" figure, positioned
        let torusNode = SCNNode(geometry: geometry)
        torusNode.position = SCNVector3(0, Dimensions.FIGURE_RADIUS * 0.5, 0)
        
        // Wrap the torus node into a parent node representing the "O" figure
        let node = SCNNode()
        node.addChildNode(torusNode)
        return node
    }
}

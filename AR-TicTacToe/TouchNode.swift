//
//  TouchNode.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/8/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import SceneKit

public class TouchNode: SCNNode {
    // MARK: - Lifecycle

    /// Initializes a new TouchNode instance.
    public override init() {
        super.init()
        commonInit()
    }

    /// Initializes a new TouchNode instance from a decoder, required for conforming to NSCoding.
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    /// Shared initialization routines for setting up the node's geometry and physics.
    private func commonInit() {
        // Create a sphere geometry to represent the touch point in the scene.
        let sphere = SCNSphere(radius: 0.01) // Set the radius to a small value suitable for touch interactions.

        // Create and configure the material of the sphere.
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red // Sets the color of the sphere to red for visibility.

        // Uncomment the following line during debugging to visualize the node.
         geometry = sphere

        // Assign the material to the sphere.
        sphere.firstMaterial = material

        // Create a physics shape based on the sphere geometry.
        let sphereShape = SCNPhysicsShape(geometry: sphere, options: nil)

        // Configure the physics body of the node as kinematic. Kinematic bodies are not affected by forces
        // and collisions but can be moved programmatically which is ideal for controlled interactions.
        physicsBody = SCNPhysicsBody(type: .kinematic, shape: sphereShape)
        
        // Set additional node properties if needed here. For example, setting visibility or interaction behaviors.
    }
}

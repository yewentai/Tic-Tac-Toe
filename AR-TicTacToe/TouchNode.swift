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

    public override init() {
        super.init()
        commonInit()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        // Touch node configuration
        let sphere = SCNSphere(radius: 0.01)

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.red

        // Uncomment to see the node for debugging purposes
        geometry = sphere
        sphere.firstMaterial = material

        let sphereShape = SCNPhysicsShape(geometry: sphere, options: nil)

        physicsBody = SCNPhysicsBody(type: .kinematic, shape: sphereShape)
    }
}

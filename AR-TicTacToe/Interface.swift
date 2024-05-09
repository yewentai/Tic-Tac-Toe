//
//  Interface.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/9/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

// Parts of this code have been obtained from WWDC sample code: https://developer.apple.com/wwdc19/607

// 1. Import Frameword
import RealityKit
import SwiftUI
import ARKit        //motion capture feature

// 5. Create BodySkeleton entity to visualize and update joint pose

    // 6. Create entity for each joint in skeleton

        // Default values for joint appearance

        // 12. Set color and size based on specific joinName
        // NOTE: Green joints are actively tracked by ARkit. Yellow joints are not tracked. They just follow the motion of the closest green parent

        // Create an entity for the joint, ad to joints dictionary, and add ti to the parent entity (i.e. bodySkeleton)

    // 7. Create helper method to create a sphere-shaped entity with specified radius and color for a joint

    // 8. Create method to update the position and orientation of each jointEntity

// 9. Create global variables for Body Skeleton

// 3. Create ARViewContainer
    // 10. Add bodeSkeletonAnchor to the scene

// 4. Extend ARView to implement body tracking functionality

    // 4a. configure ARView for body tracking
    // NOTE: Dont forget to call this method in ARViewComntainer

    // 4b. Implement ARSession didUpdate anchors delegate method

// 2a. Create ContentView

// 2b. Set ContentView as LiveView



//
//  HandGestureDetector.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/9/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import CoreML
import Vision

public class HandGestureDetector {
    
    // MARK: - Variables
    
    // DispatchQueue for performing vision operations, labeled distinctly for easier debugging.
    private let visionQueue = DispatchQueue(label: "com.jeffee.handgesture")
    
    // Lazy-initialized Vision Core ML request using a machine learning model.
    private lazy var predictionRequest: VNCoreMLRequest = {
        do {
            // Load the ML model and prepare it for use with Vision requests.
            let model = try VNCoreMLModel(for: HandGesture().model)
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    // Handle any errors during request configuration.
                    print("Error setting up Core ML request: \(error.localizedDescription)")
                    return
                }
            }
            
            // Configure the image processing to scale the image to fill the required size while maintaining the aspect ratio.
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            // It's generally good to avoid fatal errors in production. Consider more graceful error handling.
            fatalError("Unable to load Vision ML model: \(error)")
        }
    }()
    
    // MARK: - Public functions
    
    /// Performs gesture detection on the provided image buffer.
    /// - Parameters:
    ///   - inputBuffer: The image buffer containing the frame to be analyzed.
    ///   - completion: Closure to be called upon completion of the detection process, returning either a result string or an error.
    public func performDetection(inputBuffer: CVPixelBuffer, completion: @escaping (_ output: String, _ error: Error?) -> Void) {
        // Handler for processing the image buffer with the specified orientation.
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: inputBuffer, orientation: .right, options: [:])
        
        // Perform the Core ML request asynchronously to avoid blocking the UI.
        visionQueue.async {
            do {
                // Execute the Core ML request.
                try requestHandler.perform([self.predictionRequest])
                
                // Extract and process the results of the request.
                guard let observations = self.predictionRequest.results as? [VNClassificationObservation] else {
                    // Handle unexpected result types gracefully.
                    print("Expected classification observations but got other types.")
                    completion("", nil)
                    return
                }
                
                // Filter and format the top classification results.
                let topClassifications = observations.prefix(3)  // Limit to top 3 results
                    .map { observation in
                        return "\(observation.identifier) (confidence: \(String(format: "%.2f", observation.confidence)))"
                    }.joined(separator: "\n")
                
                // Output classification results.
                print("Top classifications: \(topClassifications)")
                
                // Pass the classification results to the completion handler.
                completion(topClassifications, nil)
            } catch {
                // Handle errors in model execution or result processing.
                print("Failed to perform Vision request: \(error)")
                completion("", error)
            }
        }
    }
}

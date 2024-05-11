//
//  HandDetector.swift
//  AR-TicTacToe
//
//  Created by jeffee hsiung on 5/8/24.
//  Copyright © 2024 Bjarne Møller Lundgren. All rights reserved.
//

import CoreML
import Vision

public class HandDetector {
    // MARK: - Variables

    // Creates a dedicated queue for processing vision-related tasks to avoid blocking the UI thread.
    private let visionQueue = DispatchQueue(label: "com.jeffee.visionqueue")

    private lazy var predictionRequest: VNCoreMLRequest = {
        do {
            let model = try VNCoreMLModel(for: HandModel().model)
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    print("Error during model setup: \(error.localizedDescription)")
                }
            }
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            print("Failed to load Vision ML model: \(error)")
            fatalError("Failed to load the ML model.")
        }
    }()


    // MARK: - Public functions

    /// Perform hand detection on the provided image buffer.
    /// - Parameters:
    ///   - inputBuffer: The pixel buffer of the camera feed.
    ///   - completion: A closure that returns either a pixel buffer of the detected hand or an error.
    public func performDetection(inputBuffer: CVPixelBuffer, completion: @escaping (_ outputBuffer: CVPixelBuffer?, _ error: Error?) -> Void) {
        // Ensures the image is processed in the correct orientation as the camera’s native capture orientation is landscape.
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: inputBuffer, orientation: .right, options: [:])

        // Processes the request asynchronously on the vision queue to prevent UI blockages.
        visionQueue.async {
            do {
                // Execute the prediction request.
                try requestHandler.perform([self.predictionRequest])

                // Handle the results of the prediction.
                guard let observation = self.predictionRequest.results?.first as? VNPixelBufferObservation else {
                    print("Failed to obtain VNPixelBufferObservation")
                    completion(nil, nil)  // Consider providing a more descriptive error.
                    return
                }

                // If successful, pass the pixel buffer containing the detected hand.
                completion(observation.pixelBuffer, nil)
            } catch {
                // Handle any errors that occur during the vision request.
                print("Error performing vision request: \(error.localizedDescription)")
                completion(nil, error)
            }
        }
    }
}

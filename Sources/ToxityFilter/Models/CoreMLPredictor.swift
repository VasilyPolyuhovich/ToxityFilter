import Foundation
import CoreML
import NaturalLanguage

/// Toxicity labels from toxic-bert model
public enum ToxicityLabel: String, CaseIterable, Sendable {
    case toxic = "toxic"
    case severeToxic = "severe_toxic"
    case obscene = "obscene"
    case threat = "threat"
    case insult = "insult"
    case identityHate = "identity_hate"

    public var displayName: String {
        switch self {
        case .toxic: return "Toxic"
        case .severeToxic: return "Severe Toxic"
        case .obscene: return "Obscene"
        case .threat: return "Threat"
        case .insult: return "Insult"
        case .identityHate: return "Identity Hate"
        }
    }
}

/// Result from toxicity prediction
public struct ToxicityPrediction: Sendable {
    public let scores: [ToxicityLabel: Double]

    /// Maximum toxicity score across all labels
    public var maxScore: Double {
        scores.values.max() ?? 0
    }

    /// Label with highest score
    public var dominantLabel: ToxicityLabel? {
        scores.max(by: { $0.value < $1.value })?.key
    }

    /// Check if any toxicity exceeds threshold
    public func isAboveThreshold(_ threshold: Double) -> Bool {
        maxScore >= threshold
    }

    /// Get all labels above threshold
    public func labelsAboveThreshold(_ threshold: Double) -> [ToxicityLabel] {
        scores.filter { $0.value >= threshold }.map { $0.key }
    }
}

/// CoreML model wrapper with async prediction support
/// Uses toxic-bert model for multi-label toxicity detection
@available(iOS 15.0, *)
public actor CoreMLPredictor {

    // MARK: - Properties

    private let toxicityModel: MLModel?
    private let toxicityLabels: [Int: ToxicityLabel]

    // MARK: - Initialization

    /// Initialize predictor with CoreML models from Bundle
    /// - Parameter bundle: Bundle containing models and resources (defaults to ToxityFilter bundle)
    public init(bundle: Bundle? = nil) {
        let resourceBundle = bundle ?? Bundle.module

        // Load toxicity model from compiled .mlmodelc URL
        let toxicityModelResult: MLModel? = {
            guard let modelURL = resourceBundle.url(
                forResource: "ToxicityDetector",
                withExtension: "mlmodelc"
            ) else {
                print("ToxicityDetector.mlmodelc not found in bundle")
                return nil
            }

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all // Use Neural Engine

                let model = try MLModel(contentsOf: modelURL, configuration: config)
                print("Loaded ToxicityDetector from \(modelURL.lastPathComponent)")
                return model
            } catch {
                print("Failed to load toxicity model: \(error)")
                return nil
            }
        }()
        self.toxicityModel = toxicityModelResult

        // Static labels for toxic-bert (order matters!)
        self.toxicityLabels = [
            0: .toxic,
            1: .severeToxic,
            2: .obscene,
            3: .threat,
            4: .insult,
            5: .identityHate
        ]
    }

    // MARK: - Prediction

    /// Predict toxicity from tokenized input (multi-label classification)
    /// - Parameters:
    ///   - inputIds: Token IDs from tokenizer
    ///   - attentionMask: Attention mask from tokenizer
    /// - Returns: ToxicityPrediction with scores for all 6 labels
    public func predictToxicity(
        inputIds: [Int32],
        attentionMask: [Int32]
    ) async throws -> ToxicityPrediction {
        guard let model = toxicityModel else {
            throw PredictionError.modelNotAvailable("Toxicity model not loaded")
        }

        // Create input features
        let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: inputIds.count)], dataType: .int32)
        let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: attentionMask.count)], dataType: .int32)

        for (index, value) in inputIds.enumerated() {
            inputIdsArray[index] = NSNumber(value: value)
        }

        for (index, value) in attentionMask.enumerated() {
            attentionMaskArray[index] = NSNumber(value: value)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ])

        // Predict
        let output = try model.prediction(from: input)

        // Get probabilities (toxic-bert outputs probabilities directly after sigmoid)
        guard let probs = output.featureValue(for: "probabilities")?.multiArrayValue else {
            throw PredictionError.invalidOutput("No probabilities in output")
        }

        // Map to labels
        var scores: [ToxicityLabel: Double] = [:]
        for i in 0..<min(probs.count, toxicityLabels.count) {
            if let label = toxicityLabels[i] {
                scores[label] = probs[i].doubleValue
            }
        }

        return ToxicityPrediction(scores: scores)
    }

    /// Check if model is loaded and available
    public var isModelAvailable: Bool {
        toxicityModel != nil
    }
}

// MARK: - Error Types

public enum PredictionError: Error, LocalizedError {
    case modelNotAvailable(String)
    case invalidInput(String)
    case invalidOutput(String)
    case predictionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let message):
            return "Model not available: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .invalidOutput(let message):
            return "Invalid output: \(message)"
        case .predictionFailed(let error):
            return "Prediction failed: \(error.localizedDescription)"
        }
    }
}

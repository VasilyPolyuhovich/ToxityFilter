import Foundation

/// Pipeline execution mode
public enum PipelineMode: Sendable {
    /// Only ML model (ToxicityDetector v3)
    case mlOnly
    /// ML + keyword filter (default, recommended)
    case mlWithKeywords
    /// Keyword filter only (fastest, for real-time validation)
    case keywordsOnly
}

/// Configuration for content moderation
public struct ModerationConfig: Sendable {
    /// Threshold for toxicity detection (0.0 - 1.0)
    /// Lower = more strict, Higher = more lenient
    public let toxicityThreshold: Double
    
    /// Cache size for storing moderation results
    public let cacheSize: Int
    
    /// Pipeline execution mode
    public let pipelineMode: PipelineMode
    
    public init(
        toxicityThreshold: Double = 0.5,
        cacheSize: Int = 1000,
        pipelineMode: PipelineMode = .mlWithKeywords
    ) {
        self.toxicityThreshold = toxicityThreshold
        self.cacheSize = cacheSize
        self.pipelineMode = pipelineMode
    }
}

// MARK: - Presets

extension ModerationConfig {
    /// Default configuration - balanced accuracy and speed
    /// - Use for: Most applications, social apps, chat systems
    /// - Pipeline: ML + Keywords
    /// - Threshold: 50%
    public static let `default` = ModerationConfig(
        toxicityThreshold: 0.5,
        cacheSize: 1000,
        pipelineMode: .mlWithKeywords
    )
    
    /// Strict configuration - maximum sensitivity
    /// - Use for: Children's apps, highly moderated communities
    /// - Pipeline: ML + Keywords  
    /// - Threshold: 30% (catches more content)
    public static let strict = ModerationConfig(
        toxicityThreshold: 0.3,
        cacheSize: 1000,
        pipelineMode: .mlWithKeywords
    )
    
    /// Lenient configuration - fewer false positives
    /// - Use for: Adult communities, creative writing, opinion forums
    /// - Pipeline: ML only (no keyword filter)
    /// - Threshold: 70%
    public static let lenient = ModerationConfig(
        toxicityThreshold: 0.7,
        cacheSize: 1000,
        pipelineMode: .mlOnly
    )
    
    /// Fast configuration - real-time validation
    /// - Use for: Live typing validation, high-throughput systems
    /// - Pipeline: Keywords only (no ML inference)
    /// - Threshold: 50%
    public static let fast = ModerationConfig(
        toxicityThreshold: 0.5,
        cacheSize: 2000,
        pipelineMode: .keywordsOnly
    )
}

import Foundation

/// Result of content moderation analysis
public struct ModerationResult: Sendable {
    
    // MARK: - Properties
    
    /// Overall decision whether content should be allowed
    public let isAcceptable: Bool
    
    /// Moderation level (ok/recommendation/warning/critical)
    public let level: ModerationLevel
    
    /// Combined severity score (0.0 - 1.0)
    public let severityScore: Double
    
    /// Detected issues with individual scores
    public let detectedIssues: [Issue]
    
    /// Detailed reasons with confidence levels
    public let reasons: [ModerationReason]
    
    /// User-facing message based on moderation level
    public let userMessage: String
    
    /// Original text that was analyzed
    public let analyzedText: String
    
    /// Processing time in milliseconds
    public let processingTimeMs: Double
    
    /// Which analysis layers were used
    public let layersUsed: [AnalysisLayer]
    
    // MARK: - Issue
    
    public struct Issue: Sendable, Identifiable {
        public let id = UUID()
        public let type: IssueType
        public let score: Double
        public let source: AnalysisLayer

        public init(
            type: IssueType,
            score: Double,
            source: AnalysisLayer
        ) {
            self.type = type
            self.score = score
            self.source = source
        }
    }
    
    // MARK: - Issue Types
    
    public enum IssueType: String, Sendable, CaseIterable, Codable {
        // Toxicity from ToxicityDetector v3 (toxic-bert domain-adapted)
        case toxicity = "Toxicity"
        case threat = "Threat"
        case insult = "Insult"
        case obscenity = "Obscene Language"
        case hateSpeech = "Hate Speech"
        
        // Critical keywords
        case criticalKeyword = "Critical Keyword"

        public var helpMessage: String {
            switch self {
            case .toxicity:
                return "This content appears toxic. Please be respectful."
            case .threat:
                return "Threatening language is not allowed. Please revise your message."
            case .insult:
                return "Insulting language is not appropriate. Consider a more constructive approach."
            case .obscenity:
                return "This content contains inappropriate language. Please revise."
            case .hateSpeech:
                return "This content may violate community guidelines. Please be respectful."
            case .criticalKeyword:
                return "This content contains prohibited terms. Please revise your message."
            }
        }
    }
    
    // MARK: - Analysis Layers
    
    public enum AnalysisLayer: String, Sendable {
        case cache = "Cache"
        case keywordFilter = "Keyword Filter"
        case toxicityModel = "CoreML Toxicity Detector"

        public var priority: Int {
            switch self {
            case .cache: return 0
            case .keywordFilter: return 1
            case .toxicityModel: return 2
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(
        isAcceptable: Bool,
        level: ModerationLevel,
        severityScore: Double,
        detectedIssues: [Issue],
        reasons: [ModerationReason],
        userMessage: String,
        analyzedText: String,
        processingTimeMs: Double,
        layersUsed: [AnalysisLayer]
    ) {
        self.isAcceptable = isAcceptable
        self.level = level
        self.severityScore = severityScore
        self.detectedIssues = detectedIssues
        self.reasons = reasons
        self.userMessage = userMessage
        self.analyzedText = analyzedText
        self.processingTimeMs = processingTimeMs
        self.layersUsed = layersUsed
    }
    
    // MARK: - Computed Properties
    
    /// Primary issue with highest score
    public var primaryIssue: Issue? {
        detectedIssues.max(by: { $0.score < $1.score })
    }
    
    /// Whether analysis was served from cache
    public var wasCached: Bool {
        layersUsed.contains(.cache)
    }
    
    /// Human-readable summary
    public var summary: String {
        if isAcceptable {
            return "Content is acceptable"
        }
        
        if let primary = primaryIssue {
            return "Detected: \(primary.type.rawValue) (score: \(String(format: "%.2f", primary.score)))"
        }
        
        return "Content flagged (severity: \(String(format: "%.2f", severityScore)))"
    }
    
    /// All help messages for detected issues
    public var helpMessages: [String] {
        detectedIssues.map { $0.type.helpMessage }
    }
}

// MARK: - CustomStringConvertible

extension ModerationResult: CustomStringConvertible {
    public var description: String {
        """
        ModerationResult {
          level: \(level.rawValue)
          acceptable: \(isAcceptable)
          severity: \(String(format: "%.3f", severityScore))
          issues: \(detectedIssues.count)
          message: "\(userMessage)"
          processing: \(String(format: "%.1f", processingTimeMs))ms
          layers: \(layersUsed.map { $0.rawValue }.joined(separator: ", "))
        }
        """
    }
}

// MARK: - Convenience Constructors

public extension ModerationResult {
    /// Create result for acceptable content
    static func acceptable(
        text: String,
        processingTimeMs: Double,
        layersUsed: [AnalysisLayer]
    ) -> ModerationResult {
        ModerationResult(
            isAcceptable: true,
            level: .ok,
            severityScore: 0.0,
            detectedIssues: [],
            reasons: [],
            userMessage: "Content is acceptable",
            analyzedText: text,
            processingTimeMs: processingTimeMs,
            layersUsed: layersUsed
        )
    }
    
    /// Create cached result
    static func cached(result: ModerationResult) -> ModerationResult {
        ModerationResult(
            isAcceptable: result.isAcceptable,
            level: result.level,
            severityScore: result.severityScore,
            detectedIssues: result.detectedIssues,
            reasons: result.reasons,
            userMessage: result.userMessage,
            analyzedText: result.analyzedText,
            processingTimeMs: 0.0,
            layersUsed: [.cache] + result.layersUsed
        )
    }
    
    /// Generate user-facing message based on level and reasons
    static func generateUserMessage(level: ModerationLevel, reasons: [ModerationReason]) -> String {
        switch level {
        case .ok:
            return "Content is acceptable"
            
        case .recommendation:
            if reasons.isEmpty {
                return "Consider rephrasing your text"
            }
            let reasonList = reasons.map { $0.description }.joined(separator: ", ")
            return "We detected: \(reasonList). Consider rephrasing your text"
            
        case .warning:
            if reasons.isEmpty {
                return "Your content may contain inappropriate elements"
            }
            let reasonList = reasons.map { $0.description }.joined(separator: ", ")
            return "We believe your text contains \(reasonList). Please try to change the text"
            
        case .critical:
            if reasons.isEmpty {
                return "This content is not allowed"
            }
            let reasonList = reasons.map { $0.description }.joined(separator: ", ")
            return "This is not allowed because: \(reasonList)"
        }
    }
    
    /// Determine moderation level from severity score and issues
    static func determineLevel(severityScore: Double, detectedIssues: [Issue]) -> ModerationLevel {
        if detectedIssues.contains(where: { $0.type == .criticalKeyword }) {
            return .critical
        }
        
        if severityScore >= 0.85 {
            return .critical
        }
        
        if severityScore >= 0.6 {
            return .warning
        }
        
        if severityScore >= 0.3 {
            return .recommendation
        }
        
        return .ok
    }
    
    /// Convert detected issues to moderation reasons
    static func issuesToReasons(_ issues: [Issue]) -> [ModerationReason] {
        issues.map { issue in
            ModerationReason(
                category: ReasonCategory.from(issueType: issue.type),
                confidence: issue.score,
                source: issue.source.rawValue
            )
        }
    }
}

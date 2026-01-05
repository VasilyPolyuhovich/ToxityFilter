import Foundation

/// Moderation severity level with user-facing messages
public enum ModerationLevel: String, Codable, Sendable {
    case ok
    case recommendation
    case warning
    case critical
    
    /// User-facing description of the moderation level
    public var description: String {
        switch self {
        case .ok:
            return "Content is acceptable"
        case .recommendation:
            return "Consider rephrasing your text"
        case .warning:
            return "Your content may contain inappropriate elements"
        case .critical:
            return "This content is not allowed"
        }
    }
    
    /// Severity score range for this level
    public var severityRange: ClosedRange<Double> {
        switch self {
        case .ok:
            return 0.0...0.3
        case .recommendation:
            return 0.3...0.6
        case .warning:
            return 0.6...0.85
        case .critical:
            return 0.85...10.0
        }
    }
}

/// Detailed reason for moderation decision
public struct ModerationReason: Codable, Sendable {
    public let category: ReasonCategory
    public let confidence: Double  // 0.0 - 1.0
    public let source: String      // Which model/layer detected it
    
    public init(category: ReasonCategory, confidence: Double, source: String) {
        self.category = category
        self.confidence = confidence
        self.source = source
    }
    
    /// Human-readable description with confidence
    public var description: String {
        let percentage = Int(confidence * 100)
        return "\(category.displayName) (\(percentage)% confidence)"
    }
}

/// Categories of content issues that can be detected
public enum ReasonCategory: String, Codable, CaseIterable, Sendable {
    // Harmful content from ToxicityDetector v3
    case hateSpeech = "hate_speech"
    case offensiveLanguage = "offensive_language"
    case threats
    case toxicity
    
    // Keywords
    case criticalKeywords = "critical_keywords"
    
    /// User-facing display name
    public var displayName: String {
        switch self {
        case .hateSpeech:
            return "hate speech"
        case .offensiveLanguage:
            return "offensive language"
        case .threats:
            return "threatening language"
        case .toxicity:
            return "toxic content"
        case .criticalKeywords:
            return "prohibited terms"
        }
    }
    
    /// Map from IssueType to ReasonCategory
    public static func from(issueType: ModerationResult.IssueType) -> ReasonCategory {
        switch issueType {
        case .toxicity: return .toxicity
        case .threat: return .threats
        case .insult: return .offensiveLanguage
        case .obscenity: return .offensiveLanguage
        case .hateSpeech: return .hateSpeech
        case .criticalKeyword: return .criticalKeywords
        }
    }
}

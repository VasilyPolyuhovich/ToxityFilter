import Foundation

/// Main content moderation pipeline with multi-level filtering
/// Uses: Cache → Keywords (optional) → CoreML ToxicityDetector v3 (toxic-bert domain-adapted)
@available(iOS 15.0, *)
public actor ContentModerator {

    // MARK: - Properties

    private let tokenizer: BERTTokenizer
    private let predictor: CoreMLPredictor
    private let cache: LRUCache<String, ModerationResult>
    private let keywordFilter: KeywordFilter
    private let config: ModerationConfig

    // MARK: - Initialization

    /// Initialize content moderator with configuration preset
    /// - Parameters:
    ///   - config: Moderation configuration preset (default: .default)
    ///   - bundle: Bundle containing models and resources (defaults to ToxityFilter bundle)
    public init(
        config: ModerationConfig = .default,
        bundle: Bundle? = nil
    ) throws {
        let resourceBundle = bundle ?? Bundle.module

        // Load BERT tokenizer for ToxicityDetector
        guard let vocabURL = resourceBundle.url(forResource: "ToxicityDetector_vocab", withExtension: "txt"),
              let specialTokensURL = resourceBundle.url(forResource: "ToxicityDetector_special_tokens", withExtension: "txt") else {
            throw NSError(
                domain: "ToxityFilter",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to find ToxicityDetector vocabulary or special tokens file in bundle"]
            )
        }

        self.tokenizer = try BERTTokenizer(
            vocabularyURL: vocabURL,
            specialTokensURL: specialTokensURL,
            maxLength: 128
        )

        self.predictor = CoreMLPredictor(bundle: resourceBundle)
        self.cache = LRUCache(capacity: config.cacheSize)
        self.keywordFilter = KeywordFilter(bundle: resourceBundle)
        self.config = config
    }

    // MARK: - Simple API

    /// Quick check if text is safe
    /// - Parameter text: Text to check
    /// - Returns: true if content is acceptable
    public func isSafe(_ text: String) async -> Bool {
        let result = await analyze(text)
        return result.isAcceptable
    }

    /// Check text with reason on rejection
    /// - Parameter text: Text to check
    /// - Returns: Tuple with safety status and optional reason message
    public func check(_ text: String) async -> (isSafe: Bool, reason: String?) {
        let result = await analyze(text)
        return (result.isAcceptable, result.isAcceptable ? nil : result.userMessage)
    }

    // MARK: - Batch API

    /// Check multiple texts
    /// - Parameter texts: Array of texts to check
    /// - Returns: Array of boolean results
    public func isSafe(_ texts: [String]) async -> [Bool] {
        var results: [Bool] = []
        for text in texts {
            results.append(await isSafe(text))
        }
        return results
    }

    // MARK: - Detailed API

    /// Full analysis with detailed result
    /// - Parameter text: Text to analyze
    /// - Returns: Detailed moderation result
    public func analyze(_ text: String) async -> ModerationResult {
        let startTime = Date()
        var layersUsed: [ModerationResult.AnalysisLayer] = []
        var issues: [ModerationResult.Issue] = []

        // Normalize text
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Empty text is acceptable
        guard !normalizedText.isEmpty else {
            return .acceptable(
                text: text,
                processingTimeMs: Date().timeIntervalSince(startTime) * 1000,
                layersUsed: []
            )
        }

        // Layer 1: Cache check
        if let cachedResult = cache.get(normalizedText) {
            return .cached(result: cachedResult)
        }

        // Layer 2: Keyword filter (if enabled)
        if config.pipelineMode != .mlOnly {
            if let keywordIssues = keywordFilter.check(normalizedText) {
                issues.append(contentsOf: keywordIssues)
                layersUsed.append(.keywordFilter)
            }
        }

        // Layer 3: ML Model (if enabled)
        if config.pipelineMode != .keywordsOnly {
            let mlIssues = await analyzeWithToxicityModel(normalizedText)
            issues.append(contentsOf: mlIssues.issues)
            if !mlIssues.layers.isEmpty {
                layersUsed.append(contentsOf: mlIssues.layers)
            }
        }

        // Create final result
        let result = createResult(
            text: text,
            issues: issues,
            startTime: startTime,
            layersUsed: layersUsed
        )

        // Cache result
        cache.set(result, forKey: normalizedText)

        return result
    }

    /// Legacy method name - calls analyze()
    @available(*, deprecated, renamed: "analyze")
    public func moderate(_ text: String) async -> ModerationResult {
        await analyze(text)
    }

    /// Clear cached results
    public func clearCache() {
        cache.removeAll()
    }

    /// Get cache statistics
    public func getCacheStats() -> LRUCache<String, ModerationResult>.Statistics {
        cache.statistics
    }

    // MARK: - Private Methods

    private func analyzeWithToxicityModel(_ text: String) async -> (issues: [ModerationResult.Issue], layers: [ModerationResult.AnalysisLayer]) {
        var issues: [ModerationResult.Issue] = []
        var layers: [ModerationResult.AnalysisLayer] = []

        do {
            let (inputIds, attentionMask) = tokenizer.tokenize(text)
            let prediction = try await predictor.predictToxicity(
                inputIds: inputIds,
                attentionMask: attentionMask
            )
            layers.append(.toxicityModel)

            // Map toxicity labels to issue types
            let labelToIssueType: [ToxicityLabel: ModerationResult.IssueType] = [
                .toxic: .toxicity,
                .severeToxic: .toxicity,
                .obscene: .obscenity,
                .threat: .threat,
                .insult: .insult,
                .identityHate: .hateSpeech
            ]

            // Check each toxicity class against threshold
            for (label, score) in prediction.scores {
                if score > config.toxicityThreshold {
                    if let issueType = labelToIssueType[label] {
                        issues.append(ModerationResult.Issue(
                            type: issueType,
                            score: score,
                            source: .toxicityModel
                        ))
                    }
                }
            }

        } catch {
            layers.append(.toxicityModel)
        }

        return (issues, layers)
    }

    private func createResult(
        text: String,
        issues: [ModerationResult.Issue],
        startTime: Date,
        layersUsed: [ModerationResult.AnalysisLayer]
    ) -> ModerationResult {
        let processingTime = Date().timeIntervalSince(startTime) * 1000

        // Calculate combined severity
        let severityScore: Double
        if issues.isEmpty {
            severityScore = 0.0
        } else {
            let weightedScores = issues.map { issue -> Double in
                var weight = 1.0
                switch issue.type {
                case .threat:
                    weight = 2.0
                case .hateSpeech:
                    weight = 1.8
                case .criticalKeyword:
                    weight = 2.5
                case .toxicity:
                    weight = 1.5
                default:
                    weight = 1.0
                }
                return issue.score * weight
            }
            severityScore = min(weightedScores.max() ?? 0.0, 1.0)
        }

        // Decision logic
        let isAcceptable: Bool
        if issues.isEmpty {
            isAcceptable = true
        } else {
            let hasCritical = issues.contains { issue in
                let isCritical = [.threat, .hateSpeech, .criticalKeyword, .toxicity].contains(issue.type)
                return isCritical && issue.score >= config.toxicityThreshold
            }
            let hasKeywordBlock = issues.contains { $0.source == .keywordFilter && $0.score >= 0.70 }
            isAcceptable = !hasCritical && !hasKeywordBlock
        }

        // Generate moderation level
        let level = ModerationResult.determineLevel(
            severityScore: severityScore,
            detectedIssues: issues
        )

        // Convert issues to reasons
        let reasons = ModerationResult.issuesToReasons(issues)

        // Generate user message
        let userMessage = ModerationResult.generateUserMessage(
            level: level,
            reasons: reasons
        )

        return ModerationResult(
            isAcceptable: isAcceptable,
            level: level,
            severityScore: severityScore,
            detectedIssues: issues,
            reasons: reasons,
            userMessage: userMessage,
            analyzedText: text,
            processingTimeMs: processingTime,
            layersUsed: layersUsed
        )
    }
}

// MARK: - Keyword Filter

private struct KeywordFilter {
    private let criticalPatterns: [(keyword: String, type: ModerationResult.IssueType)]
    private let moderateKeywords: Set<String>

    init(bundle: Bundle? = nil) {
        let resourceBundle = bundle ?? Bundle.module

        // Load critical keywords from file
        var patterns: [(String, ModerationResult.IssueType)] = []
        if let criticalURL = resourceBundle.url(forResource: "keywords_critical", withExtension: "txt"),
           let content = try? String(contentsOf: criticalURL, encoding: .utf8) {

            var currentType: ModerationResult.IssueType = .criticalKeyword
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

                if trimmed == "[hate]" {
                    currentType = .hateSpeech
                } else if trimmed.hasPrefix("[") {
                    currentType = .criticalKeyword
                } else {
                    patterns.append((trimmed.lowercased(), currentType))
                }
            }
        }
        self.criticalPatterns = patterns

        // Load moderate keywords from file
        var moderate: Set<String> = []
        if let moderateURL = resourceBundle.url(forResource: "keywords_moderate", withExtension: "txt"),
           let content = try? String(contentsOf: moderateURL, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                moderate.insert(trimmed.lowercased())
            }
        }
        self.moderateKeywords = moderate
    }

    func check(_ text: String) -> [ModerationResult.Issue]? {
        var issues: [ModerationResult.Issue] = []

        // Check critical keywords
        for (keyword, issueType) in criticalPatterns {
            if text.contains(keyword) {
                issues.append(ModerationResult.Issue(
                    type: issueType,
                    score: 0.70,
                    source: .keywordFilter
                ))
            }
        }

        // Check moderate keywords only if no critical found
        if issues.isEmpty {
            for keyword in moderateKeywords {
                if text.contains(keyword) {
                    issues.append(ModerationResult.Issue(
                        type: .criticalKeyword,
                        score: 0.50,
                        source: .keywordFilter
                    ))
                    break
                }
            }
        }

        return issues.isEmpty ? nil : issues
    }
}

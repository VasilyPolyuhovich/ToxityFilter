import Testing
@testable import ToxityFilter

@Suite("ModerationResult Tests")
struct ModerationTests {

    @Test("ModerationResult creation")
    func testModerationResultCreation() {
        let result = ModerationResult(
            isAcceptable: false,
            level: .warning,
            severityScore: 0.85,
            detectedIssues: [
                ModerationResult.Issue(
                    type: .toxicity,
                    score: 0.85,
                    source: .toxicityModel
                )
            ],
            reasons: [],
            userMessage: "Content flagged",
            analyzedText: "test text",
            processingTimeMs: 15.5,
            layersUsed: [.keywordFilter, .toxicityModel]
        )

        #expect(!result.isAcceptable)
        #expect(abs(result.severityScore - 0.85) < 0.001)
        #expect(result.detectedIssues.count == 1)
        #expect(abs(result.processingTimeMs - 15.5) < 0.1)
        #expect(!result.wasCached)
    }

    @Test("Primary issue detection")
    func testPrimaryIssue() {
        let result = ModerationResult(
            isAcceptable: false,
            level: .warning,
            severityScore: 0.8,
            detectedIssues: [
                ModerationResult.Issue(type: .toxicity, score: 0.6, source: .toxicityModel),
                ModerationResult.Issue(type: .hateSpeech, score: 0.8, source: .toxicityModel),
                ModerationResult.Issue(type: .insult, score: 0.5, source: .toxicityModel)
            ],
            reasons: [],
            userMessage: "Content flagged",
            analyzedText: "test",
            processingTimeMs: 10,
            layersUsed: [.toxicityModel]
        )

        #expect(result.primaryIssue?.type == .hateSpeech)
        if let score = result.primaryIssue?.score {
            #expect(abs(score - 0.8) < 0.001)
        }
    }

    @Test("Acceptable result creation")
    func testAcceptableResult() {
        let result = ModerationResult.acceptable(
            text: "This is fine",
            processingTimeMs: 5.0,
            layersUsed: [.keywordFilter]
        )

        #expect(result.isAcceptable)
        #expect(result.severityScore == 0.0)
        #expect(result.detectedIssues.isEmpty)
    }

    @Test("Cached result creation")
    func testCachedResult() {
        let original = ModerationResult(
            isAcceptable: false,
            level: .warning,
            severityScore: 0.7,
            detectedIssues: [
                ModerationResult.Issue(type: .toxicity, score: 0.7, source: .toxicityModel)
            ],
            reasons: [],
            userMessage: "Content flagged",
            analyzedText: "test",
            processingTimeMs: 20.0,
            layersUsed: [.toxicityModel]
        )

        let cached = ModerationResult.cached(result: original)

        #expect(cached.wasCached)
        #expect(cached.processingTimeMs == 0.0)
        #expect(cached.layersUsed.first == .cache)
        #expect(cached.isAcceptable == original.isAcceptable)
    }

    @Test("Issue type help messages")
    func testIssueTypeHelpMessages() {
        #expect(!ModerationResult.IssueType.toxicity.helpMessage.isEmpty)
        #expect(!ModerationResult.IssueType.hateSpeech.helpMessage.isEmpty)
        #expect(!ModerationResult.IssueType.threat.helpMessage.isEmpty)
        #expect(!ModerationResult.IssueType.insult.helpMessage.isEmpty)
    }

    @Test("Layer priority order")
    func testLayerPriority() {
        #expect(
            ModerationResult.AnalysisLayer.cache.priority <
            ModerationResult.AnalysisLayer.keywordFilter.priority
        )

        #expect(
            ModerationResult.AnalysisLayer.keywordFilter.priority <
            ModerationResult.AnalysisLayer.toxicityModel.priority
        )
    }

    @Test("Result summary generation")
    func testResultSummary() {
        let acceptable = ModerationResult.acceptable(
            text: "test",
            processingTimeMs: 5,
            layersUsed: []
        )
        #expect(acceptable.summary.contains("acceptable"))

        let flagged = ModerationResult(
            isAcceptable: false,
            level: .warning,
            severityScore: 0.8,
            detectedIssues: [
                ModerationResult.Issue(type: .toxicity, score: 0.8, source: .toxicityModel)
            ],
            reasons: [],
            userMessage: "Content flagged",
            analyzedText: "test",
            processingTimeMs: 10,
            layersUsed: [.toxicityModel]
        )
        #expect(flagged.summary.contains("Toxicity"))
    }
}

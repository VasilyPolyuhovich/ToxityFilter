import Testing
import Foundation
@testable import ToxityFilter

@Suite("ContentModerator Integration Tests")
struct ContentModeratorIntegrationTests {

    // MARK: - Initialization Tests

    @Test("ContentModerator initializes successfully")
    func testInitialization() async throws {
        let moderator = try ContentModerator()
        #expect(moderator != nil)
    }

    @Test("ContentModerator initializes with config presets")
    func testInitializationWithPresets() async throws {
        let defaultMod = try ContentModerator(config: .default)
        let strictMod = try ContentModerator(config: .strict)
        let lenientMod = try ContentModerator(config: .lenient)
        let fastMod = try ContentModerator(config: .fast)
        
        #expect(defaultMod != nil)
        #expect(strictMod != nil)
        #expect(lenientMod != nil)
        #expect(fastMod != nil)
    }

    // MARK: - Violence Detection

    @Test("Detects violence in text")
    func testViolenceDetection() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        #expect(!result.isAcceptable, "Violence should be flagged")
        #expect(result.severityScore > 0.5, "Severity should be high")
        #expect(!result.detectedIssues.isEmpty, "Should have detected issues")
        #expect(result.layersUsed.contains(.toxicityModel), "Should use toxicity model")
    }

    @Test("Detects threats")
    func testThreatDetection() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I know where you live, watch your back")

        #expect(!result.isAcceptable)
        #expect(result.severityScore > 0.5)
    }

    @Test("Detects hate speech")
    func testHateSpeechDetection() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I hate those people, they are all disgusting and worthless")

        #expect(!result.isAcceptable)
        #expect(result.detectedIssues.count > 0)
    }

    // MARK: - Safe Content

    @Test("Positive content is acceptable")
    func testPositiveContent() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("What a beautiful day! I'm so grateful for my friends and family")

        #expect(result.isAcceptable)
        #expect(result.severityScore < 0.2)
        #expect(result.detectedIssues.isEmpty)
    }

    @Test("Neutral content is acceptable")
    func testNeutralContent() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("The weather forecast shows rain tomorrow afternoon")

        #expect(result.isAcceptable)
        #expect(result.detectedIssues.isEmpty)
    }

    // MARK: - Processing Time

    @Test("Processing time is tracked")
    func testProcessingTimeTracking() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        #expect(result.processingTimeMs > 0, "Processing time should be tracked")
        #expect(result.processingTimeMs < 500, "Processing should be reasonable")
    }

    // MARK: - Layer Priority

    @Test("Layers are used in correct order")
    func testLayerPriority() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        #expect(result.layersUsed.contains(.toxicityModel))

        let priorities = result.layersUsed.map { $0.priority }
        for i in 0..<(priorities.count - 1) {
            #expect(priorities[i] <= priorities[i + 1], "Layers should be in priority order")
        }
    }

    // MARK: - Multiple Moderations

    @Test("Multiple moderations work correctly")
    func testMultipleModerations() async throws {
        let moderator = try ContentModerator()

        let testCases = [
            ("I want to kill all dogs", false),
            ("What a beautiful day", true),
            ("I hate those people", false),
            ("Hello, how are you?", true)
        ]

        for (text, shouldBeAcceptable) in testCases {
            let result = await moderator.analyze(text)

            if shouldBeAcceptable {
                #expect(result.isAcceptable, "'\(text)' should be acceptable")
            } else {
                #expect(!result.isAcceptable, "'\(text)' should NOT be acceptable")
            }
        }
    }

    // MARK: - Edge Cases

    @Test("Handles empty text")
    func testEmptyText() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("")

        #expect(result.isAcceptable)
        #expect(result.detectedIssues.isEmpty)
    }

    @Test("Handles very long text")
    func testLongText() async throws {
        let moderator = try ContentModerator()

        let longText = String(repeating: "This is a test sentence. ", count: 100)
        let result = await moderator.analyze(longText)

        #expect(result.processingTimeMs < 2000, "Long text should still process reasonably")
    }

    // MARK: - Issue Validation

    @Test("Issue scores are valid")
    func testIssueScoresValid() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        for issue in result.detectedIssues {
            #expect(issue.score >= 0.0 && issue.score <= 1.0, "Issue score should be in [0,1]")
            #expect(!issue.score.isNaN, "Issue score should not be NaN")
        }
    }

    @Test("Severity score is valid")
    func testSeverityScoreValid() async throws {
        let moderator = try ContentModerator()

        let testTexts = [
            "I want to kill all dogs",
            "What a beautiful day"
        ]

        for text in testTexts {
            let result = await moderator.analyze(text)

            #expect(result.severityScore >= 0.0 && result.severityScore <= 1.0, "Severity should be in [0,1]")
            #expect(!result.severityScore.isNaN, "Severity should not be NaN")
        }
    }

    // MARK: - Result Summary

    @Test("Result summary is informative")
    func testResultSummary() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        let summary = result.summary
        #expect(!summary.isEmpty, "Summary should not be empty")
    }

    @Test("Primary issue is identified correctly")
    func testPrimaryIssue() async throws {
        let moderator = try ContentModerator()

        let result = await moderator.analyze("I want to kill all dogs")

        if !result.detectedIssues.isEmpty {
            let primary = result.primaryIssue
            #expect(primary != nil, "Should identify primary issue")

            let maxScore = result.detectedIssues.map { $0.score }.max() ?? 0
            #expect(primary?.score == maxScore, "Primary issue should have highest score")
        }
    }
    
    // MARK: - Simple API Tests
    
    @Test("isSafe returns correct boolean")
    func testIsSafeAPI() async throws {
        let moderator = try ContentModerator()
        
        let safe = await moderator.isSafe("Hello world!")
        #expect(safe == true)
        
        let unsafe = await moderator.isSafe("I hate you, die!")
        #expect(unsafe == false)
    }
    
    @Test("check returns reason on rejection")
    func testCheckAPI() async throws {
        let moderator = try ContentModerator()
        
        let (safe, safeReason) = await moderator.check("Have a nice day!")
        #expect(safe == true)
        #expect(safeReason == nil)
        
        let (unsafe, unsafeReason) = await moderator.check("You're worthless garbage")
        #expect(unsafe == false)
        #expect(unsafeReason != nil)
    }
}

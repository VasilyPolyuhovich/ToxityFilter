import XCTest
@testable import ToxityFilter

final class TokenizerTests: XCTestCase {
    
    var tokenizer: BERTTokenizer!
    
    override func setUp() async throws {
        // Create mock vocabulary for testing
        let mockVocab = """
        <s>
        </s>
        <pad>
        <unk>
        <mask>
        hello
        world
        test
        ##ing
        ##ed
        good
        bad
        """
        
        let mockTokens = """
        cls_token=<s>
        sep_token=</s>
        pad_token=<pad>
        unk_token=<unk>
        mask_token=<mask>
        """
        
        let tempDir = FileManager.default.temporaryDirectory
        let vocabURL = tempDir.appendingPathComponent("test_vocab.txt")
        let tokensURL = tempDir.appendingPathComponent("test_tokens.txt")
        
        try mockVocab.write(to: vocabURL, atomically: true, encoding: .utf8)
        try mockTokens.write(to: tokensURL, atomically: true, encoding: .utf8)
        
        tokenizer = try BERTTokenizer(
            vocabularyURL: vocabURL,
            specialTokensURL: tokensURL,
            maxLength: 16
        )
    }
    
    func testBasicTokenization() {
        let (inputIds, attentionMask) = tokenizer.tokenize("hello world")
        
        // Should have: <s> hello world </s> + padding
        XCTAssertEqual(inputIds.count, 16, "Output should be padded to max_length")
        XCTAssertEqual(attentionMask.count, 16)
        
        // First token should be CLS
        XCTAssertEqual(inputIds[0], 0, "First token should be <s> (CLS)")
        
        // Check attention mask has 1s for real tokens, 0s for padding
        XCTAssertEqual(attentionMask[0], 1)
        XCTAssertEqual(attentionMask[1], 1)
        XCTAssertEqual(attentionMask[2], 1)
        XCTAssertEqual(attentionMask[3], 1) // SEP token
        XCTAssertEqual(attentionMask[4], 0) // First padding
    }
    
    func testEmptyString() {
        let (inputIds, attentionMask) = tokenizer.tokenize("")
        
        // Should have: <s> </s> + padding
        XCTAssertEqual(inputIds.count, 16)
        XCTAssertEqual(inputIds[0], 0) // CLS
        XCTAssertEqual(inputIds[1], 1) // SEP
        XCTAssertEqual(attentionMask[0], 1)
        XCTAssertEqual(attentionMask[1], 1)
        XCTAssertEqual(attentionMask[2], 0) // Padding
    }
    
    func testWordPieceTokenization() {
        let (inputIds, _) = tokenizer.tokenize("testing")
        
        // Should tokenize as: <s> test ##ing </s>
        XCTAssertEqual(inputIds[0], 0) // <s>
        XCTAssertEqual(inputIds[1], 7) // test
        XCTAssertEqual(inputIds[2], 8) // ##ing
        XCTAssertEqual(inputIds[3], 1) // </s>
    }
    
    func testTruncation() {
        // Create very long text that exceeds max_length
        let longText = String(repeating: "hello ", count: 20)
        let (inputIds, attentionMask) = tokenizer.tokenize(longText)
        
        XCTAssertEqual(inputIds.count, 16, "Should truncate to max_length")
        XCTAssertEqual(inputIds.last, 1, "Last token should be SEP after truncation")
        
        // All tokens should have attention (no padding when truncated)
        XCTAssertTrue(attentionMask.allSatisfy { $0 == 1 })
    }
    
    func testUnknownWords() {
        let (inputIds, _) = tokenizer.tokenize("xyz123")
        
        // Unknown word should be tokenized as <unk>
        XCTAssertTrue(inputIds.contains(3), "Should contain <unk> token")
    }
}

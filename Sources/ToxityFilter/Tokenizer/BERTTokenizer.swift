import Foundation

/// WordPiece tokenizer compatible with BERT/RoBERTa models
/// Implements offline tokenization using exported vocabulary from HuggingFace models
public final class BERTTokenizer {
    
    // MARK: - Properties
    
    private let vocabulary: [String: Int]
    private let invertedVocabulary: [Int: String]
    private let maxLength: Int
    private let vocabularySize: Int
    
    // Special tokens
    private let clsToken: String
    private let sepToken: String
    private let padToken: String
    private let unkToken: String
    private let maskToken: String
    
    private let clsTokenId: Int
    private let sepTokenId: Int
    private let padTokenId: Int
    private let unkTokenId: Int
    
    // MARK: - Initialization
    
    /// Initialize tokenizer with vocabulary file
    /// - Parameters:
    ///   - vocabularyURL: URL to vocab.txt file exported from Python script
    ///   - specialTokensURL: URL to special_tokens.txt file
    ///   - maxLength: Maximum sequence length (default: 128)
    public init(
        vocabularyURL: URL,
        specialTokensURL: URL,
        maxLength: Int = 128
    ) throws {
        self.maxLength = maxLength
        
        // Load special tokens
        let specialTokensData = try String(contentsOf: specialTokensURL, encoding: .utf8)
        var specialTokensMap: [String: String] = [:]
        
        for line in specialTokensData.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                specialTokensMap[String(parts[0])] = String(parts[1])
            }
        }
        
        self.clsToken = specialTokensMap["cls_token"] ?? "<s>"
        self.sepToken = specialTokensMap["sep_token"] ?? "</s>"
        self.padToken = specialTokensMap["pad_token"] ?? "<pad>"
        self.unkToken = specialTokensMap["unk_token"] ?? "<unk>"
        self.maskToken = specialTokensMap["mask_token"] ?? "<mask>"
        
        // Load vocabulary
        let vocabData = try String(contentsOf: vocabularyURL, encoding: .utf8)
        let tokens = vocabData.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        var vocab: [String: Int] = [:]
        var invertedVocab: [Int: String] = [:]
        
        for (index, token) in tokens.enumerated() {
            vocab[token] = index
            invertedVocab[index] = token
        }
        
        self.vocabulary = vocab
        self.invertedVocabulary = invertedVocab
        
        // Get special token IDs
        guard let clsId = vocab[clsToken],
              let sepId = vocab[sepToken],
              let padId = vocab[padToken],
              let unkId = vocab[unkToken] else {
            throw TokenizerError.missingSpecialTokens
        }
        
        self.clsTokenId = clsId
        self.sepTokenId = sepId
        self.padTokenId = padId
        self.unkTokenId = unkId
        
        // Calculate vocabulary size (max ID + 1)
        self.vocabularySize = vocab.values.max().map { $0 + 1 } ?? 0
    }
    
    // MARK: - Tokenization
    
    /// Tokenize text and return input IDs and attention mask
    /// - Parameter text: Input text to tokenize
    /// - Returns: Tuple of (inputIds, attentionMask)
    public func tokenize(_ text: String) -> (inputIds: [Int32], attentionMask: [Int32]) {
        // Basic preprocessing
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Early truncation: limit text to ~500 chars to prevent processing extremely long texts
        // This prevents memory issues and ensures token count stays reasonable
        if cleanedText.count > 500 {
            cleanedText = String(cleanedText.prefix(500))
        }
        
        // Tokenize into words
        let words = cleanedText.components(separatedBy: .whitespaces)
        var tokens: [String] = [clsToken]
        
        // Apply WordPiece tokenization
        for word in words where !word.isEmpty {
            let wordTokens = wordpieceTokenize(word)
            tokens.append(contentsOf: wordTokens)
        }
        
        tokens.append(sepToken)
        
        // Convert to IDs with bounds checking
        var inputIds = tokens.map { token -> Int32 in
            let tokenId = vocabulary[token] ?? unkTokenId
            // Ensure token ID is within vocabulary bounds
            // CoreML expects IDs in range [0, vocabularySize)
            if tokenId >= vocabularySize || tokenId < 0 {
                return Int32(unkTokenId)
            }
            return Int32(tokenId)
        }
        
        // Truncate if needed
        if inputIds.count > maxLength {
            inputIds = Array(inputIds.prefix(maxLength - 1))
            // Double-check sepTokenId is valid before appending
            let validSepId = (sepTokenId < vocabularySize && sepTokenId >= 0) ? sepTokenId : unkTokenId
            inputIds.append(Int32(validSepId))
        }
        
        // Create attention mask (1 for real tokens, 0 for padding)
        var attentionMask = Array(repeating: Int32(1), count: inputIds.count)
        
        // Pad to max length
        let paddingLength = maxLength - inputIds.count
        if paddingLength > 0 {
            // Ensure padTokenId is valid
            let validPadId = (padTokenId < vocabularySize && padTokenId >= 0) ? padTokenId : 0
            inputIds.append(contentsOf: Array(repeating: Int32(validPadId), count: paddingLength))
            attentionMask.append(contentsOf: Array(repeating: Int32(0), count: paddingLength))
        }
        
        return (inputIds, attentionMask)
    }
    
    // MARK: - Private Methods
    
    /// Apply WordPiece tokenization to a word
    private func wordpieceTokenize(_ word: String) -> [String] {
        let maxInputCharsPerWord = 100
        
        if word.count > maxInputCharsPerWord {
            return [unkToken]
        }
        
        var tokens: [String] = []
        var startIndex = word.startIndex
        
        while startIndex < word.endIndex {
            var endIndex = word.endIndex
            var foundSubtoken: String?
            
            // Try to find the longest matching subtoken
            while startIndex < endIndex {
                let substring = String(word[startIndex..<endIndex])
                let subtoken = startIndex == word.startIndex ? substring : "##\(substring)"
                
                if vocabulary.keys.contains(subtoken) {
                    foundSubtoken = subtoken
                    break
                }
                
                endIndex = word.index(before: endIndex)
            }
            
            if let subtoken = foundSubtoken {
                tokens.append(subtoken)
                startIndex = endIndex
            } else {
                // No match found, use unknown token
                tokens.append(unkToken)
                break
            }
        }
        
        return tokens
    }
}

// MARK: - Error Types

public enum TokenizerError: Error, LocalizedError {
    case missingSpecialTokens
    case invalidVocabulary
    case fileNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .missingSpecialTokens:
            return "Required special tokens not found in vocabulary"
        case .invalidVocabulary:
            return "Vocabulary file is invalid or corrupted"
        case .fileNotFound(let filename):
            return "Required file not found: \(filename)"
        }
    }
}

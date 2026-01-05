# ToxityFilter

A Swift SDK for real-time content moderation on iOS and macOS using on-device CoreML models.

## Features

- **On-device ML inference** - No API calls, works offline, privacy-preserving
- **ToxicityDetector v3** - Domain-adapted toxic-bert model with 99.9% accuracy on affirmations
- **Multi-layer pipeline** - ML model + keyword filter for comprehensive moderation
- **Simple API** - `isSafe()`, `check()`, `analyze()` methods
- **Configurable presets** - `default`, `strict`, `lenient`, `fast`
- **Swift Concurrency** - Full `async/await` support with `actor` isolation
- **LRU Cache** - Built-in caching for repeated queries
- **Batch processing** - Check multiple texts at once

## Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AnotherTechSource/ToxityFilter.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Quick Start

```swift
import ToxityFilter

// Initialize moderator
let moderator = try ContentModerator()

// Simple check
let isSafe = await moderator.isSafe("Hello, world!")
// true

// Check with reason
let (safe, reason) = await moderator.check("Your message here")
if !safe {
    print("Rejected: \(reason ?? "Unknown")")
}

// Full analysis
let result = await moderator.analyze("Text to analyze")
print(result.isAcceptable)     // true/false
print(result.level)            // .ok, .recommendation, .warning, .critical
print(result.severityScore)    // 0.0 - 1.0
print(result.processingTimeMs) // ~10-50ms
```

## API Reference

### ContentModerator

Main class for content moderation. Thread-safe `actor` with async methods.

```swift
public actor ContentModerator {
    // Initialize with configuration
    init(config: ModerationConfig = .default, bundle: Bundle? = nil) throws
    
    // Simple API
    func isSafe(_ text: String) async -> Bool
    func check(_ text: String) async -> (isSafe: Bool, reason: String?)
    
    // Batch API
    func isSafe(_ texts: [String]) async -> [Bool]
    
    // Detailed API
    func analyze(_ text: String) async -> ModerationResult
    
    // Cache management
    func clearCache()
    func getCacheStats() -> LRUCache<String, ModerationResult>.Statistics
}
```

### ModerationConfig

Configuration for moderation behavior.

```swift
public struct ModerationConfig {
    let toxicityThreshold: Double  // 0.0 - 1.0 (default: 0.5)
    let cacheSize: Int             // LRU cache capacity (default: 1000)
    let pipelineMode: PipelineMode // Processing mode
}
```

#### Presets

| Preset | Threshold | Pipeline | Use Case |
|--------|-----------|----------|----------|
| `.default` | 0.5 | ML + Keywords | Most applications, social apps |
| `.strict` | 0.3 | ML + Keywords | Children's apps, strict moderation |
| `.lenient` | 0.7 | ML only | Adult communities, creative writing |
| `.fast` | 0.5 | Keywords only | Live typing, high-throughput |

### PipelineMode

```swift
public enum PipelineMode {
    case mlOnly          // ToxicityDetector v3 only
    case mlWithKeywords  // ML + keyword filter (recommended)
    case keywordsOnly    // Keyword filter only (fastest)
}
```

### ModerationResult

Detailed result from `analyze()` method.

```swift
public struct ModerationResult {
    let isAcceptable: Bool           // Overall decision
    let level: ModerationLevel       // .ok, .recommendation, .warning, .critical
    let severityScore: Double        // Combined severity (0.0 - 1.0)
    let detectedIssues: [Issue]      // Individual issues found
    let reasons: [ModerationReason]  // Human-readable reasons
    let userMessage: String          // User-facing message
    let analyzedText: String         // Original text
    let processingTimeMs: Double     // Processing time
    let layersUsed: [AnalysisLayer]  // Which layers were used
    
    // Computed
    var primaryIssue: Issue?         // Highest-scoring issue
    var wasCached: Bool              // Cache hit
    var summary: String              // Human-readable summary
}
```

#### Issue Types

- `toxicity` - General toxic content
- `threat` - Threatening language
- `insult` - Insulting language
- `obscenity` - Obscene language
- `hateSpeech` - Hate speech
- `criticalKeyword` - Blocked keyword detected

## Configuration Examples

### Strict Moderation (Children's Apps)

```swift
let moderator = try ContentModerator(config: .strict)
// Catches more content with 30% threshold
```

### Lenient Moderation (Adult Communities)

```swift
let moderator = try ContentModerator(config: .lenient)
// ML only, 70% threshold
```

### Real-time Validation (Live Typing)

```swift
let moderator = try ContentModerator(config: .fast)
// Keywords only, sub-millisecond response
```

### Custom Configuration

```swift
let config = ModerationConfig(
    toxicityThreshold: 0.4,
    cacheSize: 5000,
    pipelineMode: .mlWithKeywords
)
let moderator = try ContentModerator(config: config)
```

## SwiftUI Integration

```swift
import SwiftUI
import ToxityFilter

struct ContentView: View {
    @State private var text = ""
    @State private var isSafe = true
    
    let moderator = try! ContentModerator()
    
    var body: some View {
        VStack {
            TextField("Enter message", text: $text)
                .onChange(of: text) { newValue in
                    Task {
                        isSafe = await moderator.isSafe(newValue)
                    }
                }
            
            if !isSafe {
                Text("Content may violate guidelines")
                    .foregroundColor(.red)
            }
        }
    }
}
```

## Architecture

```
ToxityFilter/
├── Pipeline/
│   └── ContentModerator.swift    # Main actor, orchestrates pipeline
├── Configuration/
│   └── ModerationConfig.swift    # Config + presets
├── Models/
│   ├── ModerationResult.swift    # Result types
│   └── ModerationLevel.swift     # Severity levels
├── ML/
│   ├── CoreMLPredictor.swift     # CoreML inference
│   └── BERTTokenizer.swift       # Text tokenization
├── Utilities/
│   └── LRUCache.swift            # Caching layer
└── Resources/
    ├── ToxicityDetector.mlpackage
    ├── keywords_critical.txt
    └── keywords_moderate.txt
```

### Processing Pipeline

1. **Cache Check** - Return cached result if available
2. **Keyword Filter** - Fast regex-based detection
3. **ML Inference** - ToxicityDetector v3 CoreML model
4. **Result Aggregation** - Combine scores, determine severity

## Performance

| Mode | Latency | Use Case |
|------|---------|----------|
| ML + Keywords | ~10-50ms | Standard moderation |
| Keywords only | <1ms | Real-time typing |
| Cached | <0.1ms | Repeated queries |

## ML Model

**ToxicityDetector v3** — CoreML model for on-device toxicity detection:

- Fine-tuned on ToxiGen dataset
- Domain-adapted for affirmations (99.9% SAFE accuracy)
- 6-class multi-label: toxic, severe_toxic, obscene, threat, insult, identity_hate
- Quantized INT8 for efficient on-device inference

## Project Structure

```
ToxityFilter/
├── ToxityFilterSDK/     # Main SDK package
├── Demo/                # Demo iOS app
├── Examples/            # Usage examples
├── ml_training/         # Model training scripts
└── Resources/Models/    # Additional models
```

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

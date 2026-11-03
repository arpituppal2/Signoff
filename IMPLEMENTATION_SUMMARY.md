# Signoff Per-Bucket Anti-Repetition Implementation

## Problem
The Signoff app was generating repetitive signoffs and template-like phrases (e.g., "all fizz no fizz", "from the chaos [...]") because:
1. Validation was bypassed in the main generation path (accepting all outputs)
2. Recent signoffs avoidance used a global list instead of per-bucket tracking
3. Standard bucket had no avoidance logic at all
4. Only last 8 signoffs were checked instead of the desired 10

## Solution Implemented

### 1. Added Per-Bucket Fetch Method (`PersistenceController.swift`)
```swift
public func fetchGenerations(forBucket bucketId: String, limit: Int = 10) throws -> [SignoffGeneration] {
    let descriptor = FetchDescriptor<SignoffGeneration>(
        predicate: #Predicate { $0.bucketId == bucketId },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = limit
    return try context.fetch(descriptor)
}
```

### 2. Updated AppState to Use Bucket-Specific Recent Signoffs (`AppState.swift`)
Changed line 561 from:
```swift
recentTexts: recentGenerations.map(\.text),
```
to:
```swift
recentTexts: (try? persistence.fetchGenerations(forBucket: bucket.id, limit: 10))?.map { $0.text } ?? [],
```

### 3. Increased Avoid-List Window to 10 (`PromptComposer.swift`)
Changed line 246 from:
```swift
.suffix(8)
```
to:
```swift
.suffix(10)
```

### 4. Re-enabled Mechanical Validation (`GenerationService.swift`)
Removed the bypass comment and restored the full validation pipeline that checks for:
- Template skeleton collisions (e.g., "all _ no _" patterns)
- Exact duplicates of recent/rejected signoffs
- Similes ("X like Y" patterns)
- Missing trailing comma
- Word count outside 2-7 range
- First word not capitalized
- Banned words (coffee, drink, beer, wine, whiskey)

## Expected Behavior After Changes
- Each bucket maintains its own history of the last 10 signoffs
- Generation avoids repeating signoffs from the same bucket's recent history
- Template-like outputs are caught by validation and trigger retries
- Standard bucket now participates in the avoidance mechanism (previously had none)
- All buckets use consistent 10-signoff avoidance window
- Quality validation prevents mechanical failures while allowing human judgment via the existing generateRaw path

## Files Modified
1. `Sources/SignoffCore/Persistence/PersistenceController.swift` - Added fetchGenerations(forBucket:)
2. `Sources/SignoffCore/AppState.swift` - Updated recentTexts to be bucket-specific
3. `Sources/SignoffCore/Generation/PromptComposer.swift` - Increased avoid-list to 10
4. `Sources/SignoffCore/Generation/GenerationService.swift` - Re-enabled validation logic

## Testing
Build verification: `swift build` succeeds
The changes align with the original design intent of storing "the last 10 signoffs it generated in each bucket and uses that to make sure not to generate that again."
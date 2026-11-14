import Foundation

public struct ReplacementRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var phrase: String
    public var replacement: String

    public init(id: UUID = UUID(), phrase: String, replacement: String) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
    }
}

public enum PhraseReplacement {
    /// Match literal phrases, ignoring case but preserving accents. Replacement case is exact.
    /// Letters, numbers, marks and underscores form words. Punctuation remains literal.
    /// Earlier rules reserve overlapping source ranges. Inserted text is never matched again.
    public static func apply(_ text: String, rules: [ReplacementRule]) -> String {
        let source = text as NSString
        var matches: [(NSRange, String)] = []
        for rule in rules where !rule.phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let literal = NSRegularExpression.escapedPattern(for: rule.phrase)
            let pattern = "(?<![\\p{L}\\p{N}\\p{M}_])" + literal + "(?![\\p{L}\\p{N}\\p{M}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                if !matches.contains(where: { NSIntersectionRange($0.0, match.range).length > 0 }) {
                    matches.append((match.range, rule.replacement))
                }
            }
        }
        let result = NSMutableString(string: text)
        for (range, replacement) in matches.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    public static func isDuplicate(_ phrase: String, in rules: [ReplacementRule], excluding id: UUID? = nil) -> Bool {
        rules.contains { $0.id != id && $0.phrase.compare(phrase, options: .caseInsensitive) == .orderedSame }
    }
}

public protocol ReplacementRuleStorage {
    func load() -> [ReplacementRule]
    func save(_ rules: [ReplacementRule]) throws
}

/// One private key leaves existing session and settings formats unchanged.
public struct UserDefaultsReplacementStorage: ReplacementRuleStorage {
    public static let key = "phraseReplacementRules"
    private let defaults: UserDefaults
    private struct Document: Codable {
        var version: Int = 1
        var rules: [ReplacementRule]
    }

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public static func appDefault() -> Self {
        Self(defaults: UserDefaults(suiteName: HandyConfiguration.appGroupIdentifier) ?? .standard)
    }

    public func load() -> [ReplacementRule] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(Document.self, from: data), document.version == 1 {
            return document.rules
        }
        // Accept an unversioned array from an earlier local format.
        return (try? decoder.decode([ReplacementRule].self, from: data)) ?? []
    }

    public func save(_ rules: [ReplacementRule]) throws {
        defaults.set(try JSONEncoder().encode(Document(rules: rules)), forKey: Self.key)
    }
}

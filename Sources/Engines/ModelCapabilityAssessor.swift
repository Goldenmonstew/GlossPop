import Foundation
import NaturalLanguage

enum ModelCapabilityLevel: Sendable, Equatable {
    case full
    case translationOnly
    case incompatible
    case inconclusive
}

enum ModelCapabilityStage: Sendable, Equatable {
    case translation
    case dictionary
    case sentence
}

enum ModelCapabilityIssue: Sendable, Equatable {
    case request(message: String, inconclusive: Bool)
    case emptyTranslation
    case invalidDictionary
    case invalidSentence
    case wrongLanguage(expectedCode: String, detectedCode: String?)
    case uncertainLanguage(expectedCode: String)
    case missingSentenceFixture(languageCode: String)

    var preventsVerdict: Bool {
        switch self {
        case .request(_, let inconclusive):
            return inconclusive
        case .uncertainLanguage, .missingSentenceFixture:
            return true
        case .emptyTranslation, .invalidDictionary, .invalidSentence, .wrongLanguage:
            return false
        }
    }
}

enum ModelCapabilityOutcome: Sendable, Equatable {
    case passed
    case failed(ModelCapabilityIssue)
    case skipped
}

struct ModelCapabilityCheck: Sendable, Equatable {
    let latency: Duration
    let outcome: ModelCapabilityOutcome

    static let skipped = ModelCapabilityCheck(latency: .zero, outcome: .skipped)

    var passed: Bool {
        if case .passed = outcome { return true }
        return false
    }
}

struct ModelCapabilityReport: Sendable, Equatable {
    let translation: ModelCapabilityCheck
    let dictionary: ModelCapabilityCheck
    let sentence: ModelCapabilityCheck
    let totalLatency: Duration

    var level: ModelCapabilityLevel {
        guard translation.passed else {
            return translation.issue?.preventsVerdict == true ? .inconclusive : .incompatible
        }
        guard dictionary.passed, sentence.passed else {
            let issues = [dictionary.issue, sentence.issue].compactMap { $0 }
            return issues.contains(where: \.preventsVerdict) ? .inconclusive : .translationOnly
        }
        return .full
    }

    var firstIssue: ModelCapabilityIssue? {
        [translation.issue, dictionary.issue, sentence.issue].compactMap { $0 }.first
    }

    var blockingIssue: ModelCapabilityIssue? {
        [translation.issue, dictionary.issue, sentence.issue]
            .compactMap { $0 }
            .first(where: \.preventsVerdict)
    }
}

private extension ModelCapabilityCheck {
    var issue: ModelCapabilityIssue? {
        if case .failed(let issue) = outcome { return issue }
        return nil
    }
}

enum ModelOutputLanguageMatch: Sendable, Equatable {
    case match
    case mismatch(detectedCode: String?)
    case inconclusive
}

enum ModelOutputLanguageValidator {
    static func compare(text: String, expectedCode: String) -> ModelOutputLanguageMatch {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letterCount = trimmed.unicodeScalars.lazy.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= 4 else { return .inconclusive }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else {
            return .inconclusive
        }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let confidence = hypotheses[dominant] ?? 0
        let detectedCode = dominant.rawValue
        if TargetLanguage.sameLanguage(
            Locale.Language(identifier: detectedCode),
            Locale.Language(identifier: expectedCode)
        ), confidence >= 0.25 {
            return .match
        }
        if confidence >= 0.65 {
            return .mismatch(detectedCode: detectedCode)
        }
        return .inconclusive
    }
}

enum ModelCapabilityFixtures {
    static func translationSource(firstLanguage: String) -> String {
        if isEnglish(firstLanguage) {
            return "虽然雨在中午前停了，徒步者们还是决定早点收队。"
        }
        return "Although the rain eased before noon, the hikers decided to call it a day."
    }

    static func dictionary(firstLanguage: String) -> String {
        isEnglish(firstLanguage) ? "韧性" : "resilience"
    }

    static func sentenceAnalysisSource(firstLanguage: String) -> String? {
        switch TargetLanguage.displayCode(Locale.Language(identifier: firstLanguage)) {
        case "zh-Hans":
            return "虽然雨在中午前停了，徒步者们还是决定早点收队。"
        case "zh-Hant":
            return "雖然雨在中午前停了，健行者們還是決定提早收隊。"
        case "en":
            return "Although the rain eased before noon, the hikers decided to call it a day."
        case "ja":
            return "昼前に雨は弱まったものの、登山者たちは早めに切り上げることにした。"
        case "ko":
            return "비가 정오 전에 잦아들었지만, 등산객들은 일찍 마무리하기로 했다."
        case "fr":
            return "Même si la pluie s'est calmée avant midi, les randonneurs ont décidé d'écourter leur journée."
        case "de":
            return "Obwohl der Regen vor Mittag nachließ, beschlossen die Wanderer, früher Schluss zu machen."
        case "es":
            return "Aunque la lluvia amainó antes del mediodía, los excursionistas decidieron terminar antes."
        case "ru":
            return "Хотя дождь стих до полудня, туристы решили закончить поход пораньше."
        default:
            return nil
        }
    }

    private static func isEnglish(_ code: String) -> Bool {
        TargetLanguage.sameLanguage(
            Locale.Language(identifier: code),
            Locale.Language(identifier: "en")
        )
    }
}

struct ModelCapabilityAssessor: Sendable {
    typealias LanguageJudge = @Sendable (String, String) -> ModelOutputLanguageMatch

    private let engine: any StructuredRefineEngine
    private let languageJudge: LanguageJudge
    private let redactions: [String]

    init(
        engine: any StructuredRefineEngine,
        redacting sensitiveValues: [String] = [],
        languageJudge: @escaping LanguageJudge = {
            ModelOutputLanguageValidator.compare(text: $0, expectedCode: $1)
        }
    ) {
        self.engine = engine
        self.languageJudge = languageJudge
        redactions = sensitiveValues.filter { !$0.isEmpty }
    }

    init(
        snapshot: BYOKSnapshot,
        languageJudge: @escaping LanguageJudge = {
            ModelOutputLanguageValidator.compare(text: $0, expectedCode: $1)
        }
    ) {
        self.init(
            engine: OpenAICompatibleEngine(snapshot: snapshot.forCapabilityAssessment),
            redacting: [snapshot.apiKey],
            languageJudge: languageJudge
        )
    }

    func assess(
        firstLanguage: String,
        secondLanguage: String,
        progress: @escaping @MainActor @Sendable (ModelCapabilityStage) -> Void = { _ in }
    ) async throws -> ModelCapabilityReport {
        let clock = ContinuousClock()
        let totalStart = clock.now

        await progress(.translation)
        try Task.checkCancellation()
        let translationStart = clock.now
        let translation = try await checkTranslation(firstLanguage: firstLanguage)
        let translationCheck = ModelCapabilityCheck(
            latency: translationStart.duration(to: clock.now),
            outcome: translation
        )
        guard translationCheck.passed else {
            return ModelCapabilityReport(
                translation: translationCheck,
                dictionary: .skipped,
                sentence: .skipped,
                totalLatency: totalStart.duration(to: clock.now)
            )
        }

        await progress(.dictionary)
        try Task.checkCancellation()
        let dictionaryStart = clock.now
        let dictionary = try await checkDictionary(
            firstLanguage: firstLanguage,
            secondLanguage: secondLanguage
        )
        let dictionaryCheck = ModelCapabilityCheck(
            latency: dictionaryStart.duration(to: clock.now),
            outcome: dictionary
        )

        await progress(.sentence)
        try Task.checkCancellation()
        let sentenceStart = clock.now
        let sentence = try await checkSentence(
            firstLanguage: firstLanguage,
            secondLanguage: secondLanguage
        )
        let sentenceCheck = ModelCapabilityCheck(
            latency: sentenceStart.duration(to: clock.now),
            outcome: sentence
        )

        return ModelCapabilityReport(
            translation: translationCheck,
            dictionary: dictionaryCheck,
            sentence: sentenceCheck,
            totalLatency: totalStart.duration(to: clock.now)
        )
    }

    private func checkTranslation(firstLanguage: String) async throws -> ModelCapabilityOutcome {
        let source = ModelCapabilityFixtures.translationSource(firstLanguage: firstLanguage)
        var lastError: Error?

        for _ in 0..<2 {
            try Task.checkCancellation()
            var final = ""
            do {
                for try await output in engine.refine(source: source, draft: "", targetCode: firstLanguage) {
                    try Task.checkCancellation()
                    final = output
                }
                let trimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard trimmed.caseInsensitiveCompare(source) != .orderedSame else {
                    return .failed(.wrongLanguage(expectedCode: firstLanguage, detectedCode: nil))
                }
                return languageOutcome(for: trimmed, expectedCode: firstLanguage)
            } catch {
                try rethrowCancellation(error)
                if !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .failed(requestIssue(for: error))
                }
                lastError = error
            }
        }

        if let lastError { return .failed(requestIssue(for: lastError)) }
        return .failed(.emptyTranslation)
    }

    private func checkDictionary(
        firstLanguage: String,
        secondLanguage: String
    ) async throws -> ModelCapabilityOutcome {
        try Task.checkCancellation()
        let source = ModelCapabilityFixtures.dictionary(firstLanguage: firstLanguage)
        do {
            let result = try await engine.structured(
                kind: .word,
                source: source,
                firstLanguage: firstLanguage,
                secondLanguage: secondLanguage
            )
            try Task.checkCancellation()
            guard case .dictionary(let entry) = result else {
                return .failed(.invalidDictionary)
            }
            let usefulSenses = entry.senses.filter {
                meaningful($0.translation, source: source) && meaningful($0.definition, source: source)
            }
            guard !usefulSenses.isEmpty else { return .failed(.invalidDictionary) }

            let translations = usefulSenses.flatMap { sense in
                [sense.translation] + sense.examples.map(\.target)
            }.joined(separator: " ")
            let definitions = usefulSenses.map(\.definition).joined(separator: " ")
            if case .failed(let issue) = languageOutcome(for: translations, expectedCode: firstLanguage) {
                return .failed(issue)
            }
            return languageOutcome(for: definitions, expectedCode: secondLanguage)
        } catch {
            try rethrowCancellation(error)
            return .failed(requestIssue(for: error))
        }
    }

    private func checkSentence(
        firstLanguage: String,
        secondLanguage: String
    ) async throws -> ModelCapabilityOutcome {
        try Task.checkCancellation()
        guard let source = ModelCapabilityFixtures.sentenceAnalysisSource(
            firstLanguage: firstLanguage
        ) else {
            return .failed(.missingSentenceFixture(languageCode: firstLanguage))
        }
        do {
            let result = try await engine.structured(
                kind: .sentence,
                source: source,
                firstLanguage: secondLanguage,
                secondLanguage: firstLanguage
            )
            try Task.checkCancellation()
            guard case .sentence(let analysis) = result,
                  meaningful(analysis.refinedTranslation, source: source) else {
                return .failed(.invalidSentence)
            }
            let usefulPoints = analysis.syntax.grammarPoints.filter {
                meaningful($0.point, source: source) && meaningful($0.explanation, source: source)
            }
            guard !usefulPoints.isEmpty else {
                return .failed(.invalidSentence)
            }
            if case .failed(let issue) = languageOutcome(
                for: analysis.refinedTranslation,
                expectedCode: secondLanguage
            ) {
                return .failed(issue)
            }
            return languageOutcome(
                for: usefulPoints.map(\.explanation).joined(separator: " "),
                expectedCode: firstLanguage
            )
        } catch {
            try rethrowCancellation(error)
            return .failed(requestIssue(for: error))
        }
    }

    private func languageOutcome(
        for text: String,
        expectedCode: String
    ) -> ModelCapabilityOutcome {
        switch languageJudge(text, expectedCode) {
        case .match:
            return .passed
        case .mismatch(let detectedCode):
            return .failed(.wrongLanguage(expectedCode: expectedCode, detectedCode: detectedCode))
        case .inconclusive:
            return .failed(.uncertainLanguage(expectedCode: expectedCode))
        }
    }

    private func meaningful(_ value: String, source: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !(trimmed.hasPrefix("(in ") && trimmed.hasSuffix(")")) else {
            return false
        }
        return trimmed.caseInsensitiveCompare(source) != .orderedSame
    }

    private func requestIssue(for error: Error) -> ModelCapabilityIssue {
        let message = diagnostic(error)
        switch error {
        case let refine as RefineError:
            switch refine {
            case .invalidEndpoint:
                return .request(message: message, inconclusive: false)
            case .http(let statusCode, _):
                let inconclusive = statusCode == 401 || statusCode == 403
                    || statusCode == 408 || statusCode == 429 || statusCode >= 500
                return .request(message: message, inconclusive: inconclusive)
            case .malformedStructuredResponse, .emptyStructuredResult:
                return .request(message: message, inconclusive: false)
            case .message:
                return .request(message: message, inconclusive: true)
            }
        case let urlError as URLError:
            let deterministic = urlError.code == .badURL || urlError.code == .unsupportedURL
            return .request(message: message, inconclusive: !deterministic)
        default:
            return .request(message: message, inconclusive: true)
        }
    }

    private func diagnostic(_ error: Error) -> String {
        var value = error.localizedDescription
        for sensitive in redactions {
            value = value.replacingOccurrences(of: sensitive, with: "••••")
        }
        value = value.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined()
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(value.prefix(180))
    }

    private func rethrowCancellation(_ error: Error) throws {
        if Task.isCancelled || error is CancellationError
            || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
    }
}

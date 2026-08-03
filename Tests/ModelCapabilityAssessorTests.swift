import XCTest
@testable import GlossPop

final class ModelCapabilityAssessorTests: XCTestCase {
    func testFixturesUseAnOrdinaryWordAndKeepSentenceInputInTheFirstLanguage() {
        XCTAssertEqual(
            ModelCapabilityFixtures.dictionary(firstLanguage: "zh-Hans"),
            "resilience"
        )
        XCTAssertEqual(
            ModelCapabilityFixtures.dictionary(firstLanguage: "en"),
            "韧性"
        )
        XCTAssertEqual(
            ModelCapabilityFixtures.sentenceAnalysisSource(firstLanguage: "zh-Hans"),
            "虽然雨在中午前停了，徒步者们还是决定早点收队。"
        )
        XCTAssertEqual(
            ModelCapabilityFixtures.sentenceAnalysisSource(firstLanguage: "en"),
            "Although the rain eased before noon, the hikers decided to call it a day."
        )
    }

    func testAllProductionSurfacesPassingIsFullyCompatible() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { source, _, target in
                recorder.recordTranslation(source: source, target: target)
                return stream(["虽然雨势减弱了，", "虽然雨势减弱了，徒步者们还是决定早点收队。"])
            },
            structured: { kind, source, first, second in
                recorder.recordStructured(kind: kind, source: source, first: first, second: second)
                switch kind {
                case .word:
                    return .dictionary(validDictionary())
                case .sentence:
                    return .sentence(validSentence())
                default:
                    return .dictionary(DictionaryEntry())
                }
            }
        )
        let assessor = ModelCapabilityAssessor(
            engine: engine,
            languageJudge: { text, expected in
                recorder.recordLanguageCheck(text: text, expected: expected)
                return .match
            }
        )

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .full)
        XCTAssertTrue(report.translation.passed)
        XCTAssertTrue(report.dictionary.passed)
        XCTAssertTrue(report.sentence.passed)
        XCTAssertGreaterThanOrEqual(report.totalLatency, .zero)
        XCTAssertEqual(
            recorder.translationSources,
            [ModelCapabilityFixtures.translationSource(firstLanguage: "zh-Hans")]
        )
        XCTAssertEqual(recorder.translationTargets, ["zh-Hans"])
        XCTAssertEqual(
            recorder.structuredSources,
            [
                ModelCapabilityFixtures.dictionary(firstLanguage: "zh-Hans"),
                ModelCapabilityFixtures.sentenceAnalysisSource(firstLanguage: "zh-Hans")!,
            ]
        )
        XCTAssertEqual(recorder.structuredKinds, [.word, .sentence])
        XCTAssertEqual(recorder.languagePairs.map { $0.0 }, ["zh-Hans", "en"])
        XCTAssertEqual(recorder.languagePairs.map { $0.1 }, ["en", "zh-Hans"])
        XCTAssertEqual(
            recorder.languageCheckTargets,
            ["zh-Hans", "zh-Hans", "en", "en", "zh-Hans"]
        )
    }

    func testInvalidDictionaryStillChecksSentenceAndReportsTranslationOnly() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["有效翻译结果"]) },
            structured: { kind, _, _, _ in
                recorder.recordStructuredKind(kind)
                if kind == .word {
                    return .dictionary(DictionaryEntry(senses: [Sense()]))
                }
                return .sentence(validSentence())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .translationOnly)
        XCTAssertEqual(report.dictionary.outcome, .failed(.invalidDictionary))
        XCTAssertTrue(report.sentence.passed)
        XCTAssertEqual(recorder.structuredKinds, [.word, .sentence])
    }

    func testSentenceWithoutAnalysisIsTranslationOnly() async throws {
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["有效翻译结果"]) },
            structured: { kind, _, _, _ in
                if kind == .word { return .dictionary(validDictionary()) }
                return .sentence(SentenceAnalysis(refinedTranslation: "有效翻译结果"))
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .translationOnly)
        XCTAssertEqual(report.sentence.outcome, .failed(.invalidSentence))
    }

    func testSentenceNeedsARealGrammarPointNotOnlyANoteOrEmptyPoint() async throws {
        let invalidAnalyses = [
            SentenceAnalysis(
                refinedTranslation: "The hikers decided to finish early.",
                notes: ["A generic note without any analysis."]
            ),
            SentenceAnalysis(
                refinedTranslation: "The hikers decided to finish early.",
                syntax: SyntaxBreakdown(
                    grammarPoints: [
                        GrammarPoint(point: "", explanation: "A non-empty explanation."),
                    ]
                )
            ),
        ]
        for analysis in invalidAnalyses {
            let engine = StubStructuredEngine(
                refine: { _, _, _ in stream(["有效翻译结果"]) },
                structured: { kind, _, _, _ in
                    kind == .word ? .dictionary(validDictionary()) : .sentence(analysis)
                }
            )
            let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

            let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

            XCTAssertEqual(report.level, .translationOnly)
            XCTAssertEqual(report.sentence.outcome, .failed(.invalidSentence))
        }
    }

    func testEmptyTranslationRetriesThenReportsIncompatibleWithoutStructuredRequests() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in
                recorder.recordTranslationAttempt()
                return stream([])
            },
            structured: { _, _, _, _ in
                recorder.recordUnexpectedStructuredRequest()
                return .sentence(validSentence())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .incompatible)
        XCTAssertEqual(report.translation.outcome, .failed(.emptyTranslation))
        XCTAssertEqual(report.dictionary.outcome, .skipped)
        XCTAssertEqual(report.sentence.outcome, .skipped)
        XCTAssertEqual(recorder.translationAttemptCount, 2)
        XCTAssertEqual(recorder.unexpectedStructuredRequestCount, 0)
    }

    func testTransientTranslationFailureIsInconclusive() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in
                recorder.recordTranslationAttempt()
                return failingStream(URLError(.timedOut))
            },
            structured: { _, _, _, _ in .sentence(validSentence()) }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .inconclusive)
        guard case .failed(.request(_, let inconclusive)) = report.translation.outcome else {
            return XCTFail("Expected an inconclusive request issue")
        }
        XCTAssertTrue(inconclusive)
        XCTAssertEqual(recorder.translationAttemptCount, 2)
    }

    func testDeterministicBadRequestIsIncompatibleButAuthenticationIsInconclusive() async throws {
        for (statusCode, expected) in [(400, ModelCapabilityLevel.incompatible), (401, .inconclusive)] {
            let engine = StubStructuredEngine(
                refine: { _, _, _ in
                    failingStream(RefineError.http(statusCode: statusCode, host: "api.example.com"))
                },
                structured: { _, _, _, _ in .sentence(validSentence()) }
            )
            let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

            let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

            XCTAssertEqual(report.level, expected)
        }
    }

    func testWrongTranslationLanguageIsIncompatible() async throws {
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["This stayed in English instead."]) },
            structured: { _, _, _, _ in .sentence(validSentence()) }
        )
        let assessor = ModelCapabilityAssessor(
            engine: engine,
            languageJudge: { _, _ in .mismatch(detectedCode: "en") }
        )

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .incompatible)
        XCTAssertEqual(
            report.translation.outcome,
            .failed(.wrongLanguage(expectedCode: "zh-Hans", detectedCode: "en"))
        )
    }

    func testUncertainLanguageDoesNotMisclassifyTheModel() async throws {
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["短句"]) },
            structured: { _, _, _, _ in .sentence(validSentence()) }
        )
        let assessor = ModelCapabilityAssessor(
            engine: engine,
            languageJudge: { _, _ in .inconclusive }
        )

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .inconclusive)
        XCTAssertEqual(
            report.translation.outcome,
            .failed(.uncertainLanguage(expectedCode: "zh-Hans"))
        )
    }

    func testEmptyFirstStreamRetriesAndUsesTheSecondResult() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in
                recorder.recordTranslationAttempt()
                return recorder.translationAttemptCount == 1 ? stream([]) : stream(["有效翻译结果"])
            },
            structured: { kind, _, _, _ in
                kind == .word ? .dictionary(validDictionary()) : .sentence(validSentence())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .full)
        XCTAssertEqual(recorder.translationAttemptCount, 2)
    }

    func testPartialStreamFailureDoesNotRetry() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in
                recorder.recordTranslationAttempt()
                return partialFailingStream("partial result", error: URLError(.networkConnectionLost))
            },
            structured: { _, _, _, _ in .sentence(validSentence()) }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .inconclusive)
        XCTAssertEqual(recorder.translationAttemptCount, 1)
    }

    func testCancellationIsRethrownInsteadOfProducingAVerdict() async {
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["有效翻译结果"]) },
            structured: { _, _, _, _ in
                try await Task.sleep(for: .seconds(30))
                return .dictionary(validDictionary())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })
        let task = Task {
            try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")
        }
        try? await Task.sleep(for: .milliseconds(20))

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation must not produce a capability report")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancellationBeforeDictionaryDoesNotStartAStructuredRequest() async {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["有效翻译结果"]) },
            structured: { _, _, _, _ in
                recorder.recordUnexpectedStructuredRequest()
                return .dictionary(validDictionary())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })
        let task = Task {
            try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en") { stage in
                if stage == .dictionary {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation before a stage must stop the next request")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(recorder.unexpectedStructuredRequestCount, 0)
    }

    func testTransientStructuredFailureMakesMixedResultInconclusive() async throws {
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["有效翻译结果"]) },
            structured: { kind, _, _, _ in
                if kind == .word {
                    return .dictionary(DictionaryEntry(senses: [Sense()]))
                }
                throw RefineError.http(statusCode: 429, host: "api.example.com")
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        XCTAssertEqual(report.level, .inconclusive)
        XCTAssertEqual(report.firstIssue, .invalidDictionary)
        XCTAssertEqual(
            report.blockingIssue,
            .request(message: "HTTP 429 from api.example.com", inconclusive: true)
        )
    }

    func testAssessmentSnapshotNeverCarriesCustomPrompts() {
        let snapshot = BYOKSnapshot(
            baseURL: "https://api.example.com",
            apiPath: "/v1/chat/completions",
            model: "example-model",
            apiKey: "secret",
            reasoningEffort: "low",
            customSystem: "private system prompt",
            customUser: "private user prompt"
        )

        let assessment = snapshot.forCapabilityAssessment

        XCTAssertEqual(assessment.baseURL, snapshot.baseURL)
        XCTAssertEqual(assessment.model, snapshot.model)
        XCTAssertEqual(assessment.apiKey, snapshot.apiKey)
        XCTAssertEqual(assessment.reasoningEffort, snapshot.reasoningEffort)
        XCTAssertTrue(assessment.customSystem.isEmpty)
        XCTAssertTrue(assessment.customUser.isEmpty)
    }

    func testUnsupportedFirstLanguageIsInconclusiveWithoutAFakeSentenceRequest() async throws {
        let recorder = ProbeRecorder()
        let engine = StubStructuredEngine(
            refine: { _, _, _ in stream(["Traduzione valida per il controllo."]) },
            structured: { kind, _, _, _ in
                if kind == .word {
                    return .dictionary(validDictionary())
                }
                recorder.recordUnexpectedStructuredRequest()
                return .sentence(validSentence())
            }
        )
        let assessor = ModelCapabilityAssessor(engine: engine, languageJudge: { _, _ in .match })

        let report = try await assessor.assess(firstLanguage: "it", secondLanguage: "en")

        XCTAssertEqual(report.level, .inconclusive)
        XCTAssertEqual(
            report.sentence.outcome,
            .failed(.missingSentenceFixture(languageCode: "it"))
        )
        XCTAssertEqual(recorder.unexpectedStructuredRequestCount, 0)
    }

    func testDiagnosticsAreSingleLineBoundedAndRedacted() async throws {
        let secret = "secret-api-token"
        let message = String(repeating: "failure \(secret)\n", count: 30)
        let engine = StubStructuredEngine(
            refine: { _, _, _ in failingStream(RefineError.message(message)) },
            structured: { _, _, _, _ in .sentence(validSentence()) }
        )
        let assessor = ModelCapabilityAssessor(
            engine: engine,
            redacting: [secret],
            languageJudge: { _, _ in .match }
        )

        let report = try await assessor.assess(firstLanguage: "zh-Hans", secondLanguage: "en")

        guard case .failed(.request(let diagnostic, _)) = report.translation.outcome else {
            return XCTFail("Expected a request diagnostic")
        }
        XCTAssertFalse(diagnostic.contains(secret))
        XCTAssertFalse(diagnostic.contains("\n"))
        XCTAssertLessThanOrEqual(diagnostic.count, 180)
    }

    func testLanguageValidatorDistinguishesStrongMatchesAndUncertainShortText() {
        XCTAssertEqual(
            ModelOutputLanguageValidator.compare(
                text: "The hikers decided to finish their journey before sunset.",
                expectedCode: "en"
            ),
            .match
        )
        XCTAssertEqual(
            ModelOutputLanguageValidator.compare(text: "好", expectedCode: "zh-Hans"),
            .inconclusive
        )
        guard case .mismatch(let detected) = ModelOutputLanguageValidator.compare(
            text: "Les randonneurs ont décidé de terminer leur voyage avant le coucher du soleil.",
            expectedCode: "en"
        ) else {
            return XCTFail("Expected a confident language mismatch")
        }
        XCTAssertEqual(detected, "fr")
    }

    func testLanguageValidatorRecognisesEverySettingsLanguageAndChineseScript() {
        let samples = [
            "en": "The hikers decided to finish their journey before sunset because the weather was changing quickly.",
            "zh-Hans": "今天下午天气突然转凉，徒步旅行的人决定提前结束行程并返回营地。",
            "zh-Hant": "今天下午天氣突然轉涼，健行的人決定提早結束行程並返回營地。",
            "ja": "午後になって天気が急に冷え込んだため、登山者たちは早めに行程を終えてキャンプに戻ることにした。",
            "ko": "오후에 날씨가 갑자기 추워져서 등산객들은 일정을 일찍 마치고 야영지로 돌아가기로 했다.",
            "fr": "Comme le temps s'est brusquement refroidi dans l'après-midi, les randonneurs ont décidé de terminer plus tôt et de rentrer au camp.",
            "de": "Weil es am Nachmittag plötzlich kälter wurde, beschlossen die Wanderer, ihre Tour früher zu beenden und zum Lager zurückzukehren.",
            "es": "Como el tiempo se enfrió de repente por la tarde, los excursionistas decidieron terminar antes y regresar al campamento.",
            "ru": "Поскольку во второй половине дня резко похолодало, туристы решили закончить поход раньше и вернуться в лагерь.",
        ]

        XCTAssertEqual(Set(samples.keys), Set(TargetLanguage.choices))
        for code in TargetLanguage.choices {
            XCTAssertEqual(
                ModelOutputLanguageValidator.compare(text: samples[code]!, expectedCode: code),
                .match,
                "Expected a confident match for \(code)"
            )
        }
        XCTAssertEqual(
            ModelOutputLanguageValidator.compare(text: samples["zh-Hant"]!, expectedCode: "zh-Hans"),
            .mismatch(detectedCode: "zh-Hant")
        )
        XCTAssertEqual(
            ModelOutputLanguageValidator.compare(text: samples["zh-Hans"]!, expectedCode: "zh-Hant"),
            .mismatch(detectedCode: "zh-Hans")
        )
    }
}

private struct StubStructuredEngine: StructuredRefineEngine {
    let refineHandler: @Sendable (String, String, String) -> AsyncThrowingStream<String, Error>
    let structuredHandler: @Sendable (InputKind, String, String, String) async throws -> StructuredResult

    init(
        refine: @escaping @Sendable (String, String, String) -> AsyncThrowingStream<String, Error>,
        structured: @escaping @Sendable (InputKind, String, String, String) async throws -> StructuredResult
    ) {
        refineHandler = refine
        structuredHandler = structured
    }

    var label: String { "Stub" }
    var provenance: String { "" }
    func isAvailable() async -> Bool { true }

    func refine(
        source: String,
        draft: String,
        targetCode: String
    ) -> AsyncThrowingStream<String, Error> {
        refineHandler(source, draft, targetCode)
    }

    func structured(
        kind: InputKind,
        source: String,
        firstLanguage: String,
        secondLanguage: String
    ) async throws -> StructuredResult {
        try await structuredHandler(kind, source, firstLanguage, secondLanguage)
    }
}

private final class ProbeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTranslationSources: [String] = []
    private var storedTranslationTargets: [String] = []
    private var storedStructuredSources: [String] = []
    private var storedStructuredKinds: [InputKind] = []
    private var storedLanguagePairs: [(String, String)] = []
    private var storedLanguageCheckTargets: [String] = []
    private var storedTranslationAttemptCount = 0
    private var storedUnexpectedStructuredRequestCount = 0

    var translationSources: [String] { lock.withLock { storedTranslationSources } }
    var translationTargets: [String] { lock.withLock { storedTranslationTargets } }
    var structuredSources: [String] { lock.withLock { storedStructuredSources } }
    var structuredKinds: [InputKind] { lock.withLock { storedStructuredKinds } }
    var languagePairs: [(String, String)] { lock.withLock { storedLanguagePairs } }
    var languageCheckTargets: [String] { lock.withLock { storedLanguageCheckTargets } }
    var translationAttemptCount: Int { lock.withLock { storedTranslationAttemptCount } }
    var unexpectedStructuredRequestCount: Int {
        lock.withLock { storedUnexpectedStructuredRequestCount }
    }

    func recordTranslation(source: String, target: String) {
        lock.withLock {
            storedTranslationSources.append(source)
            storedTranslationTargets.append(target)
        }
    }

    func recordLanguageCheck(text: String, expected: String) {
        lock.withLock {
            storedLanguageCheckTargets.append(expected)
        }
    }

    func recordTranslationAttempt() {
        lock.withLock {
            storedTranslationAttemptCount += 1
        }
    }

    func recordStructured(kind: InputKind, source: String, first: String, second: String) {
        lock.withLock {
            storedStructuredKinds.append(kind)
            storedStructuredSources.append(source)
            storedLanguagePairs.append((first, second))
        }
    }

    func recordStructuredKind(_ kind: InputKind) {
        lock.withLock {
            storedStructuredKinds.append(kind)
        }
    }

    func recordUnexpectedStructuredRequest() {
        lock.withLock {
            storedUnexpectedStructuredRequestCount += 1
        }
    }
}

private func stream(_ values: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for value in values { continuation.yield(value) }
        continuation.finish()
    }
}

private func failingStream(_ error: any Error) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}

private func partialFailingStream(
    _ value: String,
    error: any Error
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        continuation.yield(value)
        continuation.finish(throwing: error)
    }
}

private func validDictionary() -> DictionaryEntry {
    DictionaryEntry(
        headword: "resilience",
        senses: [
            Sense(
                definition: "the ability to recover quickly from difficulty",
                translation: "韧性",
                examples: [
                    Example(
                        source: "Her resilience helped the team recover.",
                        target: "她的韧性帮助团队恢复了状态。"
                    ),
                ]
            ),
        ]
    )
}

private func validSentence() -> SentenceAnalysis {
    SentenceAnalysis(
        refinedTranslation: "Although the rain eased before noon, the hikers decided to finish early.",
        syntax: SyntaxBreakdown(
            grammarPoints: [
                GrammarPoint(
                    point: "虽然……还是……",
                    explanation: "这个让步结构说明后面的决定没有因前面的情况而改变。"
                ),
            ]
        )
    )
}

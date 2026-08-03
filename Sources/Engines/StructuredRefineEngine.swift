import Foundation

enum StructuredResult: Sendable {
    case dictionary(DictionaryEntry)
    case sentence(SentenceAnalysis)
}

// A refine engine that can also produce input-aware STRUCTURED output (PLAN §2.5).
// Word/phrase → bilingual dictionary: definition in `secondLanguage`, meaning in `firstLanguage`.
// Sentence → translate into `firstLanguage` + syntax.
protocol StructuredRefineEngine: RefineEngine {
    func structured(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) async throws -> StructuredResult
}

// JSON prompts (BYOK path) + tolerant JSON→DTO building. FM uses @Generable mirrors (macOS 26).
enum StructuredPrompt {
    static let system = """
    You are a precise bilingual assistant. Reply with ONLY a single JSON object, no markdown fences, no prose. \
    Leave a string as "" or an array as [] when a field does not apply — never output placeholder/empty entries.
    """

    static func user(kind: InputKind, source: String, firstLanguage: String, secondLanguage: String) -> String {
        let s = String(source.prefix(RefinePrompt.maxSourceChars))
        // Instruct the model with a written language NAME ("Simplified Chinese"), not a BCP-47 code
        // ("zh-Hans"): an LLM reliably honours the name when told which language to WRITE in, but often
        // ignores a bare code for secondary fields (observed: a sentence's translation obeyed "zh-Hans"
        // while its grammar notes still came back in English).
        let first = languageName(firstLanguage)
        let second = languageName(secondLanguage)
        switch kind {
        case .word, .phrase:
            // Bilingual entry: "definition" in the SECOND language, "translation" = the meaning in the FIRST.
            return """
            For the term below, return a JSON dictionary entry. "definition" MUST be written in \(second); \
            "translation" MUST be the meaning in \(first); each example's "target" in \(first):
            {"headword":"","pronunciation":"","senses":[{"partOfSpeech":"","definition":"(in \(second))","translation":"(in \(first))","examples":[{"source":"","target":"(in \(first))"}],"synonyms":[""],"register":""}],"idioms":[{"phrase":"","meaning":"(in \(first))"}]}
            Term: \(s)
            """
        case .sentence:
            // Only request fields the SentenceCard actually shows (dropped tokenGloss/clauses → smaller/faster).
            // firstLanguage = the RESOLVED translation target; secondLanguage = the user's NATIVE language,
            // so the analysis stays readable even when translating OUT of it.
            let spec = """
            Translate the sentence into \(first), then analyse it for a \(second) reader. Write \
            "refinedTranslation" in \(first); write every "point", every "explanation" and every "notes" \
            entry in \(second) — never in English unless \(second) is English. Keep "subject", "predicate" \
            and "objects" as the \
            exact words from the original sentence. In "grammarPoints" include ONLY what genuinely helps \
            understanding: key or uncommon vocabulary and domain terms (give the meaning), set phrases and \
            idioms, and non-obvious grammar (subordination, ellipsis, unusual word order, tricky \
            tense/voice). Do NOT label ordinary words with their part of speech (no "is — linking verb", \
            "creates — present-tense verb"); skip what a learner already knows. Be thorough: cover every \
            genuinely useful item — for a long or dense passage don't stop at three or four and leave key \
            terms or structures unexplained — but add a point ONLY when you are confident it is correct and \
            it genuinely helps; never pad with filler, obvious words or uncertain guesses. A simple sentence \
            still gets few or none. Use "notes" for translation caveats, cultural context or ambiguities, or \
            [] when nothing is useful. Return JSON:
            {"refinedTranslation":"(in \(first))","syntax":{"subject":"","predicate":"","objects":[],"grammarPoints":[{"point":"(in \(second))","explanation":"(in \(second))"}]},"notes":["(in \(second))"]}
            """
            // A worked example lifts weaker models close to the strong ones (eval: floor model 3.60→4.25,
            // no regression up top) without over-explaining simple sentences. Attached only when the
            // translation target IS the reader's language (the example's translation is in that language)
            // and one exists for it — so a foreign-script example never bleeds into other locales.
            if firstLanguage == secondLanguage, let ex = Self.workedExample(for: secondLanguage) {
                return spec + "\n\nWorked example (match this depth and style; pick points by what actually "
                    + "helps, and give FEWER for a simple sentence):\nSentence: \(ex.source)\nJSON: \(ex.json)"
                    + "\n\nNow analyse this one.\nSentence: \(s)"
            }
            return spec + "\nSentence: \(s)"
        }
    }

    // One worked input→output example per native language: a key term + idiom/phrasal item + a structural
    // point + a useful note, S/V/O kept in the source, explanations in the reader's language, no
    // part-of-speech labels. Authored by native speakers; lifts weaker models (eval). nil for languages
    // without one (they fall back to the plain spec).
    static func workedExample(for nativeCode: String) -> (source: String, json: String)? { workedExamples[nativeCode] }

    private static let workedExamples: [String: (source: String, json: String)] = [
        "zh-Hans": ("The startup decided to pivot after burning through its runway in just eight months.", "{\"refinedTranslation\": \"这家初创公司在短短八个月内烧光资金储备后，决定转型。\", \"syntax\": {\"subject\": \"The startup\", \"predicate\": \"decided\", \"objects\": [\"to pivot\"], \"grammarPoints\": [{\"point\": \"pivot\", \"explanation\": \"商业语境中指初创公司大幅调整方向或商业模式，而非字面的“旋转”。\"}, {\"point\": \"burn through its runway\", \"explanation\": \"runway 指公司现金能支撑运营的时长；burn through 表示快速耗尽，整体即“烧光资金储备”。\"}, {\"point\": \"after + 动名词 (burning)\", \"explanation\": \"after 接动名词表时间先后，主句“决定转型”发生在资金耗尽之后。\"}]}, \"notes\": [\"runway 是创投术语，指资金可维持的时长，不能按字面“跑道”理解。\"]}"),
        "zh-Hant": ("Had the regulators not stepped in, the bank would have been left holding the bag when the subprime market collapsed.", "{\"refinedTranslation\": \"要不是監管機構及時介入，等到次級貸款市場崩盤時，這家銀行恐怕就得獨自承擔所有爛攤子了。\", \"syntax\": {\"subject\": \"the bank\", \"predicate\": \"would have been left\", \"objects\": [\"holding the bag\"], \"grammarPoints\": [{\"point\": \"subprime market\", \"explanation\": \"金融術語，指次級房貸（信用較差借款人的高風險貸款）市場，2008 年金融海嘯的核心，不可按字面拆成「次等市場」。\"}, {\"point\": \"left holding the bag\", \"explanation\": \"慣用語，字面是「被留下拿著袋子」，實指在出問題時被丟下來獨自承擔損失或責任，相當於「替人背鍋、收拾爛攤子」。\"}, {\"point\": \"Had the regulators not stepped in\", \"explanation\": \"省略 if 的倒裝虛擬條件句，由 If the regulators had not stepped in 改寫而來；助動詞 Had 提前到句首，搭配主句 would have been 表達與過去事實相反的假設。\"}]}, \"notes\": [\"全句是與過去事實相反的假設：監管機構其實有介入，所以銀行最終並未真的獨自承擔損失，翻譯需用「要不是…恐怕就…」保留這層反事實語氣。\"]}"),
        "en": ("Après avoir essuyé un revers cuisant en bourse, le PDG a décidé de jeter l'éponge.", "{\"refinedTranslation\": \"After suffering a bitter setback on the stock market, the CEO decided to throw in the towel.\", \"syntax\": {\"subject\": \"le PDG\", \"predicate\": \"a décidé\", \"objects\": [\"de jeter l'éponge\"], \"grammarPoints\": [{\"point\": \"PDG\", \"explanation\": \"Abbreviation of Président-Directeur Général, the French equivalent of CEO/Chairman; treated as a masculine noun and read letter by letter (pé-dé-gé).\"}, {\"point\": \"essuyer un revers\", \"explanation\": \"Fixed collocation meaning to suffer/sustain a setback or defeat; essuyer literally means 'to wipe', so this is figurative, not literal — and cuisant ('stinging, bitter', lit. 'burning') is the standard intensifier paired with revers.\"}, {\"point\": \"jeter l'éponge\", \"explanation\": \"Idiom borrowed from boxing, exactly matching English 'throw in the towel' (to give up); l'éponge ('the sponge') is the fixed object and cannot be altered or pluralised.\"}, {\"point\": \"Après avoir essuyé\", \"explanation\": \"Perfect (past) infinitive: après + avoir/être + past participle. French requires this construction — not a finite clause — when both actions share the same subject, and it marks the setback as completed before the main verb 'a décidé'.\"}]}, \"notes\": [\"The opening clause has no expressed subject because of the perfect-infinitive structure; the implied agent must be the same as the main clause's subject, le PDG. Using a finite 'après que' clause here would be ungrammatical.\"]}"),
        "ja": ("Having vested only half her equity, she walked away from the company before hitting her one-year cliff.", "{\"refinedTranslation\": \"持ち株の半分しか権利確定していなかったが、彼女は1年のクリフに達する前にその会社を去った。\", \"syntax\": {\"subject\": \"she\", \"predicate\": \"walked away\", \"objects\": [\"from the company\"], \"grammarPoints\": [{\"point\": \"cliff\", \"explanation\": \"ストックオプション報酬の専門用語で、この期間在籍して初めて権利確定が始まる「最低勤続期間」を指す。one-year cliff は通常「1年在籍するまで一切権利確定しない」を意味し、それを満たす前に辞めると付与株はゼロになる。\"}, {\"point\": \"walked away from\", \"explanation\": \"walk away from は「(関係・職・取引などを)きっぱり手放す/見切りをつけて去る」という句動詞。単なる物理的に歩き去る意味ではなく、自ら進んで関与をやめるニュアンスを含む。\"}, {\"point\": \"Having vested only half her equity\", \"explanation\": \"完了分詞構文(Having + 過去分詞)。主節の「去った」より前に完了した状況を表し、「半分しか権利確定していない状態で」という譲歩・背景を簡潔に前置きしている。\"}]}, \"notes\": [\"vest/vested は法律・報酬分野で「権利が確定する」の意。equity は文脈上「株式(の持ち分)」を指し、cliff も含めスタートアップの報酬制度を知らないと直訳では誤読しやすい。\"]}"),
        "ko": ("Having underwritten the policy in good faith, the insurer found itself on the hook for damages it never saw coming.", "{\"refinedTranslation\": \"선의로 보험을 인수했음에도, 그 보험사는 전혀 예상하지 못한 손해를 떠안는 처지에 놓였다.\", \"syntax\": {\"subject\": \"the insurer\", \"predicate\": \"found\", \"objects\": [\"itself\"], \"grammarPoints\": [{\"point\": \"underwritten the policy\", \"explanation\": \"underwrite는 보험·금융 용어로 보험사가 위험을 평가해 보장 책임을 '인수'한다는 뜻이며, 글자 그대로 '밑에 쓰다'가 아니다. policy는 여기서 '정책'이 아니라 '보험증권/보험계약'을 가리킨다.\"}, {\"point\": \"on the hook for\", \"explanation\": \"'~에 대해 책임을 지는/덤터기를 쓰는' 상태를 뜻하는 관용구로, 낚싯바늘(hook)에 걸려 빠져나갈 수 없다는 이미지에서 나왔다. 여기서는 손해배상 책임을 피할 수 없이 떠안았다는 의미다.\"}, {\"point\": \"Having underwritten ... , the insurer ...\", \"explanation\": \"문두의 'Having + 과거분사'는 완료분사구문으로, 주절보다 앞서 일어난 일을 압축해 표현한다. in good faith(선의로)와 결합해 '선의로 인수했음에도'라는 양보의 뉘앙스를 자연스럽게 전달한다.\"}]}, \"notes\": [\"damages는 복수형일 때 '손해'가 아니라 법률상 '손해배상금'을 뜻하며, 끝의 'it never saw coming'은 damages를 수식하는 관계절(목적격 관계대명사 생략)로 '예상하지 못한'이라는 의미다.\"]}"),
        "fr": ("The defense attorney moved to throw out the evidence, arguing it had been obtained on a fishing expedition.", "{\"refinedTranslation\": \"L'avocat de la défense a demandé l'irrecevabilité des preuves, faisant valoir qu'elles avaient été obtenues à l'issue d'une pêche aux informations sans fondement.\", \"syntax\": {\"subject\": \"The defense attorney\", \"predicate\": \"moved\", \"objects\": [\"to throw out the evidence\"], \"grammarPoints\": [{\"point\": \"moved to throw out the evidence\", \"explanation\": \"Terme juridique : « to move (to do sth) » signifie déposer une requête / saisir formellement le tribunal, et non « bouger ». « Throw out the evidence » = faire écarter / déclarer irrecevables les preuves. À rendre par « demander l'irrecevabilité », pas par un mouvement physique.\"}, {\"point\": \"a fishing expedition\", \"explanation\": \"Expression idiomatique (surtout en contexte juridique) : une recherche tous azimuts, spéculative et sans motif sérieux, menée dans l'espoir de « repêcher » par hasard quelque chose de compromettant. Le sens littéral de « partie de pêche » est trompeur.\"}, {\"point\": \"arguing it had been obtained\", \"explanation\": \"Structure : participe présent en apposition (« arguing… ») qui exprime le moyen/la justification de l'action principale, équivalent de « en faisant valoir que… ». Le plus-que-parfait « had been obtained » marque l'antériorité : l'obtention des preuves précède la demande de l'avocat.\"}]}, \"notes\": [\"« Fishing expedition » est une formule consacrée du langage judiciaire anglo-saxon désignant une demande de preuves abusivement large ; le calque « expédition de pêche » serait incompréhensible, mieux vaut expliciter le caractère sans fondement de la démarche.\"]}"),
        "de": ("Had the auditors not flagged the discrepancy, the company would have swept the shortfall under the rug indefinitely.", "{\"refinedTranslation\": \"Hätten die Wirtschaftsprüfer die Unstimmigkeit nicht aufgedeckt, hätte das Unternehmen das Defizit auf unbestimmte Zeit unter den Teppich gekehrt.\", \"syntax\": {\"subject\": \"the company\", \"predicate\": \"would have swept\", \"objects\": [\"the shortfall\"], \"grammarPoints\": [{\"point\": \"discrepancy / shortfall\", \"explanation\": \"Fachbegriffe aus dem Rechnungswesen: discrepancy ist eine Abweichung bzw. Unstimmigkeit (z. B. zwischen Soll- und Ist-Werten), shortfall ein konkreter Fehlbetrag bzw. ein Defizit. Beide sind hier nicht synonym, sondern bezeichnen Ursache (Unstimmigkeit) und Befund (Fehlbetrag).\"}, {\"point\": \"sweep the shortfall under the rug\", \"explanation\": \"Idiom „etw. unter den Teppich kehren“: etwas Unangenehmes bewusst verschweigen oder vertuschen, statt es offenzulegen. Nicht wörtlich als „fegen“ zu verstehen; das Objekt shortfall wird hier idiomatisch in die Redewendung eingebettet.\"}, {\"point\": \"Had the auditors not flagged …\", \"explanation\": \"Inversion als Ersatz für einen if-Konditionalsatz (Typ III, irreale Vergangenheit): „Had X not done“ = „If X had not done“. Das Hilfsverb had rückt vor das Subjekt, if entfällt; im Deutschen entspricht das der Form „Hätten die Prüfer … nicht“ ohne „wenn“.\"}]}, \"notes\": [\"flag bedeutet hier nicht „markieren mit einer Fahne“, sondern fachsprachlich „auf ein Problem hinweisen / beanstanden“ — ein typisches Verb im Prüfungs- und Compliance-Kontext.\"]}"),
        "es": ("Once the central bank signalled tighter policy, investors who had bet on cheap money found themselves caught flat-footed.", "{\"refinedTranslation\": \"En cuanto el banco central dio señales de un endurecimiento de su política, los inversores que habían apostado por el dinero barato se vieron pillados por sorpresa.\", \"syntax\": {\"subject\": \"investors who had bet on cheap money\", \"predicate\": \"found\", \"objects\": [\"themselves caught flat-footed\"], \"grammarPoints\": [{\"point\": \"tighter policy / cheap money\", \"explanation\": \"Términos de política monetaria: 'tighter policy' es el endurecimiento (subir tipos, retirar liquidez) y 'cheap money' el dinero barato (tipos bajos, crédito abundante). No traducir 'tighter' como 'más apretada' ni 'cheap money' como dinero literalmente barato.\"}, {\"point\": \"caught flat-footed\", \"explanation\": \"Modismo: ser pillado desprevenido, sin tiempo de reaccionar. La imagen es la de quedarse plantado, con los pies planos. Equivale a 'pillar por sorpresa' o 'agarrar con el pie cambiado', no algo sobre los pies.\"}, {\"point\": \"Once + cláusula, ... / found themselves caught\", \"explanation\": \"'Once' aquí no es 'una vez (número)' sino 'en cuanto / tan pronto como', introduciendo una subordinada temporal. Además 'found themselves caught' es estructura reflexiva con participio: 'se encontraron/vieron + atrapados', que expresa un estado sufrido de forma involuntaria.\"}]}, \"notes\": [\"'had bet' es pluscuamperfecto: la apuesta por el dinero barato es anterior a la señal del banco central; ese orden temporal es justo lo que explica que los pillara por sorpresa.\"]}"),
        "ru": ("Had the defendant disclosed the conflict of interest, the board would never have signed off on the merger.", "{\"refinedTranslation\": \"Если бы ответчик раскрыл конфликт интересов, совет директоров ни за что не одобрил бы это слияние.\", \"syntax\": {\"subject\": \"the board\", \"predicate\": \"would never have signed off on\", \"objects\": [\"the merger\"], \"grammarPoints\": [{\"point\": \"conflict of interest\", \"explanation\": \"Юридический и деловой термин: ситуация, когда личная заинтересованность лица противоречит его служебным обязанностям. Переводится устойчиво как «конфликт интересов», а не дословно «конфликт интереса».\"}, {\"point\": \"sign off on\", \"explanation\": \"Фразовый глагол со значением «официально одобрить, дать санкцию, утвердить» (часто документ или сделку). Не путать с буквальным «расписаться»: акцент на формальном согласии ответственного лица.\"}, {\"point\": \"Had the defendant disclosed …, the board would have …\", \"explanation\": \"Инвертированное условное предложение третьего типа: вместо «If the defendant had disclosed» вспомогательный had вынесен вперёд, а if опущен. Это книжно-формальный приём; всё предложение описывает нереальное условие в прошлом — на русском передаётся через «если бы … раскрыл … одобрил бы».\"}]}, \"notes\": [\"Конструкция выражает контрфактическое прошлое: ответчик НЕ раскрыл конфликт, поэтому слияние фактически было одобрено. Отрицание never усиливает гипотетический отказ совета («ни за что не одобрил бы»).\"]}"),
    ]

    // English language name for a BCP-47 code, for prompting (LLMs follow names better than codes).
    static func languageName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "Simplified Chinese"
        case "zh-Hant": return "Traditional Chinese"
        default: return Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
        }
    }
}

// Tolerant JSON → DTO builders (also a test target).
enum StructuredJSON {
    /// Return the FIRST balanced `{…}` span that parses as a JSON object — skipping brace-bearing prose or a
    /// preamble/thought object before the real answer (walks depth, respects string literals).
    static func object(from raw: String) -> [String: Any]? {
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            guard chars[i] == "{" else { i += 1; continue }
            var depth = 0, inString = false, escaped = false, j = i, closed = false
            while j < chars.count {
                let c = chars[j]
                if inString {
                    if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" { depth -= 1; if depth == 0 { closed = true; break } }
                j += 1
            }
            guard closed else { break }  // unbalanced from here on
            let slice = String(chars[i...j])
            if let obj = (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any] { return obj }
            i = j + 1  // this span wasn't a valid object → keep scanning
        }
        return nil
    }

    static func dictionary(from json: [String: Any]) -> DictionaryEntry {
        var e = DictionaryEntry()
        e.headword = json["headword"] as? String ?? ""
        e.pronunciation = json["pronunciation"] as? String ?? ""
        e.senses = (json["senses"] as? [[String: Any]] ?? []).map { s in
            var sense = Sense()
            sense.partOfSpeech = s["partOfSpeech"] as? String ?? ""
            sense.definition = s["definition"] as? String ?? ""
            sense.translation = s["translation"] as? String ?? ""
            sense.synonyms = (s["synonyms"] as? [String]) ?? []
            sense.register = s["register"] as? String ?? ""
            sense.examples = (s["examples"] as? [[String: Any]] ?? []).map {
                Example(source: $0["source"] as? String ?? "", target: $0["target"] as? String ?? "")
            }
            return sense
        }
        e.idioms = (json["idioms"] as? [[String: Any]] ?? []).map {
            Idiom(phrase: $0["phrase"] as? String ?? "", meaning: $0["meaning"] as? String ?? "")
        }
        return e
    }

    static func sentence(from json: [String: Any]) -> SentenceAnalysis {
        var a = SentenceAnalysis()
        a.refinedTranslation = json["refinedTranslation"] as? String ?? ""
        a.literalTranslation = json["literalTranslation"] as? String ?? ""
        a.notes = (json["notes"] as? [String]) ?? []
        if let syn = json["syntax"] as? [String: Any] {
            var b = SyntaxBreakdown()
            b.subject = syn["subject"] as? String ?? ""
            b.predicate = syn["predicate"] as? String ?? ""
            b.objects = (syn["objects"] as? [String]) ?? []
            b.clauses = (syn["clauses"] as? [[String: Any]] ?? []).map {
                Clause(text: $0["text"] as? String ?? "", role: $0["role"] as? String ?? "")
            }
            b.grammarPoints = (syn["grammarPoints"] as? [[String: Any]] ?? []).map {
                GrammarPoint(point: $0["point"] as? String ?? "", explanation: $0["explanation"] as? String ?? "")
            }
            b.tokenGloss = (syn["tokenGloss"] as? [[String: Any]] ?? []).map {
                Token(surface: $0["surface"] as? String ?? "", lemma: $0["lemma"] as? String ?? "",
                      pos: $0["pos"] as? String ?? "", gloss: $0["gloss"] as? String ?? "")
            }
            a.syntax = b
        }
        return a
    }
}

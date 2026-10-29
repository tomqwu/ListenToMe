import Foundation
import XCTest
@testable import ListenToMeCore

/// Translated equivalents of the existing English semantic contract, not tuned to MPNet outputs.
@MainActor
final class MultilingualHistoryQualityTests: XCTestCase {
    func testGermanParaphrasesNegativesAndSmallTalk() async throws {
        try await check("de")
    }
    func testSpanishParaphrasesNegativesAndSmallTalk() async throws {
        try await check("es")
    }
    func testJapaneseParaphrasesNegativesAndSmallTalk() async throws {
        try await check("ja")
    }
    func testKoreanParaphrasesNegativesAndSmallTalk() async throws {
        try await check("ko")
    }

    private func check(_ language: String) async throws {
        guard let path = ProcessInfo.processInfo.environment["LISTENTOME_MPNET_TEST_ASSETS"], !path.isEmpty else {
            throw XCTSkip("Requires explicit installed local MPNet assets; never downloads")
        }
        let embedder = QualityVectorObserver(base: MultilingualHistoryEmbedder(
            installedModelDirectory: URL(fileURLWithPath: path), fallback: UnavailableAppleRuntime()))
        let fixture = try XCTUnwrap(Self.fixtures[language])
        let ids = ["budget", "hiring", "outage", "travel", "design", "lunch", "legal", "family"]
        let records = fixture[0].enumerated().map { offset, text in
            SessionRecord(id: ids[offset], title: ids[offset], date: Date(timeIntervalSince1970: Double(offset)),
                          transcript: text, summary: "",
                          segments: [TranscriptSegment(source: .others, text: text, isFinal: true, start: 0, end: 1)])
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MPNetQuality-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = HistoryIndex(directory: directory, embedder: embedder)
        try await index.sync(records)
        let observed = await embedder.passages
        XCTAssertEqual(Set(observed.values.map(\.model)), [MultilingualHistoryEmbedder.modelIdentifier],
                       "This quality gate must exercise MPNet even on hosts with Apple language assets")
        for record in records {
            let chunks = HistoryChunker.chunks(for: record)
            print("MPNet passage \(language) id=\(record.id) chunks=\(chunks.count) "
                  + "vectors=\(chunks.filter { observed[$0.text] != nil }.count) tokens=not-observed")
        }
        let expected = ["travel", "travel", "lunch", "lunch", "legal", "design", "family", "outage"]
        var found = 0
        for (query, target) in zip(fixture[1], expected) {
            XCTAssertFalse(SessionSearch.search(records, query: query).contains { $0.id == target }, "Fixture must not earn keyword credit: \(query)")
            let queryVectors = await embedder.embedQuery(query, models: [MultilingualHistoryEmbedder.modelIdentifier])
            let first = await index.search(query, in: records).first { $0.isRelated }
            print("MPNet quality \(language) query=\(query) models=\(queryVectors.map(\.model)) top=\(first?.id ?? "none") expected=\(target)")
            diagnose(query: query, target: target, records: records, directory: directory,
                     passages: observed, queries: queryVectors)
            if first?.id == target { found += 1 }
        }
        XCTAssertGreaterThanOrEqual(found, 6, "\(language): found \(found)/8 paraphrases (unchanged English criterion)")
        let fillers = fixture[3].enumerated().map { offset, text in
            SessionRecord(id: "filler\(offset)", title: "filler", date: .distantPast, transcript: text, summary: "",
                          segments: [TranscriptSegment(source: .you, text: text, isFinal: true, start: 0, end: 1)])
        }
        let all = records + fillers
        try await index.sync(all)
        let indexed = try await index.indexedIDs()
        XCTAssertEqual(indexed.count, all.count)
        for query in fixture[2] {
            let related = await index.search(query, in: all).filter(\.isRelated).map(\.id)
            XCTAssertTrue(related.isEmpty, "\(language) \(query): unrelated matches \(related)")
            let terms = HistoryQuestion.contentTerms(query)
            let byMeaning = await index.retrieve(query, in: all).filter { passage in
                !terms.contains { SessionSearch.fold(passage.text).contains($0) }
            }
            XCTAssertTrue(byMeaning.isEmpty, "\(language) \(query): sends unrelated meaning \(byMeaning.map(\.recordID))")
        }
        for text in fixture[3].prefix(2) {
            let vector = await embedder.embed(text, transcribedIn: language)
            XCTAssertNil(vector, "\(language): small talk must not create meaning matches")
        }
    }

    /// Reads the actual persisted quantized vectors. Raw cosine is separately labelled.
    private func diagnose(query: String, target: String, records: [SessionRecord], directory: URL,
                          passages: [String: HistoryVector], queries: [HistoryVector]) {
        let byModel = Dictionary(queries.map { ($0.model, $0.values) }, uniquingKeysWith: { first, _ in first })
        var scores: [(id: String, score: Float, raw: Float?)] = []
        for record in records {
            let file = directory.appendingPathComponent(record.id).appendingPathExtension("vectors")
            guard let data = try? Data(contentsOf: file), let stored = HistoryIndexFile.decode(data) else { continue }
            let chunks = HistoryChunker.chunks(for: record)
            for chunk in stored.chunks {
                guard let query = byModel[chunk.model], chunks.indices.contains(chunk.ordinal) else { continue }
                let original = passages[chunks[chunk.ordinal].text]
                let raw = original.flatMap { vector -> Float? in
                    guard vector.model == chunk.model, vector.values.count == query.count else { return nil }
                    return zip(vector.values, query).reduce(Float(0)) { $0 + $1.0 * $1.1 }
                }
                scores.append((record.id, chunk.similarity(query), raw))
            }
        }
        let ordered = scores.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        guard let expected = ordered.first(where: { $0.id == target }), let top = ordered.first else {
            print("MPNet score query=\(query) expected=\(target) reason=no-compatible-passage-vector")
            return
        }
        let parameters = HistoryRanking.Parameters()
        let mean = scores.reduce(Float(0)) { $0 + $1.score } / Float(scores.count)
        let floor = scores.count < parameters.gapSample ? max(parameters.floor, parameters.smallSampleFloor) : parameters.floor
        let passesGap = scores.count < parameters.gapSample || expected.score - mean >= parameters.minimumGap
        let rank = (ordered.firstIndex(where: { $0.id == target }) ?? -1) + 1
        let rawOrder = scores.filter { $0.raw != nil }.sorted { $0.raw! > $1.raw! }
        let rawRank = (rawOrder.firstIndex(where: { $0.id == target }) ?? -1) + 1
        print("MPNet score query=\(query) expected=\(target) "
              + "rawCosine=\(expected.raw.map { String($0) } ?? "unavailable") rawRank=\(rawRank) "
              + "storedScore=\(expected.score) storedRank=\(rank) mean=\(mean) "
              + "topScore=\(top.score) floor=\(floor) floorOK=\(expected.score >= floor) "
              + "gapOK=\(passesGap) marginOK=\(expected.score >= top.score - parameters.margin)")
    }

    private static let fixtures: [String: [[String]]] = [
        "de": [
            [
                "Wir haben das Quartalsbudget geprüft. Die Marketingausgaben liegen zwanzig Prozent darüber, deshalb will "
                    + "die Finanzabteilung Kosten senken und Neueinstellungen bis zum Abschluss der Finanzierungsrunde "
                    + "verschieben.",
                "Wir müssen drei weitere Bewerber für die Stelle als Backend-Entwickler interviewen. Der "
                    + "Personalvermittler plant nächste Woche die Vorstellungsgespräche vor Ort und versendet die Angebote.",
                "Die Datenbank fiel Dienstagnacht aus. Der Bereitschaftsingenieur stellte den Dienst nach zwei Stunden "
                    + "wieder her. Wir schreiben einen Bericht über den Vorfall.",
                "Wir buchen Flüge und ein Hotel für die Konferenz in Berlin. Dana kümmert sich um die Visumunterlagen und "
                    + "Formulare zur Reisekostenerstattung.",
                "Die neuen Einführungsbildschirme wirken klarer. Wir ändern die Schaltflächenfarben, vereinfachen das "
                    + "Anmeldeformular und testen das Layout mit fünf Nutzern.",
                "Allen hat das gemeinsame Mittagessen beim Italiener gefallen. Nächsten Monat probieren wir vielleicht "
                    + "das Sushi-Restaurant neben dem Büro.",
                "Die Anwälte prüften den Lieferantenvertrag. Vor der Unterschrift müssen die Haftungsklausel und die "
                    + "Kündigungsbedingungen korrigiert werden.",
                "Meine Tochter hat Samstagmorgen ein Fußballspiel, deshalb kann ich nicht am Ausflug teilnehmen. Mein "
                    + "Sohn ist außerdem erkältet.",
            ],
            [
                "Flughafen",
                "Reisepass",
                "Abendessen",
                "Mahlzeit",
                "Vereinbarung",
                "visueller Stil",
                "Kinder",
                "Ausfallzeit",
            ],
            [
                "Wetter",
                "der Plan für nächste Woche",
                "was haben wir beschlossen",
                "Quantenphysik",
                "Gitarrenunterricht",
                "Musikkonzert",
                "Klimawandel",
                "Kundenfeedback",
                "Autoreparatur",
                "Software",
            ],
            [
                "Okay, ja. Also, äh, mal sehen. Richtig, richtig. Klingt gut für mich.",
                "Kannst du mich hören? Ich glaube, du bist stummgeschaltet. Ja, jetzt höre ich dich.",
                "Wir haben beschlossen, dass wir es machen und dann sehen, was beim nächsten Mal passiert.",
            ],
        ],
        "es": [
            [
                "Revisamos el presupuesto trimestral. El gasto de marketing supera lo previsto en un veinte por ciento; "
                    + "finanzas quiere reducir costes y aplazar las nuevas contrataciones hasta cerrar la ronda de "
                    + "financiación.",
                "Necesitamos entrevistar a tres candidatos más para el puesto de ingeniero de backend. El reclutador "
                    + "organizará las entrevistas presenciales la próxima semana y enviará las cartas de oferta.",
                "La base de datos dejó de funcionar el martes por la noche. El ingeniero de guardia restableció el "
                    + "servicio tras dos horas y redactaremos un informe del incidente.",
                "Reservemos vuelos y un hotel para la conferencia de Berlín. Dana se encargará de los documentos del "
                    + "visado y los formularios de reembolso de viaje.",
                "Las nuevas pantallas de incorporación se ven más claras. Acordamos cambiar los colores de los botones, "
                    + "simplificar el formulario de registro y probar la distribución con cinco usuarios.",
                "A todos les gustó el almuerzo del equipo en el italiano. El mes que viene quizá probemos el restaurante "
                    + "de sushi cerca de la oficina.",
                "Los abogados revisaron el contrato del proveedor. Debemos corregir la cláusula de responsabilidad y las "
                    + "condiciones de rescisión antes de firmarlo.",
                "Mi hija tiene un partido de fútbol el sábado por la mañana, así que no puedo ir a la reunión fuera de la "
                    + "oficina. Mi hijo también está resfriado.",
            ],
            [
                "aeropuerto",
                "pasaporte",
                "cena",
                "comida",
                "convenio",
                "estilo visual",
                "niños",
                "interrupción",
            ],
            [
                "tiempo meteorológico",
                "el plan para la próxima semana",
                "qué decidimos",
                "física cuántica",
                "clases de guitarra",
                "concierto de música",
                "cambio climático",
                "opiniones de clientes",
                "reparación de coches",
                "software",
            ],
            [
                "Vale, sí. Bueno, eh, veamos. Claro, claro. Me parece bien.",
                "¿Puedes oírme? Creo que tienes el micrófono silenciado. Sí, ahora te oigo.",
                "Decidimos que lo haremos y luego veremos qué pasa la próxima vez.",
            ],
        ],
        "ja": [
            [
                "四半期の予算を確認しました。マーケティング支出が二割超過しているため、財務部は経費を削減し、資金調達が完了するまで新規採用を延期したいと考えています。",
                "バックエンド技術者の職に応募した人をあと三人面接する必要があります。採用担当者が来週の対面面接を調整し、内定通知を送ります。",
                "火曜日の夜にデータベースが停止しました。当番の技術者が二時間後にサービスを復旧しました。この障害の事後報告書を作成します。",
                "ベルリンでの会議のために航空券とホテルを予約しましょう。ダナが査証の書類と出張費精算の用紙を担当します。",
                "新しい導入画面はすっきりしています。ボタンの色を変え、登録フォームを簡素化し、五人の利用者でレイアウトを試すことにしました。",
                "イタリア料理店でのチームのランチは好評でした。来月は事務所の近くの寿司店を試すかもしれません。",
                "弁護士が取引先との契約を確認しました。署名の前に責任条項と解約条件を修正する必要があります。",
                "土曜日の朝に娘のサッカーの試合があるので、社外の集まりには参加できません。息子も風邪をひいています。",
            ],
            [
                "空港",
                "パスポート",
                "夕食",
                "食事",
                "協定",
                "見た目",
                "子供",
                "ダウンタイム",
            ],
            [
                "天気",
                "来週の計画",
                "何を決めたのか",
                "量子物理学",
                "ギター教室",
                "音楽コンサート",
                "気候変動",
                "顧客の意見",
                "自動車修理",
                "ソフトウェア",
            ],
            [
                "はい、そうですね。ええと、考えてみましょう。そうそう。いいと思います。",
                "聞こえますか。ミュートになっていると思います。はい、今は聞こえます。",
                "それをやると決めました。その後どうなるかは次回見てみましょう。",
            ],
        ],
        "ko": [
            [
                "분기 예산을 검토했습니다. 마케팅 지출이 이십 퍼센트 초과되어 재무팀은 비용을 줄이고 투자 유치가 끝날 때까지 신규 채용을 미루려고 합니다.",
                "백엔드 엔지니어 직무 지원자 세 명을 더 면접해야 합니다. 채용 담당자가 다음 주 대면 면접을 잡고 합격 제안서를 보낼 예정입니다.",
                "화요일 밤 데이터베이스가 중단되었습니다. 당직 엔지니어가 두 시간 뒤 서비스를 복구했고 사고 경위 보고서를 작성할 예정입니다.",
                "베를린 회의를 위한 항공편과 호텔을 예약합시다. 다나가 비자 서류와 출장비 환급 양식을 담당합니다.",
                "새로운 온보딩 화면이 더 깔끔합니다. 버튼 색상을 바꾸고 가입 양식을 간소화하며 사용자 다섯 명에게 레이아웃을 시험하기로 했습니다.",
                "모두 이탈리아 식당에서의 팀 점심을 좋아했습니다. 다음 달에는 사무실 근처 초밥 식당에 가볼까 합니다.",
                "변호사들이 공급업체 계약서를 검토했습니다. 서명하기 전에 책임 조항과 해지 조건을 수정해야 합니다.",
                "토요일 아침 딸의 축구 경기가 있어서 외부 모임에는 갈 수 없습니다. 아들도 감기에 걸렸습니다.",
            ],
            [
                "공항",
                "여권",
                "저녁 식사",
                "끼니",
                "협약",
                "시각적 스타일",
                "아이들",
                "장애 시간",
            ],
            [
                "날씨",
                "다음 주 계획",
                "무엇을 결정했나요",
                "양자 물리학",
                "기타 수업",
                "음악 공연",
                "기후 변화",
                "고객 의견",
                "자동차 수리",
                "소프트웨어",
            ],
            [
                "네, 그래요. 음, 어디 보자. 맞아요, 맞아요. 저는 좋습니다.",
                "제 말 들리세요? 음소거된 것 같아요. 네, 이제 들립니다.",
                "그 일을 하기로 했고 다음에 어떻게 되는지 보기로 했습니다.",
            ],
        ],
    ]
}

/// Keep optional-model quality independent of this host's installed Apple languages.
private struct UnavailableAppleRuntime: HistoryEmbedder {
    let signature = "quality-without-apple"
    func embed(_ text: String) -> HistoryVector? { nil }
    func embedQuery(_ query: String, models: Set<String>) -> [HistoryVector] { [] }
}

/// Transparent recorder: delegates every actual call, changes neither inputs nor returned vectors.
private actor QualityVectorObserver: HistoryEmbedder {
    nonisolated let signature: String
    private let base: any HistoryEmbedder
    private(set) var passages: [String: HistoryVector] = [:]
    init(base: any HistoryEmbedder) { self.base = base; signature = base.signature }
    func embed(_ text: String) async -> HistoryVector? {
        let result = await base.embed(text)
        passages[text] = result
        return result
    }
    func embed(_ text: String, transcribedIn language: String) async -> HistoryVector? {
        let result = await base.embed(text, transcribedIn: language)
        passages[text] = result
        return result
    }
    func embedQuery(_ query: String, models: Set<String>) async -> [HistoryVector] {
        await base.embedQuery(query, models: models)
    }
}

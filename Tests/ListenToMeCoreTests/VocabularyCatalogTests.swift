import XCTest
@testable import ListenToMeCore

/// The bundled preset vocabularies and their validation (issue #222).
final class VocabularyCatalogTests: XCTestCase {
    private func domain(_ terms: [String], id: String = "test", layout: [String] = ["A", "B"]) -> VocabularyDomain {
        VocabularyDomain(id: id, name: "Test", description: "A test conversation.", summaryLayout: layout, terms: terms)
    }

    private func terms(_ count: Int) -> [String] { (0..<count).map { "term\($0)" } }

    func testEveryPresetLoadsAndValidates() throws {
        let catalog = try VocabularyCatalog.loadAll()
        XCTAssertEqual(catalog.domains.map(\.id), VocabularyCatalog.presetIDs)
        XCTAssertEqual(catalog.domains.map(\.name),
                       ["Medical", "Legal", "Software & Cloud", "Engineering", "Finance", "Sales", "Education & Research"])
        for domain in catalog.domains {
            XCTAssertEqual(VocabularyCatalog.problems(in: domain), [], domain.id)
            XCTAssertGreaterThanOrEqual(domain.terms.count, 250, "a few hundred terms per preset: \(domain.id)")
            XCTAssertFalse(domain.summaryLayout.isEmpty)
        }
        XCTAssertEqual(VocabularyCatalog.bundled, catalog)
    }

    func testMedicalCarriesTheNotAMedicalDeviceNotice() throws {
        let medical = try XCTUnwrap(VocabularyCatalog.bundled.domain(id: "medical"))
        XCTAssertTrue(medical.notice?.contains("not a medical device") == true)
        XCTAssertEqual(medical.summaryLayout, ["History", "Findings", "Plan"])
        XCTAssertNil(VocabularyCatalog.bundled.domain(id: "engineering")?.notice)
        XCTAssertEqual(VocabularyCatalog.bundled.domain(id: "engineering")?.summaryLayout, ["Decisions", "Actions", "Risks"])
        XCTAssertNil(VocabularyCatalog.bundled.domain(id: "astrology"))
    }

    func testPresetsLeadWithTermsSpeechEnginesMishear() throws {
        let catalog = VocabularyCatalog.bundled
        let leading = { (id: String) in Set(catalog.domain(id: id)?.terms.prefix(100) ?? []) }
        XCTAssertTrue(leading("medical").isSuperset(of: ["metoprolol", "apixaban"]))
        XCTAssertTrue(leading("software-cloud").isSuperset(of: ["Kubernetes", "kubectl", "Terraform"]))
        XCTAssertTrue(leading("legal").isSuperset(of: ["res judicata", "voir dire", "habeas corpus"]))
    }

    func testProblemsFindsEveryKindOfMistake() {
        XCTAssertEqual(VocabularyCatalog.problems(in: domain(terms(200))), [])
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(10))).contains { $0.contains("10 terms") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(501))).contains { $0.contains("501 terms") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(199) + ["Term0"])).contains { $0.contains("duplicate") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(199) + [" padded"])).contains { $0.contains("padded") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(199) + ["one two three four five"]))
            .contains { $0.contains("too long") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(199) + [String(repeating: "x", count: 41)]))
            .contains { $0.contains("too long") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(200), layout: [])).contains { $0.contains("layout") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(200), layout: Array(repeating: "A", count: 7)))
            .contains { $0.contains("layout") })
        XCTAssertTrue(VocabularyCatalog.problems(in: domain(terms(200), id: "")).contains { $0.contains("required") })
    }

    func testDecodeRejectsAnInvalidOrMislabeledFile() throws {
        let valid = try JSONEncoder().encode(domain(terms(200)))
        XCTAssertEqual(try VocabularyCatalog.decode(valid).id, "test")
        XCTAssertThrowsError(try VocabularyCatalog.decode(valid, expectedID: "medical")) { error in
            XCTAssertTrue(error.localizedDescription.contains("medical vocabulary is invalid"))
            XCTAssertTrue(error.localizedDescription.contains("is not medical"))
        }
        let invalid = try JSONEncoder().encode(domain(terms(3)))
        XCTAssertThrowsError(try VocabularyCatalog.decode(invalid))
        XCTAssertThrowsError(try VocabularyCatalog.decode(Data("{}".utf8)))
    }

    func testAMissingPresetIsReported() {
        XCTAssertThrowsError(try VocabularyCatalog.load(id: "astrology")) { error in
            XCTAssertEqual(error as? VocabularyCatalogError, .missing("astrology"))
            XCTAssertEqual(error.localizedDescription, "The astrology vocabulary is missing from this build.")
        }
    }

    func testTokensKeepProgrammingAndAccountingSpellings() {
        XCTAssertEqual(VocabularyText.tokens("C++ and C# in the P&L, Node.js p-value"),
                       ["C++", "and", "C#", "in", "the", "P&L", "Node", "js", "p", "value"])
        XCTAssertTrue(VocabularyText.isAcronym("CBC"))
        XCTAssertTrue(VocabularyText.isAcronym("EC2"))
        XCTAssertTrue(VocabularyText.isAcronym("GD&T"))
        XCTAssertFalse(VocabularyText.isAcronym("bid"))
        XCTAssertFalse(VocabularyText.isAcronym("Kubernetes"))
        XCTAssertFalse(VocabularyText.isAcronym("A"))
        XCTAssertFalse(VocabularyText.isAcronym("IRB approval"))
        XCTAssertEqual(VocabularyText.normalizedTerm("  Kubernetes \n  cluster "), "Kubernetes cluster")
    }
}

import XCTest
@testable import DengueWatchBD

/// Keys the code builds at runtime, and keys nothing can reach.
///
/// `LocalizationHygieneTests` scans the source for `t("literal")`. Most of this
/// app does not ask that way: a symptom's label is `"symptom.\(id).title"`, a
/// lab measure's unit is `"lab.unit.\(rawValue)"`. A scanner sees the template,
/// not the 18 keys it produces, so renaming a case — or an entry in the table —
/// ships a row labelled `symptom.rash.title` with every test still green.
///
/// This walks the real values instead and asks the real table.
final class LocalizationReachabilityTests: XCTestCase {

    /// Every key any of the enumerable content types can produce.
    private func generatedKeys() -> Set<String> {
        var keys: Set<String> = []
        func add(_ produced: String...) { keys.formUnion(produced) }

        for tab in AppRouter.Tab.allCases { add(tab.titleKey) }
        for fact in MythFact.all { add(fact.mythKey, fact.factKey) }
        for topic in PreventionContent.topics {
            add(topic.titleKey, topic.summaryKey)
            keys.formUnion(topic.stepKeys)
        }
        for month in PreventionContent.seasonalPattern { add(month.labelKey, month.noteKey) }
        for task in PreventionTask.allCases { add(task.titleKey) }
        for number in EmergencyNumber.all { add(number.nameKey, number.detailKey) }
        for step in CheckerStep.allCases { add(step.titleKey, step.subtitleKey) }
        for group in Symptom.Group.allCases { add(group.titleKey, group.footnoteKey) }
        for symptom in TriageEngine.symptoms { add(symptom.titleKey, symptom.detailKey) }
        for outcome in TriageOutcome.allCases {
            add(outcome.headlineKey, outcome.summaryKey)
            keys.formUnion(outcome.actionKeys)
        }
        for phase in TriageEngine.FeverPhase.allCases { add(phase.nameKey, phase.key) }
        for range in TrendRange.allCases { add(range.labelKey) }
        for metric in MapMetric.allCases { add(metric.labelKey, metric.explanationKey) }
        for group in WHOCarePlan.Group.allCases {
            add(group.titleKey, group.detailKey)
            keys.formUnion(group.adviceKeys)
        }
        for reason in WHOCarePlan.Reason.allCases { add(reason.labelKey) }
        for trend in HealthTrend.allCases { add(trend.labelKey) }
        for status in MeasureStatus.allCases { add("status.\(status.rawValue)") }
        for kind in VitalKind.allCases { add(kind.labelKey, kind.unitKey) }
        for unit in TemperatureUnit.allCases { add(unit.labelKey) }
        for measure in LabMeasure.allCases { add(measure.labelKey, measure.unitKey) }
        for test in DengueTest.allCases { add(test.labelKey, test.usefulDaysKey) }
        for result in TestResult.allCases { add(result.labelKey) }
        for level in RiskLevel.allCases {
            add(level.labelKey, level.guidanceKey, level.headlineKey)
            add("risk.detail.band.\(level.rawValue)")
        }
        // Built from a loop index and from a prefix passed at the call site:
        // neither the template nor the values appear as a key in the source.
        for index in 1...5 { add("about.bullet\(index)") }
        for paragraph in 1...4 { add("intro.p\(paragraph).title", "intro.p\(paragraph).detail") }
        return keys
    }

    /// Every key the content types build must be in both tables.
    func testEveryGeneratedKeyIsTranslated() {
        var missingEnglish: [String] = []
        var missingBangla: [String] = []
        for key in generatedKeys().sorted() {
            if Strings.english[key] == nil { missingEnglish.append(key) }
            if Strings.bangla[key] == nil { missingBangla.append(key) }
        }
        XCTAssertTrue(missingEnglish.isEmpty, "built at runtime, missing from English: \(missingEnglish)")
        XCTAssertTrue(missingBangla.isEmpty, "built at runtime, missing from Bangla: \(missingBangla)")
    }

    /// No key is translated twice over into nothing.
    ///
    /// An orphan is a string somebody wrote, a translator read, and no reader
    /// will ever see. It is not a crash, but it is work spent and a trap: the
    /// next person to touch the feature edits the dead copy.
    func testNoKeyIsUnreachable() throws {
        let literal = try literalKeysInSource()
        let reachable = literal.union(generatedKeys())
        let orphans = Strings.english.keys.filter { !reachable.contains($0) }.sorted()
        XCTAssertTrue(orphans.isEmpty, "defined but nothing asks for them: \(orphans)")
    }

    // MARK: - Source scanning

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // DengueWatchBDTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("DengueWatchBD")
    }

    /// Every string literal in the app that looks like a key, outside the
    /// tables themselves. Deliberately generous: a false "reachable" hides an
    /// orphan, which is cheaper than a false failure on an SF Symbol name.
    private func literalKeysInSource() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #""([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)""#)
        var found: Set<String> = []
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift",
                  !(file.pathComponents.contains("Localization")
                    && file.lastPathComponent.hasPrefix("Strings")),
                  let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                found.insert(String(source[keyRange]))
            }
        }
        XCTAssertFalse(found.isEmpty, "the source tree was not found at \(sourceRoot.path)")
        return found
    }
}

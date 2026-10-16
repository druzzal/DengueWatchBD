import XCTest
@testable import DengueWatchBD

/// Runs the shared clinical cases in `clinical-rules.json`.
///
/// The Android build runs the same file, byte for byte, through its own
/// implementation. The two apps carry every clinical rule twice — triage, the
/// WHO plan, reading ranges, what a typed number means, what a scanned report
/// says — and nothing else checks that the two copies still agree. A rule
/// changed on one platform and not the other fails here, or there.
final class ClinicalConformanceTests: XCTestCase {

    private var cases: [String: Any] = [:]
    private var calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "clinical-rules", withExtension: "json"),
            "clinical-rules.json is missing from the test bundle")
        cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Dhaka"))
        now = try date(cases["now"])
    }

    // MARK: - Reading the file

    private func list(_ key: String) throws -> [[String: Any]] {
        let items = try XCTUnwrap(cases[key] as? [[String: Any]], "no \(key) cases")
        XCTAssertFalse(items.isEmpty, "no \(key) cases")
        return items
    }

    private func date(_ value: Any?) throws -> Date {
        let text = try XCTUnwrap(value as? String)
        return try XCTUnwrap(ISO8601DateFormatter().date(from: text), text)
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func context(_ value: Any?) -> TriageEngine.Context {
        let flags = value as? [String: Bool] ?? [:]
        return TriageEngine.Context(isPregnant: flags["isPregnant"] ?? false,
                                    isUnderFiveOrOverSixty: flags["isUnderFiveOrOverSixty"] ?? false,
                                    hasChronicCondition: flags["hasChronicCondition"] ?? false,
                                    hadDengueBefore: flags["hadDengueBefore"] ?? false)
    }

    private func hoursAgo(_ item: [String: Any]) -> Date {
        now.addingTimeInterval(-(double(item["hoursAgo"]) ?? 0) * 3600)
    }

    // MARK: - Cases

    func testTriage() throws {
        for item in try list("triage") {
            let selected = Set(item["selected"] as? [String] ?? [])
            let ctx = context(item["context"])
            let label = "\(selected.sorted()) \(item["context"] ?? "")"
            XCTAssertEqual(String(describing: TriageEngine.evaluate(selected: selected, context: ctx)),
                           item["outcome"] as? String, label)
            XCTAssertEqual(TriageEngine.isRaisedByRiskGroup(selected: selected, context: ctx),
                           item["raisedByRiskGroup"] as? Bool, label)
        }
    }

    func testFeverPhase() throws {
        for item in try list("feverPhase") {
            let days = try XCTUnwrap(item["feverDaysAgo"] as? Int)
            XCTAssertEqual(TriageEngine.FeverPhase.phase(feverDaysAgo: days).rawValue,
                           item["phase"] as? String, "day \(days)")
        }
    }

    func testCarePlan() throws {
        for item in try list("carePlan") {
            var vitals: VitalsEntry?
            if let readings = item["vitals"] as? [String: Any] {
                vitals = VitalsEntry(temperature: double(readings["temperature"]),
                                     pulse: double(readings["pulse"]),
                                     systolic: double(readings["systolic"]),
                                     diastolic: double(readings["diastolic"]),
                                     oxygenSaturation: double(readings["oxygenSaturation"]))
            }
            let plan = WHOCarePlan.evaluate(symptoms: Set(item["symptoms"] as? [String] ?? []),
                                            vitals: vitals,
                                            context: context(item["context"]),
                                            feverDaysAgo: item["feverDaysAgo"] as? Int)
            let label = "\(item["symptoms"] ?? "") \(item["vitals"] ?? "") \(item["context"] ?? "")"
            XCTAssertEqual(String(describing: plan.group), item["group"] as? String, label)
            XCTAssertEqual(plan.reasons.map(\.rawValue), item["reasons"] as? [String], label)
            XCTAssertEqual(plan.phase?.rawValue, item["phase"] as? String, label)
            XCTAssertEqual(plan.feverDay, item["feverDay"] as? Int, label)
        }
    }

    func testVitalStatus() throws {
        for item in try list("vitalStatus") {
            let kind = try XCTUnwrap(VitalKind(rawValue: item["kind"] as? String ?? ""))
            let value = try XCTUnwrap(double(item["value"]))
            XCTAssertEqual(kind.status(value).rawValue, item["status"] as? String, "\(kind) \(value)")
            XCTAssertEqual(kind.side(value).rawValue, item["side"] as? String, "\(kind) \(value)")
        }
    }

    func testLabStatus() throws {
        for item in try list("labStatus") {
            let measure = try XCTUnwrap(LabMeasure(rawValue: item["measure"] as? String ?? ""))
            let value = try XCTUnwrap(double(item["value"]))
            XCTAssertEqual(measure.status(value).rawValue, item["status"] as? String, "\(measure) \(value)")
            XCTAssertEqual(measure.side(value).rawValue, item["side"] as? String, "\(measure) \(value)")
        }
    }

    func testBloodPressure() throws {
        for item in try list("bloodPressure") {
            let systolic = try XCTUnwrap(double(item["systolic"]))
            let diastolic = try XCTUnwrap(double(item["diastolic"]))
            let pair = MeasureSide.bloodPressure(systolic: systolic, diastolic: diastolic)
            XCTAssertEqual(pair.side.rawValue, item["side"] as? String, "\(systolic)/\(diastolic)")
            XCTAssertEqual(pair.status.rawValue, item["status"] as? String, "\(systolic)/\(diastolic)")
        }
    }

    func testMeasureInput() throws {
        for item in try list("measureInput") {
            let text = item["text"] as? String ?? ""
            let reading: MeasureInput.Reading
            if let measure = (item["measure"] as? String).flatMap(LabMeasure.init(rawValue:)) {
                reading = MeasureInput.read(text, as: measure)
            } else {
                let kind = try XCTUnwrap(VitalKind(rawValue: item["kind"] as? String ?? ""))
                let unit = TemperatureUnit(rawValue: item["unit"] as? String ?? "") ?? .celsius
                reading = MeasureInput.read(text, as: kind, unit: unit)
            }
            let label = "\"\(text)\""
            switch (item["result"] as? String, reading) {
            case ("empty", .empty), ("notANumber", .notANumber):
                break
            case ("value", .value(let value)):
                XCTAssertEqual(value, try XCTUnwrap(double(item["value"])), accuracy: 0.0001, label)
            case ("outOfRange", .outOfRange(let range)):
                XCTAssertEqual(range.lowerBound, double(item["lower"]), label)
                XCTAssertEqual(range.upperBound, double(item["upper"]), label)
            default:
                XCTFail("\(label): expected \(item["result"] ?? ""), got \(reading)")
            }
        }
    }

    func testLabParser() throws {
        for item in try list("labParser") {
            let text = try XCTUnwrap(item["text"] as? String)
            let report = LabReportParser.draft(from: text)
            for measure in LabMeasure.allCases {
                let expected = double(item[measure.rawValue])
                let actual = report.value(for: measure)
                if let expected {
                    XCTAssertEqual(try XCTUnwrap(actual, "\(measure) in \(text)"), expected,
                                   accuracy: 0.001, "\(measure) in \(text)")
                } else {
                    XCTAssertNil(actual, "\(measure) in \(text)")
                }
            }
            for test in DengueTest.allCases {
                XCTAssertEqual(report.result(for: test).rawValue,
                               item[test.rawValue] as? String ?? "notDone", "\(test) in \(text)")
            }
        }
    }

    func testTrend() throws {
        for item in try list("trend") {
            let values = (item["values"] as? [NSNumber] ?? []).map(\.doubleValue)
            let trend = HealthTrend.direction(of: values, minimumChange: try XCTUnwrap(double(item["minimumChange"])))
            XCTAssertEqual(trend.rawValue, item["trend"] as? String, "\(values)")
        }
    }

    func testHaematocritRising() throws {
        for item in try list("haematocritRising") {
            let series = (item["series"] as? [[String: Any]] ?? []).map { point in
                (date: hoursAgo(point), value: double(point["value"]) ?? 0)
            }
            XCTAssertEqual(CarePlanContext.haematocritIsRising(series, now: now),
                           item["rising"] as? Bool, "\(item["series"] ?? "")")
        }
    }

    func testNotableReadings() throws {
        for item in try list("notableReadings") {
            let vitals = try (item["vitals"] as? [[String: Any]] ?? []).map { reading in
                (kind: try XCTUnwrap(VitalKind(rawValue: reading["kind"] as? String ?? "")),
                 value: double(reading["value"]) ?? 0, date: hoursAgo(reading))
            }
            let labs = try (item["labs"] as? [[String: Any]] ?? []).map { reading in
                (measure: try XCTUnwrap(LabMeasure(rawValue: reading["measure"] as? String ?? "")),
                 value: double(reading["value"]) ?? 0, date: hoursAgo(reading))
            }
            let context = CarePlanContext.from(vitals: vitals, labs: labs, now: now)
            XCTAssertEqual(context.notableVitals.map(\.rawValue), item["notableVitals"] as? [String])
            XCTAssertEqual(context.notableLabs.map(\.rawValue), item["notableLabs"] as? [String])
        }
    }

    func testWakingHours() throws {
        for item in try list("wakingHours") {
            let start = try date(item["start"])
            let end = try date(item["end"])
            XCTAssertEqual(FluidLog.wakingHours(from: start, to: end, calendar: calendar),
                           try XCTUnwrap(double(item["hours"])), accuracy: 0.001,
                           "\(item["start"] ?? "") → \(item["end"] ?? "")")
        }
    }

    func testUrineGap() throws {
        for item in try list("urineGap") {
            let urine = try (item["urine"] as? [String] ?? []).map { FluidEntry(date: try date($0), kind: .urine) }
            let drinks = try (item["drinks"] as? [String] ?? []).map {
                FluidEntry(date: try date($0), kind: .drink, millilitres: 200)
            }
            XCTAssertEqual(FluidLog.urineGapIsLong(entries: urine + drinks,
                                                   now: try date(item["now"]),
                                                   calendar: calendar),
                           item["long"] as? Bool, "\(item["urine"] ?? "") at \(item["now"] ?? "")")
        }
    }
}

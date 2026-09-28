import XCTest
@testable import DengueWatchBD

extension XCTestCase {

    /// A store filename unique to this test, deleted when the test finishes.
    ///
    /// The stores write into Application Support. On the simulator that is a
    /// scratch container and litter goes unnoticed; run the same suite against
    /// a phone — which is the only way to run it when no simulator runtime is
    /// installed — and it is the real app's container. Sixty-odd orphaned
    /// files had collected there before anyone looked.
    ///
    /// They were inert: every store reads one fixed filename and never
    /// enumerates the directory, so nothing ever opened them. Still not ours
    /// to leave on someone's phone.
    func temporaryStoreFilename(_ prefix: String) -> String {
        let name = "\(prefix)-\(UUID().uuidString).json"
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return name
    }
}

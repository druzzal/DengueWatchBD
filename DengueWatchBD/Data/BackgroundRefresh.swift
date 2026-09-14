import BackgroundTasks
import Foundation

/// Keeps the figures and the armed geofences current while the app is closed.
///
/// Two things depended on someone opening the app, and both are the kind of
/// thing a reader would reasonably assume happens by itself:
///
///   1. The home-area risk alert was only evaluated at launch and on
///      foreground, so a jump reported on Tuesday reached a reader who next
///      opened the app on Friday — on Friday.
///   2. The geofence list was armed from whatever the hotspots were the last
///      time the app was open, so an area that turned high while it was closed
///      was not watched at all.
///
/// iOS decides when this runs and gives no guarantee — typically a few times a
/// day, learned from how the app is used. So this is a way of arriving sooner,
/// not a schedule. Everything here still works if it never runs; it just works
/// later.
enum BackgroundRefresh {
    static let identifier = "bd.uzzal.denguewatch.refresh"

    /// Registered during launch, before the app finishes launching, as
    /// BGTaskScheduler requires.
    static func register() {
        // Delivered on the main queue: BGAppRefreshTask is not Sendable, and
        // asking for it here means the task never crosses an isolation
        // boundary on its way to the handler.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            // `using: .main` above is the guarantee: BGTaskScheduler delivers
            // this on the main queue, so the task is already where the handler
            // needs it. The compiler cannot read that from the API, so the
            // assumption is named here rather than left implicit — if the
            // registration queue ever changes, this comment is the thing that
            // has to change with it.
            nonisolated(unsafe) let delivered = task
            MainActor.assumeIsolated { handle(delivered) }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // DGHS publishes once a day. Asking for four hours lets iOS pick a
        // moment that suits the device rather than pinning it to a clock.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handle(_ task: BGAppRefreshTask) {
        // Always queue the next one first: if this run is killed, the chain
        // continues rather than stopping silently.
        schedule()

        let work = Task { @MainActor in
            let refreshed = await run()
            task.setTaskCompleted(success: refreshed)
        }

        task.expirationHandler = {
            // iOS calls this when it is taking back the time; cancelling is
            // all that is needed, and the work task reports completion.
            work.cancel()
        }
    }

    /// Fetch, re-arm, and alert. Returns whether the work got as far as
    /// applying a document.
    ///
    /// The collaborators are passed in rather than defaulted: default arguments
    /// are evaluated outside the actor, and all three are main-actor types.
    @MainActor
    @discardableResult
    static func run() async -> Bool {
        await run(store: DengueStore(), cache: FeedCache(), preferences: Preferences())
    }

    @MainActor
    @discardableResult
    static func run(store: DengueStore,
                    cache: FeedCache,
                    preferences: Preferences) async -> Bool {
        guard let summaryEndpoint = FeedConfig.summaryEndpoint,
              let latestEndpoint = FeedConfig.latestEndpoint else { return false }

        // Start from what is already on disk, so the report date we compare
        // against is the one the reader last saw.
        await store.load()

        let service = RemoteFeedService(summaryEndpoint: summaryEndpoint,
                                        latestEndpoint: latestEndpoint,
                                        validators: cache.validators)
        do {
            switch try await service.fetchIfChanged(knownReportDate: store.meta?.lastUpdated) {
            case .notModified:
                // Nothing new to say, but the geofences may still be stale from
                // an older run, so re-arm from what we have.
                rearm(store: store, preferences: preferences)
                return true
            case .updated(let document, let data, let validators):
                try cache.write(data: data, validators: validators)
                await store.apply(document: document, source: .network)
                rearm(store: store, preferences: preferences)
                await raiseHomeAreaAlert(store: store, preferences: preferences)
                return true
            }
        } catch {
            return false
        }
    }

    @MainActor
    private static func rearm(store: DengueStore, preferences: Preferences) {
        guard preferences.geofenceAlertsEnabled else { return }
        guard let hotspots = store.hotspotsToMonitor else { return }
        LocationManager.shared.monitorHighRiskAreas(hotspots)
    }

    @MainActor
    private static func raiseHomeAreaAlert(store: DengueStore, preferences: Preferences) async {
        guard preferences.alertsEnabled,
              let code = preferences.homeAreaCode,
              let area = store.area(code: code) else { return }
        await NotificationManager.shared.raiseRiskAlertIfNeeded(
            area: area,
            threshold: preferences.alertThreshold,
            localization: LocalizationManager()
        )
    }
}

import Foundation
import ListenToMeCore
@testable import ListenToMeIOS

/// Records every status the session publishes to the Apple Watch (issue #181).
@MainActor
final class FakeWatchLink: WatchLinking {
    private(set) var published: [PhoneRecorderStatus] = []

    func publish(_ status: PhoneRecorderStatus) { published.append(status) }
}

import Foundation
import Observation

/// Owns the user-requested Calendar task; platform adapters supply local lookup and UI bindings.
@MainActor @Observable
public final class CalendarContextCoordinator {
    public struct Snapshot: Sendable {
        public var conversationID: String
        public var notes: String
        public var title: String
        public var titleState: ConversationTitleState
        public init(conversationID: String, notes: String, title: String, titleState: ConversationTitleState) {
            self.conversationID = conversationID; self.notes = notes; self.title = title; self.titleState = titleState
        }
    }

    public struct Update: Sendable {
        public let conversationID: String
        public let notes: String?
        public let title: String?
        public let titleState: ConversationTitleState?
        public let error: String?
    }

    public private(set) var isLoading = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    public init() {}

    @discardableResult
    public func load(snapshot: @escaping @MainActor () -> Snapshot,
                     lookup: @escaping @MainActor () async -> CalendarLookup,
                     timeFormat: @escaping (Date) -> String,
                     apply: @escaping @MainActor (Update) -> Void) -> Task<Void, Never> {
        cancel()
        let token = generation
        let original = snapshot()
        isLoading = true
        let work = Task {
            defer {
                if generation == token { isLoading = false; task = nil }
            }
            guard !Task.isCancelled, generation == token else { return }
            let result = await lookup()
            guard !Task.isCancelled, generation == token else { return }
            let current = snapshot()
            guard current.conversationID == original.conversationID,
                  current.notes == original.notes else { return }
            guard case .meeting(let info) = result else {
                apply(Update(conversationID: current.conversationID, notes: nil, title: nil, titleState: nil,
                             error: result.message))
                return
            }
            let rename = ConversationAutoTitle.calendarMayReplace(state: current.titleState, title: current.title)
                && !info.title.isEmpty
            apply(Update(conversationID: current.conversationID,
                         notes: MeetingContext.notes(for: info, timeFormat: timeFormat),
                         title: rename ? info.title : nil, titleState: rename ? .calendar : nil, error: nil))
        }
        task = work
        return work
    }

    public func cancel() {
        generation = UUID()
        task?.cancel(); task = nil
        isLoading = false
    }
}

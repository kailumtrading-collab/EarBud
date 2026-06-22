import EventKit

enum CalendarWriter {
    private static let store = EKEventStore()

    static func requestCalendarAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    static func requestRemindersAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    /// `startDate` must be supplied explicitly — when a conversation only
    /// mentioned a meeting without agreeing on a time, the caller should
    /// prompt the person to pick one rather than us guessing an arbitrary
    /// fallback time.
    @discardableResult
    static func addEvent(for detected: DetectedEvent, startDate: Date) async throws -> Bool {
        guard try await requestCalendarAccess() else { return false }
        let event = EKEvent(eventStore: store)
        event.title = detected.title
        event.notes = detected.notes
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        return true
    }

    @discardableResult
    static func addReminder(for item: ActionItem) async throws -> Bool {
        guard try await requestRemindersAccess() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = item.description
        if let owner = item.owner {
            reminder.notes = "Owner: \(owner)"
        }
        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
        return true
    }
}

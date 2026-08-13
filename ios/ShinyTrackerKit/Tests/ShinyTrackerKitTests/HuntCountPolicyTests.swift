import Foundation
import Testing

@testable import ShinyTrackerKit

/// Each of these pins a scenario that reached a review as a real defect. They are written as the
/// failure that was found, not as coverage of the branches, so a future edit that reopens one of
/// them fails with the name of the bug it reintroduced.

// MARK: - Rebuild: which count a list refresh should show

/// A cold launch draws a snapshot, and that snapshot is stale by an entire previous session —
/// `.hunts` is only written on load, never on flush. Nothing about it is confirmed.
@Test func aSnapshotCountIsNeverTreatedAsConfirmed() {
    let decision = HuntCountPolicy.rebuild(
        response: 2_847, onScreen: 2_500, hasUnflushedBurst: false, isServerBacked: false)
    #expect(decision.count == 2_847)          // the server's number wins outright
    #expect(decision.isServerBacked)
}

/// The `LogPhaseHandler` case: a phase logged from the web resets the count to 0. iOS has no
/// `logPhase` call site, so that reset always arrives as someone else's write — and a stale
/// snapshot must not outrank it, or the next increment writes the pre-phase count back.
@Test func aPhaseResetIsNotOverriddenByAStaleSnapshot() {
    let decision = HuntCountPolicy.rebuild(
        response: 0, onScreen: 2_847, hasUnflushedBurst: false, isServerBacked: false)
    #expect(decision.count == 0)
}

/// An out-of-order response: a slow GET read 2,847, then a flush confirmed 2,850, then the slow
/// GET landed. The confirmed number must survive, or a later decrease writes the older one back.
@Test func anOutOfOrderResponseCannotLowerAConfirmedCount() {
    let decision = HuntCountPolicy.rebuild(
        response: 2_847, onScreen: 2_850, hasUnflushedBurst: false, isServerBacked: true)
    #expect(decision.count == 2_850)
    #expect(decision.isServerBacked)
}

/// A confirmed row still follows the server upward — `max` protects against lowering, it does not
/// pin the client to its own number.
@Test func aConfirmedRowStillFollowsTheServerUpward() {
    let decision = HuntCountPolicy.rebuild(
        response: 3_000, onScreen: 2_850, hasUnflushedBurst: false, isServerBacked: true)
    #expect(decision.count == 3_000)
}

/// Taps not yet written are newer than anything the server can report, so they win — but the row
/// stays unconfirmed until its own write lands, which is what stops a decrease being armed
/// against it.
@Test func anUnflushedBurstWinsAndStaysUnconfirmed() {
    let decision = HuntCountPolicy.rebuild(
        response: 2_847, onScreen: 2_499, hasUnflushedBurst: true, isServerBacked: false)
    #expect(decision.count == 2_499)
    #expect(decision.isServerBacked == false)
}

/// Even a row that was already confirmed loses its backing while a burst is pending: its on-screen
/// number is once again something the server has not seen.
@Test func anUnflushedBurstRevokesBackingForThatRefresh() {
    let decision = HuntCountPolicy.rebuild(
        response: 2_850, onScreen: 2_849, hasUnflushedBurst: true, isServerBacked: true)
    #expect(decision.count == 2_849)
    #expect(decision.isServerBacked == false)
}

/// A hunt seen for the first time has no on-screen value to compare against.
@Test func aFirstAppearanceTakesTheResponse() {
    let decision = HuntCountPolicy.rebuild(
        response: 12, onScreen: nil, hasUnflushedBurst: false, isServerBacked: false)
    #expect(decision.count == 12)
    #expect(decision.isServerBacked)
}

// MARK: - Arming: may this press lower the stored count?

/// The original data-loss path: offline cold launch showing a stale 2,500 against a server holding
/// 2,847. Permission here would send 2,499 as an absolute value and destroy 347 encounters.
@Test func aPressAgainstAnUnconfirmedCountNeverArms() {
    #expect(HuntCountPolicy.armsDecreasePermission(delta: -1, isServerBacked: false) == false)
}

@Test func aPressAgainstAConfirmedCountArms() {
    #expect(HuntCountPolicy.armsDecreasePermission(delta: -1, isServerBacked: true))
}

/// Increments never arm anything — the guard only exists to police downward writes.
@Test func incrementsNeverArm() {
    #expect(HuntCountPolicy.armsDecreasePermission(delta: 1, isServerBacked: true) == false)
    #expect(HuntCountPolicy.armsDecreasePermission(delta: 10, isServerBacked: true) == false)
    #expect(HuntCountPolicy.armsDecreasePermission(delta: 0, isServerBacked: true) == false)
}

// MARK: - Sending: both gates must agree

@Test func permissionRequiresBothTheUserAndTheBacking() {
    #expect(HuntCountPolicy.sendsDecreasePermission(userLowered: true, isServerBacked: true))
    #expect(HuntCountPolicy.sendsDecreasePermission(userLowered: true, isServerBacked: false) == false)
    #expect(HuntCountPolicy.sendsDecreasePermission(userLowered: false, isServerBacked: true) == false)
}

// MARK: - Reconciling with what the server stored

/// A clamped write heals upward rather than leaving the screen showing a number the server
/// rejected — the divergence that used to persist until the user pulled to refresh.
@Test func aClampedWriteHealsToTheStoredCount() {
    #expect(HuntCountPolicy.reconciled(local: 2_499, stored: 2_847) == 2_847)
}

/// Taps made while the request was in flight are real and must survive the response.
@Test func tapsMadeInFlightSurviveReconciliation() {
    #expect(HuntCountPolicy.reconciled(local: 2_853, stored: 2_850) == 2_853)
}

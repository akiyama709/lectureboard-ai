import Testing

@testable import LectureBoardCore

struct PostIdentityBoundaryFrameGateTests {
  @Test func startsOpenAndBeginsAClosedBoundaryWait() {
    var gate = PostIdentityBoundaryFrameGate()

    #expect(gate.state == .notRequired)
    #expect(!gate.requiresFreshFrame)

    _ = gate.beginWaiting(after: 100)

    #expect(gate.state == .waiting)
    #expect(gate.requiresFreshFrame)
  }

  @Test func rejectsMissingZeroEqualOlderAndIdleFramesWhileWaiting() {
    var gate = PostIdentityBoundaryFrameGate()
    _ = gate.beginWaiting(after: 100)

    let missing = gate.acceptFrame(isNewDelivery: true, displayTime: nil)
    let zero = gate.acceptFrame(isNewDelivery: true, displayTime: 0)
    let older = gate.acceptFrame(isNewDelivery: true, displayTime: 99)
    let equal = gate.acceptFrame(isNewDelivery: true, displayTime: 100)
    let idle = gate.acceptFrame(isNewDelivery: false, displayTime: 101)

    #expect(!missing)
    #expect(!zero)
    #expect(!older)
    #expect(!equal)
    #expect(!idle)
    #expect(gate.state == .waiting)
    #expect(gate.requiresFreshFrame)
  }

  @Test func acceptsOnlyAStrictlyNewerNewFrameAndOpensTheGate() {
    var gate = PostIdentityBoundaryFrameGate()
    _ = gate.beginWaiting(after: 100)

    let synchronized = gate.acceptFrame(isNewDelivery: true, displayTime: 101)
    #expect(synchronized)
    #expect(gate.state == .synchronized)
    #expect(!gate.requiresFreshFrame)
    let openGateAccepted = gate.acceptFrame(isNewDelivery: false, displayTime: nil)
    #expect(openGateAccepted)
  }

  @Test func zeroBoundaryFailsClosed() {
    var gate = PostIdentityBoundaryFrameGate()
    _ = gate.beginWaiting(after: 0)

    let accepted = gate.acceptFrame(isNewDelivery: true, displayTime: 1)
    #expect(!accepted)
    #expect(gate.state == .waiting)
    #expect(gate.requiresFreshFrame)
  }

  @Test func timeoutDoesNotOpenTheGateAndAFreshFrameStillRecovers() {
    var gate = PostIdentityBoundaryFrameGate()
    let token = gate.beginWaiting(after: 100)

    let didTimeOut = gate.markTimedOut(for: token)
    #expect(didTimeOut)
    #expect(gate.state == .timedOut)
    #expect(gate.requiresFreshFrame)
    let idle = gate.acceptFrame(isNewDelivery: false, displayTime: 101)
    let equal = gate.acceptFrame(isNewDelivery: true, displayTime: 100)
    #expect(!idle)
    #expect(!equal)
    #expect(gate.state == .timedOut)

    let recovered = gate.acceptFrame(isNewDelivery: true, displayTime: 101)
    #expect(recovered)
    #expect(gate.state == .synchronized)
    #expect(!gate.requiresFreshFrame)
    let staleTimeout = gate.markTimedOut(for: token)
    #expect(!staleTimeout)
  }

  @Test func staleTimeoutCannotAffectANewerBoundary() {
    var gate = PostIdentityBoundaryFrameGate()
    let staleToken = gate.beginWaiting(after: 100)
    let currentToken = gate.beginWaiting(after: 200)

    let staleTimeout = gate.markTimedOut(for: staleToken)
    #expect(!staleTimeout)
    #expect(gate.state == .waiting)
    let currentTimeout = gate.markTimedOut(for: currentToken)
    #expect(currentTimeout)
    #expect(gate.state == .timedOut)
  }

  @Test func resetOpensTheGateAndInvalidatesTheOldToken() {
    var gate = PostIdentityBoundaryFrameGate()
    let oldToken = gate.beginWaiting(after: 100)

    gate.reset()

    #expect(gate.state == .notRequired)
    #expect(!gate.requiresFreshFrame)
    let timeoutAfterReset = gate.markTimedOut(for: oldToken)
    #expect(!timeoutAfterReset)

    let newToken = gate.beginWaiting(after: 200)
    #expect(oldToken != newToken)
    let staleTimeout = gate.markTimedOut(for: oldToken)
    let currentTimeout = gate.markTimedOut(for: newToken)
    #expect(!staleTimeout)
    #expect(currentTimeout)
  }
}

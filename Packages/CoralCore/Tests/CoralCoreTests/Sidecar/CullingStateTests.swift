import Testing
@testable import CoralCore

@Suite("CullingState Tests")
struct CullingStateTests {

    @Test("Rating clamped to 0–5")
    func ratingClamp() {
        let tooHigh = CullingState(rating: 7)
        #expect(tooHigh.rating == 5)

        let tooLow = CullingState(rating: -1)
        #expect(tooLow.rating == 0)

        let normal = CullingState(rating: 3)
        #expect(normal.rating == 3)
    }

    @Test("setRating clamps value")
    func setRatingClamps() {
        var state = CullingState()
        state.setRating(10)
        #expect(state.rating == 5)
        state.setRating(-5)
        #expect(state.rating == 0)
    }

    @Test("Toggle flag: pick toggles to unflagged and back")
    func flagToggle() {
        var state = CullingState()
        #expect(state.flag == .unflagged)

        state.toggleFlag(.pick)
        #expect(state.flag == .pick)

        state.toggleFlag(.pick)
        #expect(state.flag == .unflagged)
    }

    @Test("Toggle flag: different flag replaces")
    func flagReplace() {
        var state = CullingState(flag: .pick)
        state.toggleFlag(.reject)
        #expect(state.flag == .reject)
    }

    @Test("Color label exclusivity")
    func labelExclusivity() {
        var state = CullingState()
        state.toggleLabel(.green)
        #expect(state.colorLabel == .green)

        state.toggleLabel(.blue)
        #expect(state.colorLabel == .blue)
    }

    @Test("Color label toggle off")
    func labelToggleOff() {
        var state = CullingState(colorLabel: .red)
        state.toggleLabel(.red)
        #expect(state.colorLabel == nil)
    }
}

import Testing
import VerityDomain
@testable import VerityKit

struct AppStateTests {
    @MainActor @Test func defaultsToRack() {
        #expect(AppState().selectedWorkspace == .rack)
    }
}

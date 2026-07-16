import CoreText
import Testing
@testable import VerityDesign

struct VerityDesignTests {
    @Test func stripCodesMatchLegacyBoard() {
        #expect(StripCode.make("Homework") == "HW")
        #expect(StripCode.make("Boards-Mathematics") == "B·MAT")
        #expect(StripCode.make("Boards-Science-Physics") == "B·PHY")
        #expect(StripCode.make("IRIS Research") == "IRIS")
    }

    @MainActor @Test func originalBoardFontsRegisterFromBundle() {
        VerityFonts.register()
        let mono = CTFontCreateWithName("IBMPlexMono-Regular" as CFString, 13, nil)
        let stencil = CTFontCreateWithName("SairaStencilOne-Regular" as CFString, 16, nil)
        #expect(CTFontCopyPostScriptName(mono) as String == "IBMPlexMono-Regular")
        #expect(CTFontCopyPostScriptName(stencil) as String == "SairaStencilOne-Regular")
    }
}

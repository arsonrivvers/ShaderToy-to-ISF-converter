import XCTest
@testable import ShadertoyISFKit

final class ChannelBindingTests: XCTestCase {
    func test_textureChannel_becomesImageInput() {
        let input = PassInput(id: "tex0", ctype: .texture, channel: 0)
        let map = ChannelBinding.resolve(inputs: [input], bufferOutputIDToName: [:])
        XCTAssertEqual(map.bindings[0]?.glslName, "iChannel0img")
        XCTAssertEqual(map.bindings[0]?.kind, .texture)
        XCTAssertTrue(map.warnings.isEmpty)
    }

    func test_bufferChannel_resolvesToBufferName() {
        let input = PassInput(id: "bufAout", ctype: .buffer, channel: 0)
        let map = ChannelBinding.resolve(inputs: [input],
                                         bufferOutputIDToName: ["bufAout": "bufA"])
        XCTAssertEqual(map.bindings[0]?.glslName, "bufA")
        XCTAssertEqual(map.bindings[0]?.kind, .buffer)
    }

    func test_unsupportedChannel_warnsAndStubsImage() {
        let input = PassInput(id: "kb", ctype: .keyboard, channel: 1)
        let map = ChannelBinding.resolve(inputs: [input], bufferOutputIDToName: [:])
        XCTAssertEqual(map.bindings[1]?.kind, .unsupported)
        XCTAssertEqual(map.warnings.count, 1)
        XCTAssertEqual(map.warnings[0].severity, .warning)
    }

    /// Audio channels (music/mic/musicstream) map to ISF's native audio inputs: an `audioFFT` sampler
    /// (glslName) + an `audio`/waveform sampler (auxName). Shadertoy packs both into one 512×2 texture
    /// (row y<0.5 = FFT, y≥0.5 = waveform); ISF splits them, so we carry both names.
    func test_audioChannel_mapsToFftAndWaveSamplers() {
        for ct in [ChannelType.music, .musicstream, .mic] {
            let map = ChannelBinding.resolve(inputs: [PassInput(id: "a", ctype: ct, channel: 2)],
                                             bufferOutputIDToName: [:])
            XCTAssertEqual(map.bindings[2]?.kind, .audio, "\(ct)")
            XCTAssertEqual(map.bindings[2]?.glslName, "iChannel2fft", "\(ct)")
            XCTAssertEqual(map.bindings[2]?.auxName, "iChannel2wave", "\(ct)")
            XCTAssertEqual(map.warnings.first?.severity, .info, "\(ct)")
        }
    }
}

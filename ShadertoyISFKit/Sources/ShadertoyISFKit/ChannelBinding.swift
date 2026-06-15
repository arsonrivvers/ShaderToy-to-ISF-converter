public struct ChannelBinding {
    public enum Kind: Equatable { case texture, buffer, cubemap, audio, unsupported }
    public struct Binding: Equatable {
        public let glslName: String   // sampler name used in rewritten GLSL (FFT sampler for audio)
        public let kind: Kind
        public let auxName: String?   // audio only: the waveform sampler (glslName is the FFT sampler)
        public init(glslName: String, kind: Kind, auxName: String? = nil) {
            self.glslName = glslName; self.kind = kind; self.auxName = auxName
        }
    }
    public struct Resolved {
        public var bindings: [Int: Binding]   // keyed by channel index 0...3
        public var warnings: [ConversionWarning]
    }

    /// - bufferOutputIDToName: maps a buffer pass output id → its ISF buffer name (e.g. "bufA").
    public static func resolve(inputs: [PassInput],
                               bufferOutputIDToName: [String: String]) -> Resolved {
        var bindings: [Int: Binding] = [:]
        var warnings: [ConversionWarning] = []
        for input in inputs {
            switch input.ctype {
            case .texture:
                bindings[input.channel] = Binding(glslName: "iChannel\(input.channel)img", kind: .texture)
            case .buffer:
                if let name = bufferOutputIDToName[input.id] {
                    bindings[input.channel] = Binding(glslName: name, kind: .buffer)
                } else {
                    bindings[input.channel] = Binding(glslName: "iChannel\(input.channel)img", kind: .texture)
                    warnings.append(ConversionWarning(severity: .warning,
                        message: "iChannel\(input.channel) references an unknown buffer; mapped to an image input.",
                        context: ""))
                }
            case .cubemap:
                // ISF has no cubemap input. Map to a 2D image and sample it via an equirectangular
                // (lat-long) projection of the 3D direction — the standard 2D fake for a cubemap.
                bindings[input.channel] = Binding(glslName: "iChannel\(input.channel)img", kind: .cubemap)
                warnings.append(ConversionWarning(severity: .warning,
                    message: "iChannel\(input.channel) is a cubemap; ISF has no cubemap input — mapped to a 2D image sampled via equirectangular projection. Supply an equirect (lat-long) image for correct results.",
                    context: ""))
            case .music, .musicstream, .mic:
                // Shadertoy audio is one 512×2 texture (row y<0.5 = FFT spectrum, y≥0.5 = waveform).
                // ISF splits these into native `audioFFT` + `audio` inputs, so carry both names; the
                // SamplerRewriter routes a sample to the right one by the read's y coordinate.
                bindings[input.channel] = Binding(glslName: "iChannel\(input.channel)fft", kind: .audio,
                                                  auxName: "iChannel\(input.channel)wave")
                warnings.append(ConversionWarning(severity: .info,
                    message: "iChannel\(input.channel) is '\(input.ctype.rawValue)' (audio) — mapped to ISF audioFFT + audio inputs; the host must supply audio for it to react.",
                    context: ""))
            case .keyboard, .webcam, .volume, .video:
                bindings[input.channel] = Binding(glslName: "iChannel\(input.channel)img", kind: .unsupported)
                warnings.append(ConversionWarning(severity: .warning,
                    message: "iChannel\(input.channel) is '\(input.ctype.rawValue)', which has no clean ISF equivalent — stubbed as an image input; verify manually.",
                    context: ""))
            }
        }
        return Resolved(bindings: bindings, warnings: warnings)
    }
}

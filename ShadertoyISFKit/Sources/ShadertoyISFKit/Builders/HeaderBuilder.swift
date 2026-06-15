import Foundation

public enum HeaderBuilder {
    public static func build(description: String,
                             credit: String,
                             imageInputNames: [String],
                             includeMouse: Bool,
                             bufferNames: [String],
                             audioFFTNames: [String] = [],
                             audioWaveNames: [String] = []) -> String {
        var inputs: [[String: Any]] = []
        for name in imageInputNames {
            inputs.append(["NAME": name, "TYPE": "image"])
        }
        // ISF native audio: an FFT-spectrum sampler and a raw-waveform sampler, each a 1D-ish texture
        // sampled like an image. MAX is the host's max bins/samples hint.
        for name in audioFFTNames {
            inputs.append(["NAME": name, "TYPE": "audioFFT", "MAX": 256])
        }
        for name in audioWaveNames {
            inputs.append(["NAME": name, "TYPE": "audio", "MAX": 256])
        }
        if includeMouse {
            inputs.append([
                // Centered default keeps iMouse.z > 0 at rest, so mouse-gated shaders are
                // engaged immediately rather than sitting in their "button up" branch.
                "NAME": "mouse", "TYPE": "point2D",
                "DEFAULT": [0.5, 0.5], "MIN": [0.0, 0.0], "MAX": [1.0, 1.0]
            ])
        }

        var header: [String: Any] = [
            "ISFVSN": "2.0",
            "DESCRIPTION": description,
            "CREDIT": credit,
            "CATEGORIES": ["Generator", "Shadertoy"],
            "INPUTS": inputs,
        ]

        if !bufferNames.isEmpty {
            var passes: [[String: Any]] = bufferNames.map {
                ["TARGET": $0, "PERSISTENT": true, "FLOAT": true]
            }
            passes.append([:])   // final output pass
            header["PASSES"] = passes
        }

        let data = try! JSONSerialization.data(withJSONObject: header,
            options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

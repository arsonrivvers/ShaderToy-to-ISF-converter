import Foundation

public enum HeaderBuilder {
    public static func build(description: String,
                             credit: String,
                             imageInputNames: [String],
                             includeMouse: Bool,
                             bufferNames: [String]) -> String {
        var inputs: [[String: Any]] = []
        for name in imageInputNames {
            inputs.append(["NAME": name, "TYPE": "image"])
        }
        if includeMouse {
            inputs.append([
                "NAME": "mouse", "TYPE": "point2D",
                "DEFAULT": [0.0, 0.0], "MIN": [0.0, 0.0], "MAX": [1.0, 1.0]
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

import Foundation
import Metal
import ISFMSLKit

/// Compiles ISF source text into an `ISFMSLScene` and describes its inputs. Shared by the editor's
/// preview controller and the instrument's decks so both go through the SAME crash-safe path and
/// produce the SAME input descriptors.
///
/// Compilation is synchronous and blocking (a full GLSL→SPIR-V→MSL transpile). Callers that must
/// not stall the main thread run `load` on a background queue and apply the result on main.
enum ISFSceneLoader {
    struct Result {
        let scene: ISFMSLScene?
        let inputs: [ISFPreviewInput]
        let errorMessage: String?
        let errorLine: Int?
        var isValid: Bool { scene != nil && errorMessage == nil }
    }

    /// Write `source` to a temp `.fs` and compile it. The temp file is removed before returning.
    static func load(source: String, device: MTLDevice) -> Result {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isfruntime-\(UUID().uuidString).fs")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return Result(scene: nil, inputs: [], errorMessage: "Could not stage shader source.",
                          errorLine: nil)
        }
        var compileError: ObjCBool = false
        var message: NSString?
        let scene = ISFMSLSafeCreateAndLoad(device, url, &compileError, &message)
        let msg = message as String?
        guard let scene, !compileError.boolValue else {
            return Result(scene: nil, inputs: [],
                          errorMessage: (msg?.isEmpty == false ? msg : "Shader failed to compile."),
                          errorLine: parseLine(from: msg))
        }
        return Result(scene: scene, inputs: mapInputs(scene.inputs),
                      errorMessage: nil, errorLine: nil)
    }

    /// Map ISFMSLKit scene attributes into the app-side input descriptors. Moved verbatim from
    /// `MetalPreviewController.mapInputs` — behavior must not change.
    static func mapInputs(_ attribs: [any ISFMSLSceneAttrib]) -> [ISFPreviewInput] {
        attribs.compactMap { attrib in
            let typeStr: String
            switch attrib.type {
            case .event:   typeStr = "event"
            case .bool:    typeStr = "bool"
            case .long:    typeStr = "long"
            case .float:   typeStr = "float"
            case .point2D: typeStr = "point2D"
            case .color:   typeStr = "color"
            case .image:   typeStr = "image"
            default:       return nil   // audio/cube: still unsupported
            }

            // Read default/min/max via doubleValue — works for all scalar types.
            // For point2D and color, store as [Double] so controls can read them.
            let defaultValue: Any?
            let minVal: Any?
            let maxVal: Any?

            switch attrib.type {
            case .color:
                let d = attrib.defaultVal
                defaultValue = [d.colorValue(by: 0), d.colorValue(by: 1),
                                d.colorValue(by: 2), d.colorValue(by: 3)]
                minVal = nil; maxVal = nil
            case .point2D:
                let d = attrib.defaultVal
                defaultValue = [d.pointValue(by: 0), d.pointValue(by: 1)]
                let mn = attrib.minVal
                minVal = [mn.pointValue(by: 0), mn.pointValue(by: 1)]
                let mx = attrib.maxVal
                maxVal = [mx.pointValue(by: 0), mx.pointValue(by: 1)]
            case .bool:
                defaultValue = attrib.defaultVal.boolValue
                minVal = nil; maxVal = nil
            case .event:
                defaultValue = nil; minVal = nil; maxVal = nil
            case .image:
                defaultValue = nil; minVal = nil; maxVal = nil
            default:
                defaultValue = attrib.defaultVal.doubleValue
                minVal = attrib.minVal.doubleValue
                maxVal = attrib.maxVal.doubleValue
            }

            let labels: [String]? = attrib.labelArray.isEmpty ? nil : attrib.labelArray
            let values: [Double]? = attrib.valArray.isEmpty ? nil
                : attrib.valArray.map { $0.doubleValue }

            return ISFPreviewInput(name: attrib.name, type: typeStr,
                                   defaultValue: defaultValue,
                                   min: minVal, max: maxVal,
                                   labels: labels, values: values)
        }
    }

    /// glslang error format: "ERROR: 0:NN:" → NN.
    static func parseLine(from msg: String?) -> Int? {
        guard let msg else { return nil }
        if let r = msg.range(of: #"0:(\d+):"#, options: .regularExpression) {
            let digits = msg[r].dropFirst(2).dropLast()
            return Int(digits)
        }
        return nil
    }
}

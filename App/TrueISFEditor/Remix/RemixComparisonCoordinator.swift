import Foundation
import QuartzCore
import Combine

struct RemixRenderSize: Equatable {
    var width: Int
    var height: Int
}

enum RemixParameterValue: Equatable {
    case float(Double)
    case bool(Bool)
    case integer(Int)
    case point(Double, Double)
    case color(Double, Double, Double, Double)

    var rendererJSON: String {
        switch self {
        case .float(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .point(let x, let y): return "[\(x),\(y)]"
        case .color(let r, let g, let b, let a): return "[\(r),\(g),\(b),\(a)]"
        }
    }
}

protocol RemixPreviewInputApplying: AnyObject {
    func setRemixInput(_ name: String, value: RemixParameterValue)
    func resetRemixInput(_ name: String)
}

enum RemixParameterControlKind: Equatable {
    case bool
    case float
    case long
    case point2D
    case color
    case unsupported(String)
}

/// Pure comparison state shared by both preview hosts. One coordinator instance means both
/// children observe one clock, render size, pause/reset transition, and compatible input store.
final class RemixComparisonCoordinator: ObservableObject {
    let clock: RenderClock
    private(set) var renderSize = RemixRenderSize(width: 1920, height: 1080)
    private(set) var isPaused = false

    private var inputTypesByPreview: [String: [String: String]] = [:]
    @Published private var sharedValues: [String: RemixParameterValue] = [:]
    @Published private var perPreviewValues: [String: [String: RemixParameterValue]] = [:]

    init(nowSource: @escaping () -> Double = { CACurrentMediaTime() }) {
        clock = RenderClock(nowSource: nowSource)
    }

    func clockForPreview(_ previewID: String) -> RenderClock { clock }

    func setRenderSize(width: Int, height: Int) {
        renderSize = RemixRenderSize(width: max(width, 1), height: max(height, 1))
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        paused ? clock.pause() : clock.resume()
    }

    func resetTime() { clock.reset() }

    func configure(leftISF: String, rightISF: String) {
        let leftDefinitions = Self.inputDefinitions(in: leftISF)
        let rightDefinitions = Self.inputDefinitions(in: rightISF)
        inputTypesByPreview = [
            "left": Dictionary(uniqueKeysWithValues: leftDefinitions.map { ($0.name, $0.type) }),
            "right": Dictionary(uniqueKeysWithValues: rightDefinitions.map { ($0.name, $0.type) }),
        ]
        sharedValues = [:]
        perPreviewValues = [:]
        let leftByName = Dictionary(uniqueKeysWithValues: leftDefinitions.map { ($0.name, $0) })
        let rightByName = Dictionary(uniqueKeysWithValues: rightDefinitions.map { ($0.name, $0) })
        compatibleInputNames.forEach { name in
            if let definition = leftByName[name] {
                sharedValues[name] = Self.parameterValue(
                    type: definition.type,
                    rawDefault: definition.rawDefault
                )
            }
        }
        incompatibleInputNames.forEach { name in
            if let definition = leftByName[name] {
                perPreviewValues["left", default: [:]][name] = Self.parameterValue(
                    type: definition.type,
                    rawDefault: definition.rawDefault
                )
            }
            if let definition = rightByName[name] {
                perPreviewValues["right", default: [:]][name] = Self.parameterValue(
                    type: definition.type,
                    rawDefault: definition.rawDefault
                )
            }
        }
    }

    var compatibleInputNames: Set<String> {
        let left = inputTypesByPreview["left"] ?? [:]
        let right = inputTypesByPreview["right"] ?? [:]
        return Set(left.compactMap { name, type in right[name] == type ? name : nil })
    }

    var incompatibleInputNames: [String] {
        let left = inputTypesByPreview["left"] ?? [:]
        let right = inputTypesByPreview["right"] ?? [:]
        return Set(left.keys).union(right.keys)
            .subtracting(compatibleInputNames)
            .sorted()
    }

    func inputType(for name: String, previewID: String) -> String? {
        inputTypesByPreview[previewID]?[name]
    }

    func setSharedValue(_ value: RemixParameterValue, for name: String) {
        guard compatibleInputNames.contains(name) else { return }
        sharedValues[name] = value
    }

    func setValue(_ value: RemixParameterValue, for name: String, previewID: String) {
        if compatibleInputNames.contains(name) {
            sharedValues[name] = value
        } else {
            perPreviewValues[previewID, default: [:]][name] = value
        }
    }

    func value(for name: String, previewID: String) -> RemixParameterValue? {
        sharedValues[name] ?? perPreviewValues[previewID]?[name]
    }

    func valuesForRenderer(_ previewID: String) -> [String: RemixParameterValue] {
        var values = perPreviewValues[previewID] ?? [:]
        sharedValues.forEach { values[$0.key] = $0.value }
        return values
    }

    func incompatibilityExplanation(for name: String) -> String? {
        let left = inputTypesByPreview["left"]?[name]
        let right = inputTypesByPreview["right"]?[name]
        switch (left, right) {
        case (.some(let left), .some(let right)) where left != right:
            return "\(name) stays per child because its types differ: \(left) and \(right)."
        case (.some, .none):
            return "\(name) stays per child because it is only available in the left child."
        case (.none, .some):
            return "\(name) stays per child because it is only available in the right child."
        default:
            return nil
        }
    }

    static func controlKind(for type: String) -> RemixParameterControlKind {
        switch type {
        case "bool": return .bool
        case "float": return .float
        case "long": return .long
        case "point2D": return .point2D
        case "color": return .color
        case "event": return .unsupported("Events are momentary and stay per child.")
        case "image": return .unsupported("Image sources stay per child.")
        default: return .unsupported("\(type) inputs are not editable in comparison mode.")
        }
    }

    private struct InputDefinition {
        let name: String
        let type: String
        let rawDefault: Any?
    }

    private static func inputDefinitions(in source: String) -> [InputDefinition] {
        guard let start = source.range(of: "/*"),
              let end = source.range(of: "*/", range: start.upperBound..<source.endIndex),
              let data = String(source[start.upperBound..<end.lowerBound]).data(using: .utf8),
              let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inputs = header["INPUTS"] as? [[String: Any]]
        else {
            return []
        }
        return inputs.compactMap { input in
            guard let name = input["NAME"] as? String,
                  let type = input["TYPE"] as? String
            else {
                return nil
            }
            return InputDefinition(name: name, type: type, rawDefault: input["DEFAULT"])
        }
    }

    private static func parameterValue(type: String, rawDefault: Any?) -> RemixParameterValue? {
        switch type {
        case "bool":
            return .bool((rawDefault as? Bool) ?? false)
        case "float":
            return .float((rawDefault as? NSNumber)?.doubleValue ?? 0)
        case "long":
            return .integer((rawDefault as? NSNumber)?.intValue ?? 0)
        case "point2D":
            let values = rawDefault as? [NSNumber]
            return .point(values?.first?.doubleValue ?? 0, values?.dropFirst().first?.doubleValue ?? 0)
        case "color":
            let values = (rawDefault as? [NSNumber])?.map(\.doubleValue) ?? []
            return .color(
                values.indices.contains(0) ? values[0] : 0,
                values.indices.contains(1) ? values[1] : 0,
                values.indices.contains(2) ? values[2] : 0,
                values.indices.contains(3) ? values[3] : 1
            )
        default:
            return nil
        }
    }
}

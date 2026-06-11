public struct PassBuilder {
    public struct Plan {
        public let renderPasses: [RenderPass]          // ordered: buffers then image
        public let orderedPassNames: [String]
        public let bufferOutputIDToName: [String: String]
        /// ISF buffer names (bufA, bufB, …) in pass order. Single source of truth — both the header
        /// PASSES TARGETs and the in-body sampler names derive from this, so they can't diverge.
        public let orderedBufferNames: [String]
        public let commonCode: String
        public let warnings: [ConversionWarning]
    }

    public static func build(passes: [RenderPass]) -> Plan {
        var warnings: [ConversionWarning] = []
        let common = passes.filter { $0.type == .common }.map(\.code).joined(separator: "\n")

        for p in passes where p.type == .sound || p.type == .cubemap {
            warnings.append(ConversionWarning(severity: .warning,
                message: "'\(p.name)' (\(p.type.rawValue)) pass cannot be converted to ISF and was skipped.",
                context: p.name))
        }

        let buffers = passes.filter { $0.type == .buffer }
            .sorted { $0.name < $1.name }   // "Buffer A" < "Buffer B" < ...
        let images = passes.filter { $0.type == .image }

        var idToName: [String: String] = [:]
        var orderedBufferNames: [String] = []
        let letters = ["A", "B", "C", "D"]
        for (i, buf) in buffers.enumerated() {
            let name = "buf\(i < letters.count ? letters[i] : String(i))"
            orderedBufferNames.append(name)
            for out in buf.outputs { idToName[out.id] = name }
        }

        let ordered = buffers + images
        return Plan(renderPasses: ordered,
                    orderedPassNames: ordered.map(\.name),
                    bufferOutputIDToName: idToName,
                    orderedBufferNames: orderedBufferNames,
                    commonCode: common,
                    warnings: warnings)
    }
}

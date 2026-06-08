import Foundation

/// Builds a `Shader` from raw GLSL pasted by the user (manual fallback when the
/// Cloudflare-gated fetch is unavailable). v1 supports a single Image pass.
public enum ShaderFactory {
    public static func singlePass(imageCode: String, name: String = "Pasted Shader") -> Shader {
        let pass = RenderPass(
            inputs: [],
            outputs: [PassOutput(id: "out0", channel: 0)],
            code: imageCode,
            name: "Image",
            type: .image)
        let info = Info(id: "", name: name, username: nil, description: nil)
        return Shader(info: info, renderpass: [pass])
    }
}

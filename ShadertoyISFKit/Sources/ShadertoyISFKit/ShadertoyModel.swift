import Foundation

public struct ShadertoyResponse: Decodable {
    public let shader: Shader
    enum CodingKeys: String, CodingKey { case shader = "Shader" }
}

public struct Shader: Decodable {
    public let info: Info
    public let renderpass: [RenderPass]
}

public struct Info: Decodable {
    public let id: String
    public let name: String
    public let username: String?
    public let description: String?
}

public enum PassType: String, Decodable {
    case image, buffer, common, sound, cubemap
}

public struct RenderPass: Decodable {
    public let inputs: [PassInput]
    public let outputs: [PassOutput]
    public let code: String
    public let name: String
    public let type: PassType
}

public struct PassOutput: Decodable {
    public let id: String
    public let channel: Int
}

public enum ChannelType: String, Decodable {
    case texture, buffer, keyboard, webcam, music, musicstream, mic
    case cubemap, volume, video
}

public struct PassInput: Decodable {
    public let id: String
    public let ctype: ChannelType
    public let channel: Int
}

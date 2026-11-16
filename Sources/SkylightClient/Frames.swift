import Foundation

extension SkylightClient {
    /// Returns every frame on the account.
    public func frames() async throws -> [Frame] {
        let data = try await request(method: "GET", path: "/api/frames")
        let doc = try JSONDecoder().decode(JSONAPIDocument<FrameAttributes>.self, from: data)
        return doc.data.map { resource in
            let name = resource.attributes.householdName.isEmpty
                ? resource.attributes.name
                : resource.attributes.householdName
            return Frame(id: resource.id, name: name)
        }
    }
}

// MARK: - JSON:API decoding helpers

struct JSONAPIDocument<A: Decodable & Sendable>: Decodable, Sendable {
    var data: [JSONAPIResource<A>]
}

struct JSONAPIResource<A: Decodable & Sendable>: Decodable, Sendable {
    var id: String
    var type: String
    var attributes: A
}

struct FrameAttributes: Decodable, Sendable {
    var name: String
    var householdName: String

    enum CodingKeys: String, CodingKey {
        case name
        case householdName = "household_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        householdName = try c.decodeIfPresent(String.self, forKey: .householdName) ?? ""
    }
}

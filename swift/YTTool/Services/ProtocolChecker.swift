import Foundation

enum ProtocolChecker {
    enum Result {
        case allowed
        case rejected(reason: String)
    }

    static let allowedComponents: Set<String> = [
        "http", "https", "m3u8", "m3u8_native",
    ]

    static func check(transportProtocol: String?) -> Result {
        guard let proto = transportProtocol else {
            return .rejected(reason: "nil (unknown protocol)")
        }
        guard !proto.isEmpty else {
            return .rejected(reason: "empty string")
        }
        guard proto == proto.lowercased(),
              proto.trimmingCharacters(in: .whitespaces) == proto
        else {
            return .rejected(reason: "non-canonical: \(proto)")
        }
        let components = proto.split(separator: "+", omittingEmptySubsequences: false)
            .map(String.init)
        for component in components {
            if component.isEmpty {
                return .rejected(reason: "empty component in compound: \(proto)")
            }
            if !allowedComponents.contains(component) {
                return .rejected(reason: "disallowed component: \(component)")
            }
        }
        return .allowed
    }
}

import Foundation
import Security

// Eenvoudige JSON-opslag in Application Support (vervangt chrome.storage.local).
enum Persist {
    private static var dir: URL {
        URL.applicationSupportDirectory.appending(path: "Newsticker", directoryHint: .isDirectory)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appending(path: "\(name).json")) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: dir.appending(path: "\(name).json"), options: .atomic)
        } catch {
            print("Opslaan mislukt (\(name)):", error)
        }
    }
}

// De OpenAI-key staat in de Keychain (alleen dit apparaat), niet in de JSON-bestanden.
enum Keychain {
    private static let service = "com.mkdebie.newsticker"

    static func get(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

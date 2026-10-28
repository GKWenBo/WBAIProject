import Foundation
import Security

/// Keychain 读写的协议抽象，让上层（AppSettings）不必直接依赖全局单例，
/// 测试也能换一个内存实现，避免碰到生产 Keychain 槽位。
protocol KeychainStoring {
    func save(_ value: String, for key: String) throws
    func read(_ key: String) -> String?
    func delete(_ key: String) throws
}

/// API Key 只落 Keychain，绝不进 UserDefaults。
enum KeychainStore: KeychainStoring {

    /// 仅用于承载协议实例方法的占位 case，本身不带任何数据。
    case instance

    /// 生产代码应通过这个实例访问，而不是直接调静态方法。
    static let shared: KeychainStoring = KeychainStore.instance

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    /// 通用密码项的 service 标识，account 为 `key(for:)` 的结果
    private static let service = "com.wenbo.WBChatApp-UIKit"

    /// 先尝试更新，不存在再新增（首次解锁后可读）
    static func save(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 每家服务商一个 Key
    static func key(for provider: ProviderKind) -> String {
        "apiKey.\(provider.rawValue)"
    }

    // MARK: - KeychainStoring：转发到静态实现，保持生产逻辑单一来源

    func save(_ value: String, for key: String) throws { try Self.save(value, for: key) }
    func read(_ key: String) -> String? { Self.read(key) }
    func delete(_ key: String) throws { try Self.delete(key) }
}

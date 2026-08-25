import Foundation
import CryptoKit

/// Стабільний UUID з рядка.
///
/// Потрібен там, де подія має бути ідемпотентною без власної сутності в БД:
/// наприклад «норма дня виконана» — одна подія на добу, яку можна відкотити за тим самим ключем.
public enum DeterministicID {
    public static func uuid(from string: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        var bytes = [UInt8](digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

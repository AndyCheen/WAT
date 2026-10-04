import Foundation

/// FNV-1a — хеш, стабільний між запусками процесу.
///
/// `String.hashValue` у Swift засівається випадково при старті процесу (без
/// `SWIFT_DETERMINISTIC_HASHING`). У `FixtureSeeder` через це «детерміновані» демо-дані
/// виходили різними на кожен прогін — серії 0, 2 і 1 з тим самим `FixedClock`, і це вже
/// коштувало одного хибного баг-репорту (PLAN.md, «Що з'ясувалося», п. 9).
///
/// Живе в `Core`, бо потрібен не лише фікстурам: сповіщення вибирають варіант тексту й
/// рахують відбиток запиту тим самим хешем (SPEC-NOTIFICATIONS §14.1, §16.2), а пакет
/// `Notifications` не бачить `Features`.
public enum StableHash {
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

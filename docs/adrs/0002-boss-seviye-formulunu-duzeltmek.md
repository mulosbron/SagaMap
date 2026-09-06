# 2. Boss seviye formülünü düzeltmek ve 2.0.0'a çıkmak

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`lib/src/core/domain/loot_table.dart:45`:

```dart
bool isBossLevel(int levelId) => levelId > 0 && levelId % 15 == 0;
```

ADR-0001 uyarınca `id` 0 tabanlı olduğuna göre bu fonksiyon id 15, 30, 45'i boss
sayıyor — yani oyuncunun gördüğü **16., 31., 46. seviyeyi**. "Her 15 seviyede bir
boss" demek `id % 15 == 14` demektir.

Bunun bir yazım hatası olmadığının, sistemin kendi içinde tutarsız olduğunun
kanıtı paketin kendi zorluk formülü (`saga_map_level_generator.dart:52`):

```dart
difficulty: 1 + (levelId % 5)
```

| id | Oyuncunun gördüğü | Zorluk | Bugünkü boss | `% 15 == 14` |
|---|---|---|---|---|
| 14 | 15. seviye | **5 (en zor)** | ✗ | ✓ |
| 15 | 16. seviye | **1 (en kolay)** | ✓ | ✗ |
| 29 | 30. seviye | **5** | ✗ | ✓ |
| 30 | 31. seviye | **1** | ✓ | ✗ |

Paket bugün **döngünün en kolay tahtasını boss ilan ediyor.** Oyuncu bunu bir hata
olarak görmez; oyunun tasarımı sanır ve boss'un kolay olduğunu düşünür. Sessiz
yanlışın en pahalı türü.

Mevcut test hatayı sabitliyor (`test/saga_domain_test.dart:89-95`):

```dart
test('marks every fifteenth level a boss, except level zero', () {
  expect(isBossLevel(15), isTrue);
  expect(isBossLevel(14), isFalse);
});
```

Testin başlığı içeriğiyle çelişiyor: "every fifteenth level" 15. seviyedir,
15. seviye ise id 14'tür. Test doğru şeyi sınadığını sanarak yanlışı koruyor.

Örnek uygulama da hatayı çoğaltıyor (`example/lib/main.dart:349`).

## Decision

Formül düzeltilir:

```dart
/// Whether [levelId] is a boss level.
///
/// Ids are zero-based (see [LevelData.id]), so "every fifteenth level" — the
/// 15th, 30th, 45th a player sees — is `id % 15 == 14`, not `id % 15 == 0`.
/// The latter lands on the 16th node and, because difficulty is `1 + id % 5`,
/// hands the boss the easiest board in the cycle.
bool isBossLevel(int levelId) => levelId >= 0 && levelId % 15 == 14;
```

Test, örnek ve testin başlığı buna göre güncellenir.

Bu değişiklik **kırıcıdır ve 2.0.0'ı gerektirir.** Hiçbir imza değişmediği,
hiçbir alan taşınmadığı için semver açısından "yama" gibi görünür; değildir.
Mevcut oyuncuların kayıtlı ödül geçmişi bir seviye kayar — kayıtlı verinin
*anlamı* değişir. Bu, bu paketin sürümleme politikasında majör bir değişikliktir
(bkz. `docs/reports/04-surumleme-ve-gecis-plani.md` §2).

Ertelenmesi reddedildi. Paketin tek bilinen tüketicisi var ve düzeltmenin maliyeti
bugün mümkün olan en düşük noktada; her yeni tüketici bu borcu büyütür.

## Consequences

### Olumlu
- Boss her zaman zorluk 5'e denk gelir; üç sistem (boss, zorluk, kilometre taşı)
  kendiliğinden hizalanır — `id % 15 == 14` aynı anda `id % 5 == 4`'tür.
- Test başlığı ile içeriği uyumlu hale gelir; test artık gerçekten "her on beşinci
  seviye" iddiasını sınar.
- Örnek uygulama doğru davranışı gösterir, kopyalanabilir hale gelir.

### Olumsuz
- **Kayıtlı ilerlemesi olan oyuncular etkilenir:** id 15/30/45 bir kez daha ödül
  verebilir; id 14/29/44 hiç vermemiş olabilir. Paket bunu göç ettiremez, çünkü
  ödüller host'un `InventoryRepository`'sinde ve paket oraya hiç yazmıyor (ADR-0003).
  Telafi kararı host'a aittir ve CHANGELOG'da açıkça istenmelidir.
- 2.0.0 çıkmak, `^1.0.0` kısıtı kullanan tüketiciler için elle yükseltme demektir.
- Eski davranışa ihtiyaç duyan host bir kaçış yolu ister; ADR-0003'ün `bossRule`
  enjeksiyonu bunu sağlar:
  `CompleteLevelUseCase(bossRule: (id) => id > 0 && id % 15 == 0)`.
  Bu, iki ADR'nin aynı sürümde çıkmasının gerekçesidir.

## Related

- ADR-0001 (id sözleşmesi) — bu kararın dayanağı
- ADR-0003 (enjekte edilebilir ödül) — geri uyum kaçış yolunu sağlar
- Görev: T-01, T-22

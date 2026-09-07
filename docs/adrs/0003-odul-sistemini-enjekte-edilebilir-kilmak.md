# 3. Ödül sistemini Strategy + Constructor Injection ile enjekte edilebilir kılmak

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`CompleteLevelUseCase` — paketin en yüksek seviye iş mantığı — alan kurallarına
doğrudan bağlı (`complete_level_usecase.dart:95,102`):

```dart
if (!isBossLevel(levelId) || !firstClear) { ... }
reward: rollBossReward(levelId: levelId, globalSeed: globalSeed, now: now),
```

Bağlandığı şeyler soyutlama değil, derleme zamanı sabitleri:

- `isBossLevel` — top-level fonksiyon (`loot_table.dart:45`)
- `rollBossReward` — top-level fonksiyon, tablo parametresi **almıyor** (`:48`)
- `kMvpLootTable` — `const` global, `rollBossReward` içinden doğrudan okunuyor (`:54,57`)

Üstelik `const CompleteLevelUseCase()` (satır 21) hiçbir bağımlılık kabul etmiyor.
Dart'ta top-level fonksiyon çağırmak, `applying-dip` becerisinin uyardığı
`new SmtpEmailService()` anti-deseninin birebir karşılığıdır.

İki somut sonuç:

**1. Host için:** Kendi ödül tablosunu, kendi nadirliklerini veya kendi boss
aralığını kullanamıyor. Üretimdeki tüketici bu yüzden paketin
`loot_table` + `inventory_repository` + `InventoryItem` üçlüsünün **tamamını**
kullanamadı; hepsini uygulama tarafında yeniden yazdı. Paketin bir alt sistemi
fiilen ölü kod.

**2. Paket için:** Ödül kolu test edilemiyor. `complete_level_usecase_test.dart`
ödülü ancak gerçek `kMvpLootTable` üzerinden sınayabiliyor — yani tabloya bir
eşya eklemek, tablo hakkında hiçbir iddiası olmayan geçiş testlerini kırar.
Test, sınamak istemediği bir şeye bağlı.

## Decision

`applying-dip` (Constructor Injection) ve `applying-strategy-pattern` reçeteleri
uygulanır. Kurallar sabitten parametreye taşınır; varsayılanlar korunur.

```dart
/// Decides whether a level is a boss encounter.
typedef SagaBossRule = bool Function(int levelId);

class CompleteLevelUseCase {
  const CompleteLevelUseCase({
    this.bossRule = isBossLevel,
    this.lootTable = kMvpLootTable,
  });

  /// Which levels drop a boss reward. Defaults to every fifteenth level.
  final SagaBossRule bossRule;

  /// Weighted table the reward is rolled from.
  final List<LootTableEntry> lootTable;
}

InventoryItem rollBossReward({
  required int levelId,
  required int globalSeed,
  List<LootTableEntry> table = kMvpLootTable,
  DateTime? now,
});
```

Ek kararlar:

- **Boş veya sıfır ağırlıklı tablo `ArgumentError` fırlatır.** Sessizce
  `kMvpLootTable`'a düşmek yasak: host, kendi tablosunun devrede olduğunu sanırken
  paketin varsayılanından eşya dağıtmak, teşhisi en zor hata türüdür.
- **`isBossLevel` public kalır.** Gerekçesi değişir: bugün "başka yolu yok" diye
  public; bundan sonra `bossRule`'un varsayılan değeri olduğu için public. Bu,
  tüketici raporunun B4-3 sorusuna cevaptır.
- **Determinizm korunur.** `Random(levelId ^ globalSeed)` tohumlaması değişmez;
  aynı `(levelId, globalSeed, table)` her zaman aynı eşyayı verir.
- **`InventoryRepository` enjeksiyonu bu ADR'ye dahil değildir** — 2.1.0'a
  bırakılır (T-14). 2.0.0'da yalnızca sözleşme yazılır: *"reward is returned,
  not persisted."*

Sınıf hiyerarşisi (`abstract class BossRule` + alt sınıflar) yerine `typedef`
seçildi. Kural tek metotlu ve durumsuz; sınıf kurmak `balancing-architectural-tradeoffs`
becerisinin "aşırı mühendislik" kırmızı bayrağına girer. Dart'ta bir fonksiyon
tipi zaten tam yetkili bir stratejidir.

## Consequences

### Olumlu
- Host kendi ödül ekonomisini paketin içinden kurabilir; `loot_table` alt sistemi
  ölü olmaktan çıkar.
- Ödül kolu test edilebilir hale gelir. Hedef: T-04 sonrası
  `complete_level_usecase_test.dart` içinde `kMvpLootTable` referansı kalmaması.
- SRP-1 kendiliğinden kapanır: `execute` artık "geçişi uygula, ödül kararını
  stratejiye sor" olur; ödül kuralı değiştiğinde bu metot değişmez.
- ADR-0002'nin kırıcı düzeltmesine bir kaçış yolu doğar:
  `bossRule: (id) => id > 0 && id % 15 == 0` eski davranışı birebir geri verir.
- A2 (`rarityOdds`) ve A3 (pity) bu kararın üstüne oturur; ikisi de tablo
  parametresi olmadan mümkün değildi.

### Olumsuz
- `rollBossReward` imzası değişir. İsteğe bağlı parametre olduğu için kaynak-uyumlu
  ama boş tablo artık istisna fırlattığından davranış-kırıcı bir kenar durum var.
- `CompleteLevelUseCase` iki alan kazanır; `const` kalabilmesi için varsayılanların
  `const` ifade olması gerekir (`isBossLevel` bir top-level fonksiyon referansı,
  `kMvpLootTable` bir `const` liste — ikisi de uygun).
- Host artık yanlış bir tablo geçebilir (ağırlıklar toplamı 0, negatif ağırlık).
  Doğrulama maliyeti pakete geçer — `ArgumentError` kararının nedeni.
- `isBossLevel`'ın public kalması, API yüzeyini küçültme fırsatını kapatır.
  Kabul edildi: varsayılan değer olarak görünür olması zorunlu.

## Related

- ADR-0002 (boss formülü) — aynı sürümde çıkar
- Görev: T-04, T-12, T-13, T-14
- Bulgu: DIP-1, OCP-1, OCP-2, SRP-1 (`docs/reports/01-solid-uyumluluk-denetimi.md`)

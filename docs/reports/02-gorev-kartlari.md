# 02 — Görev Kartları

Her kart: **kaynak madde → kök neden → uygulanan beceri → değişecek dosyalar →
kabul kriterleri → test → kırıcılık → efor.**

Efor ölçeği: **S** ≈ yarım gün, **M** ≈ 1-2 gün, **L** ≈ 3+ gün (test ve doküman dahil).

| Dalga | Görevler |
|---|---|
| **A — 1.1.0** (kırıcı değil) | T-02, T-03, T-05, T-07, T-08, T-09, T-10, T-12, T-15, T-17, T-19, T-21 |
| **B — 2.0.0** (kırıcı) | T-01, T-04, T-06, T-11, T-20, T-22 |
| **C — 2.1.0+** | T-13, T-14, T-16, T-18 |

---

## T-01 — `isBossLevel` off-by-one düzeltmesi 🔴

**Madde:** H1 · **Dalga:** B (2.0.0) · **Efor:** S · **ADR:** [0002](../adrs/0002-boss-seviye-formulunu-duzeltmek.md)
**Beceri:** `writing-adrs`, `balancing-architectural-tradeoffs`

### Kök neden
`LevelData.id` 0 tabanlı (`saga_map_level_generator.dart:34`, `saga_progress.dart:14-25`)
ama `loot_table.dart:45` 1 tabanlı varsayıyor.

### Kanıt
Paketin kendi zorluk formülü hizalamayı ele veriyor
(`saga_map_level_generator.dart:52`, `difficulty: 1 + (levelId % 5)`):

| id | Oyuncunun gördüğü | Zorluk | Bugünkü boss | Doğru boss |
|---|---|---|---|---|
| 14 | 15. seviye | **5 (en zor)** | ✗ | ✓ |
| 15 | 16. seviye | **1 (en kolay)** | ✓ | ✗ |

Paket bugün döngünün **en kolay tahtasını** boss ilan ediyor. `% 15 == 14`
kullanıldığında boss her zaman zorluk 5'e denk gelir ve `id % 5 == 4`
(kilometre taşı) koşulunu bedavaya sağlar — üç sistem kendiliğinden hizalanır.

### Değişecek dosyalar
- `lib/src/core/domain/loot_table.dart:45`
- `test/saga_domain_test.dart:89-95`
- `example/lib/main.dart:349` (→ T-22)

### Uygulama
```dart
/// Whether [levelId] is a boss level.
///
/// Ids are zero-based (see [LevelData.id]), so "every fifteenth level" — the
/// 15th, 30th, 45th a player sees — is `id % 15 == 14`, not `id % 15 == 0`.
/// The latter lands on the 16th node and, because difficulty is
/// `1 + id % 5`, hands the boss the easiest board in the cycle.
bool isBossLevel(int levelId) => levelId >= 0 && levelId % 15 == 14;
```

### Kabul kriterleri
- [ ] `isBossLevel(14) == true`, `isBossLevel(29) == true`, `isBossLevel(44) == true`
- [ ] `isBossLevel(15) == false`, `isBossLevel(0) == false`, `isBossLevel(-1) == false`
- [ ] Her boss id'si için `1 + (id % 5) == 5`
- [ ] Test başlığı içerikle uyumlu: "marks the 15th, 30th, 45th level a boss (zero-based ids 14, 29, 44)"
- [ ] CHANGELOG'da **BREAKING** başlığı altında, geçiş notu ile

### Test
```dart
test('boss levels always land on the hardest difficulty in the cycle', () {
  for (var id = 0; id < 100; id++) {
    if (isBossLevel(id)) expect(1 + (id % 5), 5);
  }
});
```

### Kırıcılık 🔴
Kayıtlı oyuncu ödül geçmişi kayar. 2.0.0 zorunlu. Geçiş notu:
*"Kaydedilmiş ilerlemesi olan oyuncularda id 15/30/45 bir kez daha ödül verebilir
ve id 14/29/44 hiç vermemiş olabilir. Host, `CompleteLevelResult.reward`'ı
kalıcılaştırırken bir kerelik telafi düşünmelidir."*

---

## T-02 — Ekran okuyucu etiketi `Level ${id + 1}` 🔴

**Madde:** H2 · **Dalga:** A (1.1.0) · **Efor:** S · **ADR:** [0001](../adrs/0001-leveldata-id-sozlesmesi.md)
**Beceri:** `optimizing-quality-attributes` (Erişilebilirlik)

### Kök neden
`widget_renderer_adapter.dart:37` ham indeksi duyuruyor: ilk düğüm **"Level 0"**.
Görme engelli kullanıcı ile gören kullanıcı aynı seviyeden bahsedemiyor.

### Uygulama
```dart
// Ids are zero-based; players count from one. The number announced must match
// the number drawn on the node, or a sighted and a screen-reader user cannot
// talk about the same level.
final buffer = StringBuffer('Level ${level.id + 1}');
```

### Kabul kriterleri
- [ ] `defaultSagaNodeSemanticsLabel(LevelData(id: 0, ...), null) == 'Level 1'`
- [ ] `SagaNodeSemanticsLabelBuilder` doküman yorumunda "ids are zero-based,
      the default label shows `id + 1`" cümlesi
- [ ] `test/saga_semantics_test.dart` beklentileri güncel

### Kırıcılık 🟢
Davranışsal düzeltme; API imzası değişmez. Kendi `semanticsLabelBuilder`'ını
veren host etkilenmez. CHANGELOG'da "Fixed" altında.

---

## T-03 — `SagaProgress` / `LevelProgress` genişletilebilirliği 🔴

**Madde:** A5 · **Dalga:** A (1.1.0) · **Efor:** M · **ADR:** [0004](../adrs/0004-saga-progress-genisletilebilirligi.md)
**Beceri:** `applying-ocp`, `applying-memento-pattern`

### Kök neden
`saga_progress.dart:4-11` yalnız `currentMaxUnlockedLevelId` + `Map<int, LevelProgress>`
taşıyor. Tüketici, harcanan yıldız / açılan sandık / görülen diyar / mod bazlı skor /
seri sayacı verilerini **aynı kutuda paralel anahtarlarla** tutan ikinci bir
repository yazmak zorunda kalmış. İki kayıt katmanının senkron kalması host'un sorunu.

### Seçenek değerlendirmesi

| Seçenek | Artı | Eksi | Karar |
|---|---|---|---|
| **A. `Map<String, dynamic> extra`** | Ucuz, JSON'da korunur, mevcut kodu bozmaz | Tip güvenliği yok | ✅ **Seçildi** |
| B. `SagaProgressRepository<T extends SagaProgress>` | Tip güvenli | Tüm imzalar generic olur, mevcut tüketiciler kırılır | ✗ |
| C. Ayrı `SagaProgressExtensions` kayıt defteri | Temiz | İki dosya, iki serileştirme yolu | ✗ |

Beceri notu (`applying-ocp`): amaç "uzatma için açık, değiştirme için kapalı".
Seçenek A bunu tek alanla sağlıyor; B tip güvenliği için mevcut sözleşmeyi kırıyor —
`balancing-architectural-tradeoffs`'un "olgunluk aşamasına uygun" ölçütüne göre
1.x için A doğru.

### Uygulama
```dart
class SagaProgress {
  /// Host-owned data the package stores but never interprets.
  ///
  /// Round-tripped through [toJson]/[fromJson] verbatim, so a host can keep
  /// spent stars, opened chests or per-mode scores next to progression without
  /// running a second persistence layer alongside this one. The package reads
  /// nothing from it and will never claim a key.
  final Map<String, dynamic> extra;
}
```

### Kabul kriterleri
- [ ] `extra` varsayılanı `const {}`; mevcut constructor çağrıları derlenmeye devam eder
- [ ] `toJson()` → `extra` boşsa anahtarı **hiç yazmaz** (eski kayıtlarla bit-uyumlu kalır)
- [ ] `fromJson()` → anahtar yoksa `{}`; `Map` değilse `{}` (bozuk kayda dayanıklı)
- [ ] `copyWith(extra: ...)` mevcut
- [ ] Aynısı `LevelProgress` için (mod bazlı yıldız skorları buraya sığar)
- [ ] Round-trip testi: `fromJson(toJson())` `extra`'yı birebir korur, iç içe `Map`/`List` dahil

### Kırıcılık 🟢
Yalnızca ekleme. `extra` boşken JSON çıktısı bugünküyle aynı kalır.

---

## T-04 — Enjekte edilebilir ödül sistemi 🔴

**Madde:** A1 (+ SRP-1, OCP-1, OCP-2, DIP-1) · **Dalga:** B (2.0.0) · **Efor:** M
**ADR:** [0003](../adrs/0003-odul-sistemini-enjekte-edilebilir-kilmak.md)
**Beceri:** `applying-dip`, `applying-strategy-pattern`, `applying-ocp`

### Kök neden
`complete_level_usecase.dart:95,102` alan kurallarını doğrudan çağırıyor;
`const CompleteLevelUseCase()` (satır 21) hiçbir bağımlılık kabul etmiyor.
Tüketici bu yüzden `loot_table` + `inventory_repository` + `InventoryItem`
üçlüsünün **tamamını** kullanamamış, hepsini yeniden yazmış.

### Uygulama
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

### Kabul kriterleri
- [ ] `CompleteLevelUseCase()` parametresiz çağrısı hâlâ derlenir ve bugünkü davranışı verir
- [ ] Özel `bossRule` verildiğinde ödül **yalnız** o kurala göre düşer
- [ ] Özel `lootTable` verildiğinde ödül **yalnız** o tablodan çıkar
- [ ] Boş tablo → `ArgumentError` (sessiz `kMvpLootTable`'a düşmek yasak; sessiz
      geri düşüş, host'un kendi tablosunun devrede olduğunu sanmasına yol açar)
- [ ] Toplam ağırlık `0` → `ArgumentError`
- [ ] Determinizm korunur: aynı `(levelId, globalSeed, table)` → aynı eşya
- [ ] `execute` içindeki `isBossLevel(...)` doğrudan çağrısı kalkar

### Test
```dart
test('uses the injected boss rule instead of the default', () {
  const useCase = CompleteLevelUseCase(bossRule: _everyThird);
  // id 2 boss (0-tabanlı 3. seviye), id 14 değil
});

test('rolls only from the injected table', () { /* tek girdili tablo */ });
test('rejects an empty loot table', () {
  expect(() => rollBossReward(levelId: 14, globalSeed: 1, table: const []),
      throwsArgumentError);
});
```

### Kırıcılık 🟡
`rollBossReward`'a isteğe bağlı parametre eklemek kaynak-uyumlu; ancak T-01 ile
birlikte aynı sürümde çıkacağı için 2.0.0'a dahil. `isBossLevel` public kalır
(varsayılan değer olarak gerekli) — bkz. B4-3 notu, T-19.

---

## T-05 — Builder'lara chunk bağlamı 🔴

**Madde:** A7 · **Dalga:** A (1.1.0) · **Efor:** M · **ADR:** [0006](../adrs/0006-builder-baglami-ve-seviye-hizali-dekor.md)
**Beceri:** `applying-builder-pattern`

### Kök neden
`saga_map_decoration.dart:87-90` ve `saga_infinite_map_view.dart:143` builder'a
yalnız `chunkIndex` veriyor. Host, chunk'ın `LevelData`'larını göremiyor:
**`biomeId` ve `difficulty` builder'a ulaşmıyor.** `controller.chunkLevels()` var
ama (a) builder içinden controller'a uzanmak gerekiyor, (b) tahliye edilmiş chunk
boş dönüyor (`saga_infinite_map_controller.dart:86`).

**Sonuç:** Paket her seviye için `biomeId` üretiyor (`saga_map_level_generator.dart:51`),
tüketici bunu **hiç okumamış** — chunk index'ten kendi diyar eşlemesini yapmış.
Üretilen alan ölü.

### Uygulama
```dart
/// Everything a decoration or header builder needs about one chunk.
class SagaChunkContext {
  final int chunkIndex;
  final List<LevelData> levels;
  final Map<int, LevelProgress> progress;
  /// The biome most of this chunk sits in, already resolved.
  final String dominantBiomeId;
}

typedef SagaMapDecorationBuilder =
    List<SagaMapDecoration> Function(BuildContext context, SagaChunkContext chunk);

typedef SagaEpisodeHeaderBuilder =
    Widget? Function(BuildContext context, SagaChunkContext chunk);
```

`getDominantBiomeId` zaten var (`saga_dominant_biome.dart`) — bağlama koymak
maliyetsiz ve `biomeId` alanını ilk kez kullanılabilir kılıyor.

### Geçiş (kırıcı olmayan yol)
- Eski `SagaMapDecorationBuilder` → `SagaMapLegacyDecorationBuilder` olarak
  `@Deprecated('Use decorationBuilder with SagaChunkContext. Removed in 3.0.0.')`
- `SagaInfiniteMapView` iki parametreyi de kabul eder; ikisi birden verilirse
  `assert` ile uyarır, yenisi kazanır.

### Kabul kriterleri
- [ ] Builder içinden `chunk.levels` boş dönmez — tahliye edilmiş chunk'ta bile
      builder çağrılmadan önce seviyeler üretilmiştir
- [ ] `chunk.progress` yalnız o chunk'ın seviyelerini içerir (tüm harita değil)
- [ ] Eski imza 1.1.0'da çalışmaya devam eder, deprecation uyarısı verir
- [ ] `test/saga_decoration_test.dart` yeni bağlamı doğrular

---

## T-06 — Kapı ↔ ilerleme bağı 🔴

**Madde:** A9 (+ OCP-4, DIP-2) · **Dalga:** B (2.0.0) · **Efor:** L
**ADR:** [0005](../adrs/0005-kapiyi-ilerleme-engeline-baglamak.md)
**Beceri:** `applying-dip`, `applying-state-pattern`

### Kök neden — rapordan ağır
`clampTravelThroughGates` (`saga_map_gate.dart:36`) paket içinde **hiçbir yerden
çağrılmıyor**. `SagaInfiniteMapView`'in `gates` parametresi yok. Kapı:

- karakterin yürüyüşünü paket adına kesmiyor (host elle çağırmalı),
- düğüme dokunmayı engellemiyor (`SagaNodeInteractionPolicy` kapılardan habersiz),
- kilit açmayı engellemiyor (`complete_level_usecase.dart:69` koşulsuz `levelId + 1`).

Yani "önceki boss geçilmeden sonraki blok açılmasın" mekaniği pakette **yok**.
Tüketici bunu host tarafında `BossRules.isUnlocked(...)` olarak yeniden yazmış ve
paketin kendi kilit mantığının yerine geçirmiş.

### Uygulama — üç dikiş
```dart
// 1) Etkileşim: dokunma kapıya danışsın
class SagaNodeInteractionPolicy {
  /// Host veto on reaching a node at all — a closed gate, a ticket, a purchase.
  /// Consulted before [canTap]; returning false makes the node unreachable
  /// regardless of its recorded progress state.
  final bool Function(LevelData level, LevelProgress? progress)? isReachable;
}

// 2) İlerleme: kilit açma kapıya danışsın
class CompleteLevelUseCase {
  /// Vetoes unlocking the successor. Returning false completes the level but
  /// leaves the next one locked — the gate stays shut.
  final bool Function(int levelId)? canUnlock;
}

// 3) Görünüm: kapıları paket taşısın
class SagaInfiniteMapView {
  final List<SagaMapGate> gates;   // clampTravelThroughGates paket içinde uygulanır
}
```

### Kabul kriterleri
- [ ] `isReachable` false dönen düğüm: `canTap` false, `Semantics.enabled` false,
      Tab sırasında atlanır, `SagaNodeInteractionState.locked` yayılır
- [ ] `canUnlock(levelId + 1)` false → seviye `completed` olur, ardıl `locked` kalır,
      `currentMaxUnlockedLevelId` **artmaz**
- [ ] `gates` verildiğinde karakter kapalı kapının önünde durur (host `clampTravelThroughGates`
      çağırmadan)
- [ ] Kapı açıldığında (`isOpen: true`) davranış bugünküyle aynı
- [ ] `isReachable` ve `canUnlock` `null` iken davranış birebir 1.x

### Kırıcılık 🟡
Varsayılanlar `null` olduğu için davranış korunur; ancak `SagaInfiniteMapView`'e
yeni parametre ve `CompleteLevelResult` semantiğine yeni bir sonuç durumu
(tamamlandı ama açılmadı) girdiği için 2.0.0'a alındı.

---

## T-07 — `canLongPress` politikası 🟡

**Madde:** H3 (+ ISP-2) · **Dalga:** A (1.1.0) · **Efor:** S
**Beceri:** `applying-ocp`, `applying-isp`

### Kök neden
`widget_renderer_adapter.dart:180-182`: `onTap` → `emitTap` → policy kontrolü
(satır 99-112); `onLongPress` → doğrudan callback, **kontrolsüz**. Sonuç:
`emitTapForLockedNode: false` diyen host, kilitli düğüme uzun basıldığında
yine de callback alıyor.

### Uygulama
```dart
class SagaNodeInteractionPolicy {
  /// Whether a long press should be accepted.
  ///
  /// Defaults to [canTap]: a node you cannot open is a node you cannot open a
  /// context menu on either. Override when the secondary action should stay
  /// available on locked nodes — a "how do I unlock this?" hint, say.
  bool canLongPress(LevelData level, LevelProgress? progress) =>
      canTap(level, progress);
}
```

### Kabul kriterleri
- [ ] `emitTapForLockedNode: false` + kilitli düğüm + uzun basma → callback **yok**
- [ ] Bunun yerine `onNodeFocusChange(level, locked)` yayılır (tap ile aynı geri bildirim)
- [ ] `canLongPress` override eden host, `canTap`'ten bağımsız davranabilir
- [ ] Alt sınıflandırma için `SagaNodeInteractionPolicy` `final` değil

---

## T-08 — Uzun basmanın klavye ve ekran okuyucuya açılması 🟡

**Madde:** H4 · **Dalga:** A (1.1.0) · **Efor:** M
**Beceri:** `optimizing-quality-attributes` (Erişilebilirlik)

### Kök neden
`widget_renderer_adapter.dart:125-145`: `Semantics` yalnız `onTap` tanımlıyor;
`FocusableActionDetector.actions` yalnız `ActivateIntent` / `ButtonActivateIntent`
taşıyor. Uzun basmaya bağlanan her özellik (tüketicide: seviyeyi farklı modlarda
tekrar oynama menüsü) **yalnızca dokunmatik kullanıcıya açık**.

CHANGELOG "Keyboard navigation: Tab visits nodes in level order, Enter and Space
activate" diyor — ikincil eylem için bir yol yok.

### Uygulama
```dart
Semantics(
  button: true,
  onTap: canTap ? emitTap : null,
  onLongPress: canLongPress ? emitLongPress : null,   // T-07'ye bağlı
  ...
  child: FocusableActionDetector(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.f10, shift: true): _SagaContextMenuIntent(),
      SingleActivator(LogicalKeyboardKey.contextMenu): _SagaContextMenuIntent(),
    },
    actions: {
      ...,
      _SagaContextMenuIntent: CallbackAction<_SagaContextMenuIntent>(
        onInvoke: (_) => emitLongPress(),
      ),
    },
  ),
)
```

### Kabul kriterleri
- [ ] TalkBack/VoiceOver "çift dokun ve basılı tut" ikincil eylemi duyuruyor
- [ ] Odaklı düğümde `Shift+F10` ve bağlam menüsü tuşu `onNodeLongPress` tetikliyor
- [ ] `canLongPress` false iken ne semantik eylem ne kısayol devrede
- [ ] `test/saga_keyboard_test.dart` ve `test/saga_semantics_test.dart` genişletildi

### Not
T-07 ile birlikte tek PR'da yapılmalı — ikisi aynı satırlara dokunuyor.

---

## T-09 — `saveGlobalSeed` 🟡

**Madde:** A6 (+ ISP-1) · **Dalga:** A (1.1.0) · **Efor:** S
**Beceri:** `applying-isp`

### Kök neden
`saga_progress_repository.dart:4-13` asimetrik: `loadGlobalSeed()` var,
karşılığı yok. Tüketici tohumu `loadGlobalSeed()` **içinde yan etki olarak**
diske yazmak zorunda kalmış. "Haritayı yeniden üret / tohumu değiştir" özelliği
sözleşme düzeyinde imkânsız.

### Uygulama
```dart
abstract interface class SagaProgressRepository {
  Future<SagaProgress> loadProgress();
  Future<void> saveProgress(SagaProgress progress);

  /// Loads the global map seed. Implementations must not persist as a side
  /// effect of loading; write the seed with [saveGlobalSeed] instead.
  Future<int> loadGlobalSeed();

  /// Persists the global map seed.
  ///
  /// Changing a stored seed regenerates the whole map: level positions, biomes
  /// and boss rewards all derive from it. Existing [SagaProgress] keeps its
  /// level ids but those ids now point at different terrain.
  Future<void> saveGlobalSeed(int seed);
}
```

### Kabul kriterleri
- [ ] `InMemorySagaProgressRepository` uygular
      (`lib/src/adapters/repositories/in_memory_saga_progress_repository.dart`)
- [ ] `loadGlobalSeed` doküman yorumu yan etkiyi açıkça yasaklar
- [ ] Tohum değiştirmenin sonucu (harita yeniden üretilir) doküman yorumunda

### Kırıcılık 🟡
`abstract interface class`'a metot eklemek, arayüzü **uygulayan** host için
kaynak-kırıcıdır. 1.1.0'da geçmek için: metodu `abstract interface class` yerine
varsayılan gövdeli bir `mixin`/base sınıfla sunmak yerine, CHANGELOG'da
"implementors must add saveGlobalSeed" notuyla **minör kırıcı** kabul edilebilir —
ya da 2.0.0'a ertelenir. **Karar:** ADR-0004'te ele alınacak; öneri 1.1.0'da
`UnimplementedError` fırlatan varsayılan gövde ile ekleyip 2.0.0'da soyuta çevirmek
LSP'yi bozacağı için **reddedildi**; 2.0.0'a alınması önerilir.

> ⚠️ Bu, dalga planındaki tek belirsizlik. Sürüm sahibi karar vermeli.

---

## T-10 — `SagaMapDecoration.atLevel` 🟡

**Madde:** A8 · **Dalga:** A (1.1.0) · **Efor:** M · **ADR:** [0006](../adrs/0006-builder-baglami-ve-seviye-hizali-dekor.md)
**Beceri:** `applying-facade-pattern`

### Kök neden
Belirli bir seviyenin **hizasında, tam genişlikte** bant (kilometre taşı / boss
afişi) koymak için:

- `besidePath(pathPosition: n)` → nokta yolun üstünde; yol kıvrıldıkça yanlara kayar
- `atFraction(chunkFraction: ...)` → host `alongEdgeInsetFraction`
  (`saga_infinite_map_view.dart:90`) hesaba katarak kesir matematiğini kendi çözmeli

Tüketicinin kodunda bu formülün türetimini anlatan 8 satırlık yorum var.
Bu bilgi paketin içinde olmalı.

### Uygulama
```dart
/// A full-width band aligned with one level, spanning the chunk laterally.
///
/// Unlike [besidePath], this ignores the path's lateral wander: the band sits
/// at the level's position along the scroll axis and stretches edge to edge.
/// The along-axis fraction accounts for the view's `alongEdgeInsetFraction`,
/// so the band lines up with the node even when the chunk has end insets.
const SagaMapDecoration.atLevel({
  required int levelId,
  required this.builder,
  this.height = 48,
  this.offset = Offset.zero,
  this.z = 0,
});

/// Along-axis fraction of the chunk box for one level, edge insets included.
double chunkFractionForLevel({
  required int levelIndexInChunk,
  required int levelsPerChunk,
  double edgeInsetFraction = 0,
});
```

### Kabul kriterleri
- [ ] `atLevel` bandı, aynı `levelId`'nin düğümüyle piksel hizasında
      (`alongEdgeInsetFraction` 0 ve 0.1'de golden testi)
- [ ] Bant, chunk'ın tam genişliğini kaplar; yolun kıvrımından etkilenmez
- [ ] `chunkFractionForLevel` public ve ihraç edilmiş (formülü elle çözmek isteyen için)
- [ ] `atLevel`, `besidePath` ve `atFraction` ile karşılıklı dışlayıcı

---

## T-11 — Host tanımlı biyom kimlikleri 🟡

**Madde:** A10 (+ OCP-3) · **Dalga:** B (2.0.0) · **Efor:** M
**ADR:** [0007](../adrs/0007-host-tanimli-biyomlar.md)
**Beceri:** `applying-ocp`, `applying-abstract-factory-pattern`

### Kök neden (rapor düzeltmesi)
Rapor "yalnızca 4 renk" diyor; `saga_biome_theme.dart:4-37` aslında 12 alan
taşıyor (gradyan, ilerleme öncesi/sonrası yol renkleri, stroke ve gölge tokenları).
Asıl kısıt:

1. `kSagaBiomeIds` (`biome_ids.dart:13`) `const` global — **liste genişletilemiyor**.
   `SagaMapConfig.biomeSpan` yalnız döngü uzunluğunu ayarlıyor.
2. Temada **asset kancası yok** — biyom başına yol taşı, düğüm sprite'ı veya
   zemin dokusu tanımlanamıyor.

Tüketicide 10 diyar var; bu yüzden biyom sistemi yerine paralel bir `SagaRealm`
yapısı kurulmuş. Yani paketin biyom alt sistemi fiilen kullanılmıyor.

### Uygulama
```dart
class SagaMapConfig {
  /// Biome ids the generator cycles through, in order.
  ///
  /// Defaults to the built-in three. A host with its own realms passes its own
  /// list; [biomeSpan] then sets how many levels each one covers.
  final List<String> biomeIds;   // default: kSagaBiomeIds
}

class SagaBiomeTheme {
  /// Optional art keys for this biome, resolved by the host.
  ///
  /// The package never loads these; it hands them back to the node and path
  /// builders so one biome can look different from another beyond its colours.
  final Map<String, String> assets;   // default: const {}
  final Color? ambientTint;
}
```

### Kabul kriterleri
- [ ] `biomeIds: ['a','b',...10 tane]` → generator 10'lu döngü üretir
- [ ] Boş liste → `ArgumentError` (döngüde sıfıra bölme yok)
- [ ] `biomeIds` verilmediğinde üretilen `biomeId` dizisi 1.x ile birebir aynı
- [ ] `kSagaBiomeIds` `@Deprecated` değil — varsayılan olarak kalır
- [ ] `SagaBiomeThemeResolver` bilinmeyen id için düşürme (fallback) davranışını dokümante eder

---

## T-12 — Düşüş oranı hesaplama API'si 🟡

**Madde:** A2 · **Dalga:** A (1.1.0) · **Efor:** S
**Beceri:** `applying-srp`

### Kök neden
`kMvpLootTable` ağırlıkları 60/60/28/12 (toplam 160) → yaygın %75, nadir %17,5,
efsanevi %7,5. Paket bu yüzdeleri hesaplayan bir API sunmuyor; host oranları elle
yeniden hesaplıyor. **Türkiye ve AB'de ilerlemeye bağlı bir kasanın düşüş oranlarını
açıklaması bekleniyor** — UI'da gösterilen oran ile kuranın kullandığı ağırlık
ayrı yerlerde hesaplanırsa kaçınılmaz olarak ayrışır.

### Uygulama
```dart
extension LootTableOdds on List<LootTableEntry> {
  /// This entry's chance of dropping, as a `0..1` fraction of the table.
  double probabilityOf(LootTableEntry entry);

  /// Drop chance per rarity, summing to 1. The numbers a disclosure screen
  /// should show — derived from the same weights the roll uses, so the two
  /// cannot drift apart.
  Map<InventoryRarity, double> rarityOdds();
}
```

### Kabul kriterleri
- [ ] `kMvpLootTable.rarityOdds()` → `{common: 0.75, rare: 0.175, legendary: 0.075}`
- [ ] Oranların toplamı `1.0` (kayan nokta toleransı `1e-9`)
- [ ] Boş tablo → `ArgumentError`; sıfır toplam ağırlık → `ArgumentError`
- [ ] Sıfır ağırlıklı girdi oranı `0.0` döner, çekilişte hiç çıkmaz (tutarlılık testi)
- [ ] README'de "düşüş oranlarını göstermek" örneği

---

## T-13 — Pity (acıma) kuralı 🟡

**Madde:** A3 · **Dalga:** C (2.1.0) · **Efor:** M
**Beceri:** `applying-strategy-pattern`

### Kök neden
`rollBossReward` saf ağırlıklı çekiliş. %75 yaygın oranıyla 10 kasa üst üste yaygın
gelme olasılığı ≈ %5,6; uzun bir haritada bu bazı oyuncular için kesinlik. O oyuncu
kasanın bozuk olduğu sonucuna varır.

### Uygulama
```dart
/// Guarantees a floor after a run of bad luck. The counter lives with the host
/// (it is save data); the rule lives here so every consumer applies the same one.
class SagaPityRule {
  const SagaPityRule({
    this.threshold = 10,
    this.guaranteedRarity = InventoryRarity.rare,
  });
}

InventoryItem rollBossReward({
  ...,
  int pityCounter = 0,
  SagaPityRule? pityRule,
});
```

### Kabul kriterleri
- [ ] `pityCounter >= threshold` → sonuç en az `guaranteedRarity`
- [ ] Garanti devredeyken çekiliş yalnız uygun nadirlikteki girdiler arasında yapılır
- [ ] Determinizm korunur: aynı `(levelId, seed, table, pityCounter)` → aynı eşya
- [ ] Uygun nadirlikte girdi yoksa normal çekilişe düşer (istisna fırlatmaz)
- [ ] `pityRule` `null` iken davranış 2.0.0 ile birebir

---

## T-14 — Ödül kalıcılığı sözleşmesi 🟡

**Madde:** A4 (+ DIP-3) · **Dalga:** C (2.1.0), doküman kısmı A (1.1.0) · **Efor:** S
**Beceri:** `applying-dip`

### Kök neden
`CompleteLevelResult.reward` döner ama `InventoryRepository`'ye **yazılmaz**;
paket bir repository soyutlaması tanımlayıp onu hiç kullanmıyor. Ayrıca host
`rollBossReward`'ı doğrudan çağırırsa aynı eşya sonsuz kez üretilebilir
(`Random(levelId ^ globalSeed)` deterministik) — `execute` bunu `firstClear` ile
sınırlıyor (satır 94), çıplak fonksiyon sınırlamıyor.

### Uygulama
**1.1.0 (doküman):**
```dart
/// The rolled reward, or null.
///
/// Returned, **not persisted**. The caller must write it to its
/// [InventoryRepository]; the use case does not touch storage. Dropping this
/// value silently loses the item.
final InventoryItem? reward;
```
`rollBossReward` doküman yorumuna: *"Deterministic and unguarded: calling it twice
for the same level mints the same item twice. `CompleteLevelUseCase.execute`
applies the first-clear guard; a direct caller must apply its own."*

**2.1.0 (opsiyonel enjeksiyon):** `CompleteLevelUseCase({InventoryRepository? inventory})`
— verildiğinde `execute` ödülü yazar ve `CompleteLevelResult.rewardPersisted: true` döner.

### Kabul kriterleri
- [ ] `CompleteLevelResult.reward` doküman yorumu kalıcılık sorumluluğunu adlandırır
- [ ] `rollBossReward` doküman yorumu korumasızlığı adlandırır
- [ ] README "Rewards" bölümünde bir kalıcılaştırma örneği
- [ ] (2.1.0) `inventory` verildiğinde tek çağrıda yazılır, verilmediğinde davranış aynı

---

## T-15 — `onChunkEnter` / `onLevelReached` 🟡

**Madde:** B3-5 (+ B3-4) · **Dalga:** A (1.1.0) · **Efor:** M
**Beceri:** `applying-observer-pattern`

### Kök neden
Harita kaydırılırken hangi chunk'ın görünür olduğu host'a bildirilmiyor
(`saga_infinite_map_view.dart:60-152` — böyle bir callback yok). Analitik,
müzik geçişi, "yeni diyar" kutlaması için gerekli. Ayrıca "bu bölüme ilk kez
girildi" sinyali olmadığı için host hangi chunk'ın görüldüğünü kendi saklıyor.

### Uygulama
```dart
class SagaInfiniteMapView {
  /// Fires when a chunk becomes the dominant one on screen. Not called again
  /// while it stays dominant, so it is safe to trigger music or a celebration.
  final void Function(SagaChunkContext chunk)? onChunkEnter;

  /// Fires when the character's path position crosses a level.
  final void Function(LevelData level)? onLevelReached;
}
```

### Kabul kriterleri
- [ ] Aynı chunk için ardışık tekrar tetiklenme yok (kenarda gidip gelirken bile)
- [ ] Hızlı kaydırmada aradaki chunk'lar **atlanmaz** ya da bu davranış dokümante edilir
- [ ] `dispose` sonrası callback çağrılmaz (Lapsed Listener — beceri dosyasının uyarısı)
- [ ] "İlk giriş" kararı host'a ait; paket sadece olayı yayar (doküman yorumunda net)

### Beceri notu
`applying-observer-pattern` "memory leak if Observers aren't unregistered"
uyarısını taşıyor. Burada abonelik yaşam döngüsü widget'a bağlı olduğu için
`dispose` testi zorunlu kabul kriteri.

---

## T-16 — Yıldız ekonomisi 🟡

**Madde:** B3-1 · **Dalga:** C (2.1.0) · **Efor:** M
**Beceri:** `applying-srp`

### Kök neden
Yıldız toplanıyor (`LevelProgress.stars`) ama harcanacak yer yok → yıldız ölü para.
Harcama muhasebesi her tüketicide yeniden yazılıyor.

### Uygulama
`SagaProgress` üzerine:
```dart
/// Stars the player has spent. Never exceeds [totalStars].
final int spentStars;

/// Sum of stars across every completed level.
int get totalStars;

/// [totalStars] minus [spentStars]; what the player can still spend.
int get availableStars;
```

### Kabul kriterleri
- [ ] `spentStars > totalStars` durumu `fromJson`'da `totalStars`'a kırpılır (bozuk kayıt koruması)
- [ ] `spentStars` negatifse `0`'a kırpılır
- [ ] `availableStars` asla negatif değil
- [ ] T-03 (`extra`) ile geçici çözüm üreten host için geçiş notu

---

## T-17 — Yıldız toplamı yardımcıları 🟢

**Madde:** B3-6 · **Dalga:** A (1.1.0) · **Efor:** S
**Beceri:** `applying-facade-pattern`

### Kök neden
"Toplam yıldız", "şu chunk'ta kaç yıldız", "şu chunk tamamen 3 yıldız mı" hesapları
yok; her tüketici `levels.values` üzerinde aynı döngüyü yazıyor.

### Uygulama
```dart
extension SagaProgressStars on SagaProgress {
  int get totalStars;
  int starsInRange(int startLevelId, int count);
  bool isRangePerfect(int startLevelId, int count, {int perLevel = kMaxLevelStars});
  int completedCountInRange(int startLevelId, int count);
}
```

### Kabul kriterleri
- [ ] Kayıtsız seviye `0` yıldız sayılır, hata vermez
- [ ] `count == 0` → `0` / `true` (boş aralık sözleşmesi dokümante)
- [ ] Chunk bazlı kullanım README'de bir satırda gösterilir

---

## T-18 — Tekrar oynama modları 🟡

**Madde:** B3-3 · **Dalga:** C (2.1.0) · **Efor:** L
**Beceri:** `applying-ocp`

### Kök neden
Aynı seviye, farklı kural (zor / ayna / hafıza). Mod başına ayrı yıldız skoru
`LevelProgress` içinde tutulamıyor, host'a kalıyor.

### Uygulama — iki aşamalı
1. **1.1.0 (T-03 ile bedava):** `LevelProgress.extra` mod skorlarını taşır.
   Host bugün çözer, paket sözleşmesi kırılmaz.
2. **2.1.0:** Birinci sınıf destek —
   `Map<String, int> starsByMode` + `CompleteLevelUseCase.execute({String? modeId})`.

### Kabul kriterleri (2.1.0)
- [ ] `modeId` `null` → varsayılan mod, davranış 2.0.0 ile aynı
- [ ] Mod skorları birbirini ezmez; `stars` varsayılan modun skoru kalır
- [ ] Kilit açma yalnız varsayılan moddan tetiklenir (aksi hâlde zor mod ilerlemeyi çiftler)

---

## T-19 — Dokümantasyon ve sürümleme politikası 🔴

**Madde:** B4-1, B4-2, B4-3, A4 · **Dalga:** A (1.1.0) · **Efor:** M
**ADR:** [0001](../adrs/0001-leveldata-id-sozlesmesi.md) · **Beceri:** `writing-adrs`

### Kök neden
`README.md`'nin 458 satırında `LevelData.id`'nin tabanı **hiç geçmiyor**.
Bir tüketicinin ilk yapacağı hata bu — nitekim yapılmış.

### Yapılacaklar
- [ ] `LevelData` sınıf dokümanına sözleşme cümlesi:
      *"Ids are zero-based: the first level a player sees has `id == 0`. Display
      `id + 1` wherever a player reads the number."*
- [ ] `README.md`'ye "Level ids" başlığı; `id + 1` kuralı ve `isBossLevel` örneği
- [ ] `README.md`'ye "Versioning" başlığı: semver politikası, kırıcı değişiklik tanımı
      (kayıtlı oyuncu verisinin anlamını değiştiren her şey kırıcıdır)
- [ ] `CompleteLevelResult.reward` kalıcılık notu (T-14)
- [ ] `rollBossReward` korumasızlık notu (T-14)
- [ ] `isBossLevel`'ın neden public olduğu: `CompleteLevelUseCase.bossRule`'un
      varsayılanı olduğu için (T-04 sonrası doğru gerekçe)
- [ ] `SagaProgressRepository` doküman yorumu: `loadGlobalSeed` yan etki yasağı

---

## T-20 — `flutter_svg` opsiyonelleştirme 🟢

**Madde:** B4-5 · **Dalga:** B (2.0.0) · **Efor:** M
**ADR:** [0008](../adrs/0008-flutter-svg-bagimliligini-ayirmak.md)
**Beceri:** `preventing-vendor-lock-in`

### Kök neden
`pubspec.yaml`'daki `flutter_svg: ^2.2.4` yalnız `SagaMapBackgroundConfig.svgAsset`
için. SVG kullanmayan tüketici (webp kullanan) bu ağırlığı bedelsiz taşıyor.

### Seçenekler

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. `WidgetBuilder` kancası** (`svgAsset` yerine `backgroundBuilder`) | Bağımlılık tamamen düşer; host istediği formatı verir | `svgAsset` kullanan tüketici kod değiştirir |
| B. Ayrı `saga_map_svg` paketi | Kolaylık korunur | İki paket, iki sürüm, iki CHANGELOG |
| C. Bırak | Sıfır iş | Her tüketici ~200 KB taşır |

**Öneri: A.** Paket zaten "host provides its own assets" felsefesinde
(`pubspec.yaml` açıklaması) — SVG'yi özel-durum kılmak bu felsefeyle çelişiyor.

### Kabul kriterleri
- [ ] `flutter_svg` `dependencies`'ten kalkar
- [ ] `svgAsset` `@Deprecated`, 2.0.0'da çalışmaya devam eder mi / kalkar mı → ADR-0008
- [ ] README'de `flutter_svg` ile aynı görünümü elde etme örneği (host tarafında 5 satır)
- [ ] `example/` webp arka planla çalışmaya devam eder

---

## T-21 — `onLevelLongPress` kısayolu 🟢

**Madde:** Rapor sonu notu · **Dalga:** A (1.1.0) · **Efor:** S

### Kök neden
`SagaInfiniteMapView` `onLevelTap` kısayolunu sunuyor (`saga_infinite_map_view.dart:80`,
`map_chunk_widget.dart:363-370`) ama `onLevelLongPress` yok. Tüketici bu asimetri
yüzünden paketin zaten desteklediği `onNodeLongPress`'i gözden kaçırıp düğümü
kendi `GestureDetector`'ıyla sarmalamış.

### Uygulama
`onLevelTap`'in `_resolveHandler` deseni (`map_chunk_widget.dart:363-370`)
`onLevelLongPress` için birebir tekrarlanır.

### Kabul kriterleri
- [ ] `onLevelLongPress` verildiğinde ve `interactionHandler.onNodeLongPress` boşken devreye girer
- [ ] İkisi birden verilirse `interactionHandler` kazanır (tap ile aynı öncelik kuralı)
- [ ] T-07'nin `canLongPress` kapısından geçer

---

## T-22 — Örnek uygulamayı düzelt 🟢

**Madde:** B4-4 · **Dalga:** B (2.0.0, T-01 ile birlikte) · **Efor:** S

### Kök neden
`example/lib/main.dart:349` — `isBossLevel(level.id)`. Örnek H1'i çoğaltıyor;
boss örnekte de yanlış düğümde çıkıyor.

### Kabul kriterleri
- [ ] T-01 sonrası örnekte boss 15./30./45. düğümde görünür
- [ ] Örnek, düğüm üzerine yazılan sayı için `level.id + 1` kullanır (T-02 ile tutarlı)
- [ ] Örnekte `CompleteLevelUseCase`'in özel `bossRule` ile kullanımı gösterilir (T-04 vitrini)

---

## Bağımlılık grafiği

```
T-19 (doküman) ─── bağımsız, ilk yapılabilir
T-02 ─── T-19 ile aynı sözleşmeye dayanır
T-03 ──┬─ T-16 (yıldız ekonomisi geçici çözümü)
       └─ T-18 (mod skorları geçici çözümü)
T-05 ─── T-10 (ikisi de dekorasyon API'si)
       └─ T-15 (SagaChunkContext'i paylaşır)
T-07 ─── T-08 ─── T-21   (üçü aynı satırlara dokunuyor → tek PR)
T-01 ─── T-22
T-04 ──┬─ T-12 (loot tablosu API'si)
       ├─ T-13 (pity)
       └─ T-14 (kalıcılık)
T-06 ─── bağımsız ama en büyük; T-01 ile aynı sürümde
T-09 ─── bağımsız (sürüm kararı bekliyor)
T-11 ─── bağımsız
T-20 ─── bağımsız
```

**Önerilen PR grupları:**
1. `docs: level id contract + versioning policy` (T-19, T-02)
2. `feat: extensible progress` (T-03, T-17)
3. `feat: long-press parity` (T-07, T-08, T-21)
4. `feat: chunk context for builders` (T-05, T-10, T-15)
5. `feat: loot odds` (T-12)
6. `feat!: injectable rewards` (T-04, T-13, T-14)
7. `fix!: boss level off-by-one` (T-01, T-22)
8. `feat!: gates block progression` (T-06)
9. `feat!: host-defined biomes` (T-11)
10. `chore!: drop flutter_svg` (T-20), `feat!: saveGlobalSeed` (T-09)

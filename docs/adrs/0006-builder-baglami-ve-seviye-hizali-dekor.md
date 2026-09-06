# 6. Builder'lara chunk bağlamı vermek ve seviyeye hizalı dekor eklemek

Date: 2026-09-05

## Status

Accepted — implemented in 1.1.0.

## Context

### Sorun 1 — Builder'lar kör

Dekorasyon ve bölüm başlığı builder'ları yalnız `chunkIndex` alıyor:

```dart
// saga_map_decoration.dart:87-90
typedef SagaMapDecorationBuilder = List<SagaMapDecoration> Function(
  BuildContext context,
  int chunkIndex,
);

// saga_infinite_map_view.dart:143
final Widget? Function(BuildContext context, int chunkIndex)? episodeHeaderBuilder;
```

Host, bir chunk'a dekor koyarken o chunk'taki `LevelData`'ları göremiyor:
**`biomeId` ve `difficulty` builder'a ulaşmıyor.** `controller.chunkLevels(index)`
var ama iki sorunu var: (a) builder içinden controller'a uzanmak gerekiyor,
(b) tahliye edilmiş chunk için boş liste dönüyor
(`saga_infinite_map_controller.dart:86`) — yani zamanlamaya bağlı bir sözleşme.

Pratik sonucu: paket her seviye için `biomeId` üretiyor
(`saga_map_level_generator.dart:51`), üretimdeki tüketici bunu **hiç okumadı** —
chunk index'ten kendi diyar eşlemesini yaptı. Paketin ürettiği alan ölü.

### Sorun 2 — Seviyeye hizalı bant elle hesaplanıyor

Belirli bir seviyenin hizasında, tam genişlikte bir levha (kilometre taşı, boss
afişi) koymanın yolu yok:

- `besidePath(pathPosition: n)` → nokta yolun üstünde; yol kıvrıldıkça yanlara
  kayıyor, tam genişlik bant için kullanılamıyor.
- `atFraction(chunkFraction: ...)` → host, `alongEdgeInsetFraction`'ı
  (`saga_infinite_map_view.dart:90`) hesaba katarak kesir matematiğini kendi çözmeli.

Tüketicinin kodunda bu formülün türetimini anlatan 8 satırlık bir yorum var.
O bilgi paketin içinde olmalı: geometriyi paket biliyor, host tahmin ediyor.

## Decision

### Karar 1 — `SagaChunkContext`

Builder'lara tek bir bağlam nesnesi verilir:

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

`dominantBiomeId`, paketin zaten sahip olduğu `getDominantBiomeId`
(`saga_dominant_biome.dart`) ile hesaplanır — bağlama koymak maliyetsiz ve
`biomeId` alanını ilk kez kullanılabilir kılıyor.

Bağlam **itilir, çekilmez**: builder controller'a uzanmaz, chunk yaşam döngüsünde
bir kez kurulup verilir. Böylece tahliye edilmiş chunk'ın boş liste döndürmesi
sorunu da kapanır.

Ayrı ayrı `levels`, `progress`, `biome` parametreleri yerine tek nesne seçildi:
gelecekte alan eklemek imza kırmayacak.

### Karar 2 — `SagaMapDecoration.atLevel`

```dart
/// A full-width band aligned with one level, spanning the chunk laterally.
///
/// Unlike [besidePath], this ignores the path's lateral wander: the band sits at
/// the level's position along the scroll axis and stretches edge to edge. The
/// along-axis fraction accounts for the view's `alongEdgeInsetFraction`, so the
/// band lines up with the node even when the chunk has end insets.
const SagaMapDecoration.atLevel({ required int levelId, ... });

/// Along-axis fraction of the chunk box for one level, edge insets included.
double chunkFractionForLevel({
  required int levelIndexInChunk,
  required int levelsPerChunk,
  double edgeInsetFraction = 0,
});
```

Yardımcı fonksiyon da ihraç edilir: kendi yerleşimini kuran host formülü
yeniden türetmek zorunda kalmasın.

### Geçiş

Eski `SagaMapDecorationBuilder` imzası `@Deprecated` işaretlenir ama **kaldırılmaz**:

```dart
@Deprecated('Use decorationBuilder with SagaChunkContext. Removed in 3.0.0.')
```

`SagaInfiniteMapView` her iki parametreyi de kabul eder; ikisi birden verilirse
`assert` uyarır ve yenisi kazanır. Böylece bu karar **1.1.0'da, kırıcı olmadan**
çıkabilir.

## Consequences

### Olumlu
- `biomeId` ve `difficulty` ilk kez host'a ulaşır; paketin ürettiği alanlar ölü
  olmaktan çıkar.
- Builder'ın controller'a uzanma ihtiyacı kalkar — zamanlamaya bağlı boş liste
  sorunu kapanır.
- Kilometre taşı / boss afişi yerleştirmek bir satır olur; geometri bilgisi
  paketin içinde kalır.
- `SagaChunkContext`, T-15'in (`onChunkEnter`) taşıyacağı yükün aynısı — iki
  özellik tek tipi paylaşır.
- Kırıcı değil: 1.1.0'a sığar.

### Olumsuz
- **Performans dikkati:** `SagaChunkContext` her `build`'de değil, chunk yaşam
  döngüsünde bir kez kurulmalı; aksi hâlde kaydırma sırasında çöp üretimi artar.
  Bu, T-05'in kabul kriterlerinden biri.
- İki paralel builder imzası bir majör sürüm boyunca yaşar; `SagaInfiniteMapView`
  ve `MapChunkWidget` ikisini de taşımak zorunda.
- `SagaMapDecoration` üçüncü bir constructor kazanır; üçünün karşılıklı dışlayıcı
  olduğu invariant'ı elle korunmalı (`assert`).
- `chunkFractionForLevel` public API yüzeyini büyütür; formül değişirse kırıcı olur.
  Kabul edildi: bilgiyi saklamak, host'un yanlış türetmesine yol açıyor.

## Related

- Görev: T-05, T-10, T-15
- `docs/reports/05-c4-genisleme-noktalari.md` (dikişler karnesi)

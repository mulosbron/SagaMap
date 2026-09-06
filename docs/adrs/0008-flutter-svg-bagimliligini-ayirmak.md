# 8. flutter_svg bağımlılığını düşürmek

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`pubspec.yaml` `flutter_svg: ^2.2.4` taşıyor ve kendi yorumu tek kullanım yerini
adlandırıyor:

```yaml
# flutter_svg: SagaMapBackgroundConfig.svgAsset.
flutter_svg: ^2.2.4
```

Yani tüm paket, tek bir isteğe bağlı özellik için bir çizim kütüphanesi ve onun
geçişli bağımlılıklarını (`vector_graphics`, `xml`, `path_parsing`) zorunlu
kılıyor. SVG kullanmayan tüketici — üretimdeki tüketici webp kullanıyor — bu
ağırlığı bedelsiz taşıyor.

Bu, paketin kendi beyan ettiği felsefeyle de çelişiyor. `pubspec.yaml`'ın altında:

> This package is consumed from host apps.
> Host applications provide and register their own background assets.

Paket "varlıkları host sağlar" diyor ama tek bir formatı özel durum yapıp onun
yükleyicisini kendi bağımlılığına alıyor.

## Decision

Seçenekler:

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. `WidgetBuilder` kancası** | Bağımlılık tamamen düşer; host istediği formatı verir; felsefeyle tutarlı | `svgAsset` kullanan tüketici kod değiştirir |
| B. Ayrı `saga_map_svg` paketi | Kolaylık korunur | İki paket, iki sürüm, iki CHANGELOG — tek geliştirici için orantısız |
| C. Bırak | Sıfır iş | Her tüketici kullanmadığı bir kütüphaneyi taşır |

**A seçilir.** `SagaMapBackgroundConfig.svgAsset` yerine:

```dart
class SagaMapBackgroundConfig {
  /// Builds the background layer. The package positions and scrolls whatever
  /// this returns; it loads nothing itself.
  ///
  /// For an SVG, add flutter_svg to your own app and return SvgPicture.asset.
  /// README "Custom backgrounds" shows the five-line equivalent.
  final WidgetBuilder? backgroundBuilder;
}
```

`flutter_svg` `dependencies`'ten kaldırılır. README'ye `flutter_svg` ile aynı
görünümü elde etmenin beş satırlık karşılığı yazılır — özellik kaybolmaz, sahibi
değişir.

B seçeneği, `preventing-vendor-lock-in` becerisinin ruhuna uygun görünse de
burada yanlış ölçek: bir yükleyici sarmalayıcı için ayrı bir paket yayımlamak,
kazandırdığı kolaylıktan fazla bakım maliyeti yazar. Doğru soyutlama, paketin
formatı hiç bilmemesi.

`svgAsset`'in 2.0.0'da **kaldırılması mı deprecated edilmesi mi** gerektiği:
bağımlılık düşürülürken alan çalışamaz hale geldiği için deprecated tutmanın
anlamı yok — 2.0.0'da kaldırılır ve CHANGELOG'da karşılığı gösterilir.

## Consequences

### Olumlu
- Paketin bağımlılık grafiği `equatable` + `fast_noise` ile sınırlanır; ikisi de
  gerçekten çekirdek (`ProceduralBiomeGenerator`).
- İndirme boyutu ve derleme süresi, SVG kullanmayan her tüketici için düşer.
- Paket, arka plan formatı hakkında hiçbir varsayım yapmaz: webp, png, gradyan,
  `CustomPaint`, animasyon — hepsi eşit derecede desteklenir.
- `pubspec.yaml`'daki "host provides its own assets" beyanı gerçek olur.

### Olumsuz
- **Kırıcı:** `svgAsset` kullanan tüketici `flutter_svg`'yi kendi `pubspec`'ine
  ekleyip beş satır yazar. README'de birebir kopyalanabilir bir örnek şart.
- "Pili dahil" kolaylık kaybolur; SVG ile başlamak isteyen yeni tüketici için
  bir adım daha.
- `flutter_svg` sürüm uyumluluğunu paketin test etmesi biterse, host'ların
  yaşadığı uyumsuzluklar paketin görüş alanının dışına çıkar. Kabul edildi:
  bu zaten host'un bağımlılığı olmalı.

## Related

- Görev: T-20
- Beceri: `preventing-vendor-lock-in`

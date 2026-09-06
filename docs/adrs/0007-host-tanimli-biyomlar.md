# 7. Biyom kimliklerini host'a açmak ve temaya asset kancası eklemek

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

Biyom sistemi iki noktada kapalı:

**1. Liste `const` global.** `kSagaBiomeIds` üç kimlikle sabit
(`biome_ids.dart:13`) ve jeneratör onu doğrudan okuyor
(`saga_map_level_generator.dart:51`):

```dart
biomeId: kSagaBiomeIds[biomeIndex % kSagaBiomeIds.length],
```

`SagaMapConfig.biomeSpan` döngünün **uzunluğunu** ayarlanabilir kılıyor ama
**içeriğini** değil. Dört biyom isteyen host için genişleme yolu yok.

**2. Temada asset kancası yok.** Tüketici raporu `SagaBiomeTheme`'in "yalnızca
4 renk taşıdığını" söylüyor; bu doğru değil — sınıf 12 alan taşıyor
(`saga_biome_theme.dart:4-37`): gradyan, yürünen/yürünecek yol renkleri, stroke
genişlikleri, gölge tokenları. Renk paleti yeterince zengin.

Asıl eksik, biyom başına **görsel varlık** tanımlanamaması: yol taşı dokusu,
düğüm sprite'ı, zemin dokusu. Tema yalnızca boyayabiliyor, giydiremiyor.

Bu ikisinin bileşik sonucu: üretimdeki tüketicide 10 diyar var, biyom sistemi
yerine paralel bir `SagaRealm` yapısı kuruldu. Paketin biyom alt sistemi
kullanılmıyor.

## Decision

### Karar 1 — Biyom listesi konfigürasyona taşınır

```dart
class SagaMapConfig {
  /// Biome ids the generator cycles through, in order.
  ///
  /// Defaults to the built-in three. A host with its own realms passes its own
  /// list; [biomeSpan] then sets how many levels each one covers.
  final List<String> biomeIds;   // default: kSagaBiomeIds
}
```

- `kSagaBiomeIds` **kaldırılmaz, deprecated edilmez** — varsayılan değer olarak kalır.
- Boş liste `ArgumentError` fırlatır (döngüde sıfıra bölme yok).
- `biomeIds` verilmediğinde üretilen `biomeId` dizisi 1.x ile birebir aynı.

### Karar 2 — Temaya opak asset haritası

```dart
class SagaBiomeTheme {
  /// Optional art keys for this biome, resolved by the host.
  ///
  /// The package never loads these; it hands them back to the node and path
  /// builders so one biome can look different from another beyond its colours.
  final Map<String, String> assets;   // default: const {}

  /// A wash applied over the chunk, for biome mood beyond the palette.
  final Color? ambientTint;
}
```

`assets` opak seçildi — `String? pathStoneAsset`, `String? nodeSprite` gibi
adlandırılmış alanlar yerine. Gerekçe: paket bu varlıkları **yüklemiyor**, sadece
taşıyor. Adlandırılmış alanlar, paketin bilmediği bir varlık taksonomisini
dondurur; opak harita host'un kendi anahtarlarını kullanmasına izin verir ve
paketin `flutter_svg`'de düştüğü tuzağı (format hakkında varsayım, bkz. ADR-0008)
tekrarlamaz.

### Kırıcılık

`biomeIds` bir **semantik** kırıcılıktır: host özel liste verdiğinde `biomeId`
değerleri değişir ve `SagaBiomeThemeResolver` bilinmeyen kimliklerle karşılaşır.
Çözücünün düşürme (fallback) davranışı dokümante edilmeli. 2.0.0'a alınır.

## Consequences

### Olumlu
- 10 diyarlı bir host, paralel bir `SagaRealm` yapısı kurmadan paketin biyom
  sistemini kullanabilir; ADR-0006 ile birlikte `biomeId` ilk kez baştan sona
  işlevsel hale gelir (üretilir → builder'a ulaşır → temaya çözülür).
- `assets` haritası, paket bir varlık yükleyicisi hâline gelmeden biyom başına
  sanat yönetimini mümkün kılar.
- `OCP-3` kapanır: yeni biyom eklemek paketi değiştirmeyi gerektirmez.

### Olumsuz
- **Tip güvenliği yok:** biyom kimlikleri `String` kalır; yanlış yazılan bir
  kimlik derleme zamanında yakalanmaz, çalışma zamanında tema çözümünde düşer.
  `enum` kullanmak host tanımlı listeyi imkânsız kılacağı için reddedildi.
- `SagaBiomeThemeResolver`'ın bilinmeyen kimlik davranışı artık bir sözleşme
  maddesi; belirsiz bırakılırsa host'un haritası sessizce yanlış renklenir.
- `assets` opak olduğu için IDE tamamlama yardımı yok; anahtarlar README'de
  örneklenmelidir.
- `biomeSpan` ile `biomeIds.length` arasındaki etkileşim (kaç seviyede bir biyom
  değişir, döngü kaç seviyede kapanır) yeni bir kavram yükü getirir; dokümanda
  bir örnek tabloyla gösterilmeli.

## Related

- Görev: T-11
- ADR-0006 (builder bağlamı) — `biomeId`'nin host'a ulaşmasını sağlar
- Bulgu: OCP-3 (`docs/reports/01-solid-uyumluluk-denetimi.md`)

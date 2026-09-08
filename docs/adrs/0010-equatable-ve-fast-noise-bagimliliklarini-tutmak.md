# 10. `equatable` ve `fast_noise` bağımlılıklarını tutmak

Date: 2026-09-07

## Status

Accepted — 2.0.0.

## Context

ADR-0008 `flutter_svg`'yi tek bir isteğe bağlı özellik için taşınan zorunlu bir
bağımlılık olduğu gerekçesiyle düşürdü. Aynı muhakeme daha küçük ölçekte iki
bağımlılık için daha geçerli:

```yaml
# equatable + fast_noise: ProceduralBiomeGenerator.
equatable: ^2.0.5
fast_noise: ^2.0.0
```

Her ikisi de `lib/` içinde **tek** dosyada kullanılıyor:
`core/domain/terrain/biome_noise_generator.dart` (175 satır). Prosedürel arazi
üretmeyen bir tüketici — yani host'un kendi biyom haritasını verdiği her
kurulum, ki ADR-0007'den sonra desteklenen yol budur — ikisini de bedelsiz
taşıyor.

Bu bir kusur değil; yazıya dökülmemiş bir denge. ADR-0008 ile kıyaslandığında
tutarsız görünmemesi için gerekçenin açık olması gerekiyor.

## Decision

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. İkisini de tut** | Prosedürel arazi kutudan çıktığı gibi çalışır; iki küçük, saf Dart paketi | Kullanmayan tüketici iki bağımlılık taşır |
| B. `equatable`'ı elle yazılmış `==`/`hashCode` ile değiştir | Bir bağımlılık eksilir | Üç sınıfta elle eşitlik; paketin geri kalanı zaten elle yazıyor (13 `operator ==`) |
| C. `fast_noise`'ı ayrı bir `saga_map_terrain` paketine taşı | Çekirdek tamamen saf kalır | İki paket, iki sürüm, iki CHANGELOG — ADR-0008'de reddedilen aynı gerekçe |
| D. Gürültü üretimini paket içinde yeniden yaz | Bağımlılık sıfır | Perlin/simplex'i doğru ve hızlı yazmak, kazanılan ağırlığa değmeyecek bir bakım yüküdür |

**A seçildi**, ancak ADR-0008 ile arasındaki fark yazıya geçiriliyor:

`flutter_svg` bir **çizim kütüphanesi** ve geçişli bağımlılıklarıyla
(`vector_graphics`, `xml`, `path_parsing`) geliyordu; üstelik paketin kendi
felsefesiyle — "varlıkları host sağlar" — doğrudan çelişiyordu. `equatable` ve
`fast_noise` ise saf Dart, geçişli bağımlılıkları yok denecek kadar az, ve
sağladıkları şey host'un sağlayabileceği bir varlık değil, paketin kendi
alan mantığı.

B seçeneği 2.1.0'da ayrıca değerlendirilebilir: paketin geri kalanı eşitliği
elle yazıyor, dolayısıyla `equatable` zaten tek başına duruyor. Bugün
düşürülmemesinin nedeni kazancın (bir saf Dart paketi) maliyeti (üç sınıfta
elle eşitlik ve onun testleri) karşılamaması.

## Consequences

### Olumlu

- Prosedürel arazi ek kurulum olmadan çalışır.
- ADR-0008 ile aradaki fark artık açık: sorulan soru "bağımlılık var mı" değil,
  "bu bağımlılık host'un sağlayabileceği bir şeyi mi taşıyor".

### Olumsuz

- Kendi biyom haritasını veren tüketici iki paketi bedelsiz taşır.
- `equatable`, paketin geri kalanının izlemediği bir kalıbı tek bir dosyada
  sürdürüyor; bu tutarsızlık kalıyor (2.1.0'da yeniden bakılacak).

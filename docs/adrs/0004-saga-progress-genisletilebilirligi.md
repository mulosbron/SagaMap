# 4. SagaProgress genişletilebilirliği: opak `extra` alanı

Date: 2026-09-05

## Status

Accepted — `extra` implemented in 1.1.0; `saveGlobalSeed` in 2.0.0.

## Context

`SagaProgress` yalnız iki alan taşıyor (`saga_progress.dart:4-11`):
`currentMaxUnlockedLevelId` ve `Map<int, LevelProgress> levels`.
`LevelProgress` ise `levelId / state / stars / lastPlayedAt`.

Üretimdeki tüketicinin haritaya bağlı olan ama pakette karşılığı olmayan verileri:

- harcanan yıldız sayısı (yıldız ekonomisi)
- açılmış sandık id'leri
- ilk kez girilen diyarlar
- alternatif oyun modlarına ait ayrı yıldız skorları
- hatasız seri sayacı

Hiçbiri `SagaProgress`'e sığmadığı için tüketici, **aynı kutuda paketin JSON'una
paralel anahtarlar tutan ikinci bir repository** yazdı. Tek depoda iki kayıt
katmanı; senkron kalmaları artık host'un sorumluluğu ve hiçbir şey bunu
denetlemiyor.

Bu, `applying-ocp` becerisinin tarif ettiği durumun tam tersi: model uzatma için
kapalı, host'un tek çıkışı paketin dışından dolaşmak.

## Decision

`SagaProgress` ve `LevelProgress` birer opak `extra` alanı kazanır:

```dart
/// Host-owned data the package stores but never interprets.
///
/// Round-tripped through [toJson]/[fromJson] verbatim, so a host can keep spent
/// stars, opened chests or per-mode scores next to progression without running a
/// second persistence layer alongside this one. The package reads nothing from
/// it and will never claim a key.
final Map<String, dynamic> extra;
```

Kurallar:

- Varsayılan `const {}`; mevcut constructor çağrıları değişmeden derlenir.
- `toJson()`, `extra` boşken anahtarı **hiç yazmaz** — eski kayıtlarla bit uyumu korunur.
- `fromJson()`, anahtar yoksa veya `Map` değilse `{}` üretir (bozuk kayıt dayanıklılığı,
  `saga_progress.dart:59-66`'daki mevcut titizlikle aynı çizgide).
- Paket `extra` içindeki hiçbir anahtarı okumaz ve gelecekte de talep etmez.

### Reddedilen seçenekler

**`SagaProgressRepository<T extends SagaProgress>` (generic repository).**
Tip güvenli, ama tüm imzalar generic olur ve mevcut her tüketici kırılır.
Kazanılan tip güvenliği, kaybedilen uyumluluğu karşılamıyor.

**Ayrı bir uzantı kayıt defteri (registry).** Temiz ama iki serileştirme yolu,
iki dosya ve bir kayıt yaşam döngüsü demek. `balancing-architectural-tradeoffs`
becerisinin aşırı mühendislik uyarısı: tek bilinen tüketicili bir paket için
fazla ağır.

### `saveGlobalSeed` (ISP-1) hakkında

`SagaProgressRepository` asimetrik (`saga_progress_repository.dart:4-13`):
`loadGlobalSeed()` var, yazma karşılığı yok. Tüketici tohumu `loadGlobalSeed()`
**içinde yan etki olarak** yazmak zorunda kaldı; bir "load" fonksiyonunun disk
yazması, sözleşmenin istemciyi kirli bir uygulamaya zorlamasıdır. "Haritayı
yeniden üret / tohumu değiştir" özelliği de sözleşme düzeyinde imkânsız.

`Future<void> saveGlobalSeed(int seed)` eklenir. **2.0.0'da**, 1.1.0'da değil:
`abstract interface class`'a metot eklemek, arayüzü uygulayan host için
kaynak-kırıcıdır ve kırıcılığı gizlemenin tek yolu (`UnimplementedError` fırlatan
varsayılan gövde) `verifying-solid-compliance` kontrol listesinin LSP maddesinin
tam olarak yasakladığı şeydir. Bir sürüm gecikme, kalıcı bir LSP ihlalinden ucuzdur.

`loadGlobalSeed`'in doküman yorumuna yan etki yasağı yazılır.

## Consequences

### Olumlu
- Host, ikinci bir kayıt katmanı yazmadan kendi verisini ilerlemenin yanında tutar;
  iki katmanın ayrışma riski ortadan kalkar.
- 2.1.0'a bırakılan üç özellik (yıldız ekonomisi T-16, mod skorları T-18, sandık
  takibi) host tarafında **bugün** çözülebilir hale gelir — paket gecikirse maliyet
  geçici bir çözüm, kalıcı bir engel değil.
- `LevelProgress.extra`, mod bazlı yıldız skorları için doğal yer.
- Serileştirme tek yerde kalır; paketin JSON'u tek doğruluk kaynağı olur.

### Olumsuz
- **Tip güvenliği yok.** `extra['spentStars']` bir `int` mi `String` mi, derleyici
  bilmez. Host kendi okuma/yazma sarmalayıcılarını yazmalı.
- **Anahtar çakışması riski.** Paket ileride `extra`'ya bir anahtar koymaya karar
  verirse host verisini ezer. Bunu önlemek için karar metni "paket hiçbir anahtarı
  talep etmez" taahhüdünü içeriyor; bu taahhüt bağlayıcıdır.
- **Şişme riski.** `extra` sınırsız büyüyebilir; büyük bir `extra` her kaydetmede
  serileştirilir. Doküman yorumunda "küçük tutun" uyarısı gerekir.
- İleride birinci sınıf alanlar eklendiğinde (T-16 `spentStars`), `extra`'da
  geçici çözüm üretmiş host için bir göç notu gerekir.
- `saveGlobalSeed` 2.0.0'a alındığı için tüketici, tohum yazma geçici çözümünü
  bir sürüm daha taşır.

## Related

- Görev: T-03, T-09, T-16, T-18
- Bulgu: ISP-1 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)
- `.old/docs/reports/04-surumleme-ve-gecis-plani.md` §5 (T-09 sürüm kararı)

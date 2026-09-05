# 03 — Kalite Nitelikleri (NFR) Raporu

**Beceri:** `software-architecture-skills/skills/optimizing-quality-attributes/SKILL.md`

Beceri dosyası dört nitelik ailesi tanımlıyor: Performans, Ölçeklenebilirlik,
Güvenlik, Sürdürülebilirlik & Test Edilebilirlik. `saga_map` bir sunucu sistemi
değil bir **istemci kütüphanesi** olduğu için bu aileler şöyle çevriliyor:

| Beceri ailesi | Bu paketteki karşılığı |
|---|---|
| Performans | Kare hızı, chunk üretim maliyeti, bellek tahliyesi |
| Ölçeklenebilirlik | Sonsuz harita: derin chunk'ın maliyeti sığ chunk'la aynı mı |
| Güvenlik | Kurcalanmış kayıt dayanıklılığı, ödül bütünlüğü, mevzuat uyumu |
| Sürdürülebilirlik & Test Edilebilirlik | Enjeksiyon dikişleri, mock edilebilirlik, sözleşme netliği |
| *(ek)* Erişilebilirlik | Ekran okuyucu, klavye, dokunma hedefi |

---

## 1. Performans 🟢

**Durum: iyi. Aksiyon gerekmiyor.**

Kanıtlar:
- Seviye üretimi `(globalSeed, levelId)`'den **sabit maliyetli**
  (`saga_map_level_generator.dart:8-13`): onbininci chunk, birinci chunk kadar
  ucuz. Önceki uygulama rastgele diziyi sıfırdan oynatıyormuş; düzeltilmiş.
- Konum **hesaplanıyor, biriktirilmiyor** (`saga_map_level_generator.dart:42-44`):
  yinelemeli toplamanın kayan nokta kayması engellenmiş.
- Chunk tahliyesi var (`test/saga_chunk_retention_test.dart`).

**Tek dikkat noktası:** T-05 (`SagaChunkContext`) builder'a `levels` ve `progress`
taşıyacak. Bu nesne **her frame'de değil, chunk başına bir kez** kurulmalı; aksi
hâlde kaydırma sırasında çöp üretimi artar.

→ T-05 kabul kriterine ek: *"`SagaChunkContext` chunk yaşam döngüsünde bir kez
kurulur; `build` içinde yeniden yaratılmaz."*

---

## 2. Ölçeklenebilirlik 🟢

**Durum: iyi.**

Beceri dosyasının "Stateless Services" ilkesinin kütüphane karşılığı: chunk
oluşturmanın hiçbir gizli durumu okumaması. `SagaMapLevelGenerator` bunu
sağlıyor — saf fonksiyon, `startLevelId`'den bağımsız maliyet.

**Kırılgan nokta:** `chunkLevels(chunkIndex)` tahliye edilmiş chunk için boş
dönüyor (`saga_infinite_map_controller.dart:86`). Bu bir performans tercihi ama
**API sızıntısı** yaratıyor: builder içinden veri okumaya çalışan host bazen boş
liste alıyor, bazen almıyor — zamanlamaya bağlı bir sözleşme.

→ T-05 bunu kapatıyor: bağlam builder'a **itiliyor**, host çekmiyor.

---

## 3. Güvenlik ve uyumluluk 🟡

Beceri dosyasının "Defense in Depth" ilkesi burada üç başlığa düşüyor.

### 3.1 Kurcalanmış kayıt dayanıklılığı 🟢
Paket bunu ciddiye almış, örnek niteliğinde:
- `saga_progress.dart:59-66` — negatif kilit işaretçisi `0`'a kırpılıyor,
  gerekçesi yorumda yazılı
- `complete_level_usecase.dart:44-48` — `assert` yerine `clamp`, çünkü assert
  release derlemesinde silinir
- `complete_level_usecase.dart:50-55` — `enforceUnlockOrder` ile keyfi seviye atlama kapatılıyor

**Aksiyon:** T-03 (`extra`) ve T-16 (`spentStars`) aynı titizlikte olmalı —
kabul kriterlerine bozuk-kayıt koruması yazıldı.

### 3.2 Ödül bütünlüğü 🟡
`complete_level_usecase.dart:91-97` ilk geçiş korumasını doğru kuruyor ve
gerekçesini yorumda anlatıyor ("a host promoting inventory to a server would see
as an integrity hole"). Ancak:

- `rollBossReward` **çıplak çağrıldığında korumasız** — deterministik olduğu için
  aynı eşyayı sonsuz kez üretir (DIP-3)
- Ödül **kalıcılaştırılmıyor**; sessizce kaybolabilir

→ **T-14.** En azından sözleşme yazılı olmalı.

### 3.3 Mevzuat: düşüş oranı açıklaması 🔴
Türkiye ve AB'de ilerlemeye bağlı bir kasanın düşüş oranlarını açıklaması
bekleniyor. Bugün oran UI'da elle yazılıyor, çekiliş ağırlıklardan yapılıyor —
**iki sayı ayrı yerlerde tutuluyor.** Tablo değişirse ekrandaki yüzde sessizce
yanlışa döner ve bu bir uyumluluk sorunudur, bir görüntü hatası değil.

Mimari ilke: *tek doğruluk kaynağı.* Gösterilen oran, çekilişin kullandığı
ağırlıklardan **türetilmelidir**.

→ **T-12** (`rarityOdds`). Bu, listedeki "konfor" maddesi değil; uyumluluk maddesi.

---

## 4. Sürdürülebilirlik ve test edilebilirlik 🔴

Beceri dosyasının üç taktiği ve paketin durumu:

| Taktik | Durum | Bulgu |
|---|---|---|
| **Yüksek uyum, düşük bağlaşım** | 🟡 | Katmanlar temiz; ama `core/domain/usecases` → `core/domain/loot_table` bağı sabit |
| **Bağımlılık tersine çevirme** | 🔴 | `LevelGenerator`, `SagaMapRenderer`, `SagaProgressRepository` soyut; **ödül, boss, biyom kuralları değil** |
| **Mocklama** | 🔴 | Ödül kolu taklit edilemiyor |

### Test edilebilirlik açığı — somut
`test/complete_level_usecase_test.dart` bugün ödül davranışını ancak gerçek
`kMvpLootTable` üzerinden sınayabiliyor. Sonuç: **tabloya bir eşya eklemek,
tablo hakkında hiçbir iddiası olmayan geçiş testlerini kırar.** Test, sınamak
istemediği bir şeye bağlı.

T-04 sonrası:
```dart
const useCase = CompleteLevelUseCase(
  bossRule: (id) => id == 3,
  lootTable: [_onlyItem],
);
```
Geçiş mantığı, ödül tablosundan bağımsız sınanır. Bu, T-04'ün **asıl** kazancı —
host esnekliği ikincil.

### Ölçüm önerisi
- [ ] T-04 sonrası: `complete_level_usecase_test.dart` içinde `kMvpLootTable`
      referansı **kalmamalı**
- [ ] Yeni testler enjekte edilmiş sahte tablo/kural kullanmalı

---

## 5. Erişilebilirlik 🔴

Beceri dosyasında ayrı bir aile yok; bu paket için **birinci sınıf bir NFR**,
çünkü paketin ürettiği şey doğrudan son kullanıcı arayüzü.

### Mevcut durum — güçlü taraflar 🟢
- Dokunma hedefi tabanı: `kSagaMinTouchTarget = 44.0`, görselden bağımsız
  (`widget_renderer_adapter.dart:33`, `:183-186`)
- Tab sırası **seviye sırasına** göre, boyama sırasına göre değil
  (`widget_renderer_adapter.dart:119-124`) — gerekçesi yorumda; RTL ve yatay
  haritada doğru davranışın nedeni açıklanmış
- Kilitli düğüm Tab'da atlanıyor (`:134-135`)
- Düğüm görseli `excludeSemantics: true` ile dekoratif işaretli (`:132`)
- Etiket dışarıdan verilebilir → yerelleştirilebilir (`:23-26`)

Bu, çoğu Flutter paketinin ulaşamadığı bir seviye.

### Açıklar

| # | Açık | Etki | Görev |
|---|---|---|---|
| A11Y-1 🔴 | İlk düğüm "Level 0" duyuruluyor (`:37`) | Görme engelli ve gören kullanıcı aynı seviyeden bahsedemiyor | T-02 |
| A11Y-2 🟡 | Uzun basma yalnız dokunmatikte (`:125-145`) | Klavye ve ekran okuyucu kullanıcısı ikincil eylemin **tamamından** yoksun | T-08 |
| A11Y-3 🟡 | Uzun basma politikadan geçmiyor (`:180-182`) | Kilitli düğüm dokunmatikte "canlı" davranıyor, klavyede ölü — tutarsız | T-07 |

### A11Y-2'nin ağırlığı
CHANGELOG "Keyboard navigation: Tab visits nodes in level order, Enter and Space
activate" diye ilan ediyor. Bu doğru ama **eksik bir ilan**: ikincil eylem
klavyeden erişilemiyor. Tüketicide uzun basmaya bağlı olan şey "seviyeyi farklı
modlarda tekrar oynama menüsü" — yani bir kolaylık değil, oyunun bir bölümü.
Klavye kullanıcısı o bölüme hiç giremiyor.

WCAG 2.1 **2.1.1 Keyboard (Level A)**: tüm işlevsellik klavyeden erişilebilir
olmalı. Bu bir A-seviyesi ihlal.

→ **T-08, A dalgasında.**

---

## 6. NFR karnesi

| Nitelik | 1.0.0 | 1.1.0 sonrası (hedef) | 2.0.0 sonrası (hedef) |
|---|---|---|---|
| Performans | 🟢 | 🟢 | 🟢 |
| Ölçeklenebilirlik | 🟢 | 🟢 | 🟢 |
| Kayıt dayanıklılığı | 🟢 | 🟢 | 🟢 |
| Ödül bütünlüğü | 🟡 | 🟡 (doküman) | 🟢 (T-14 enjeksiyon) |
| Mevzuat uyumu | 🔴 | 🟢 (T-12) | 🟢 |
| Test edilebilirlik | 🔴 | 🟡 | 🟢 (T-04) |
| Genişletilebilirlik | 🔴 | 🟡 (T-03, T-05) | 🟢 (T-04, T-06, T-11) |
| Erişilebilirlik | 🔴 | 🟢 (T-02, T-07, T-08) | 🟢 |

**Okuma:** 1.1.0 erişilebilirlik ve uyumluluğu kapatıyor — yani **kullanıcıya
ve mevzuata dönük** her şey kırıcı olmayan bir sürümde çözülüyor. 2.0.0 ise
mimari genişletilebilirliği açıyor. Bu ayrım kasıtlı: tüketicinin kırıcı sürümü
beklemek zorunda kaldığı tek şey, kendi kodunu değiştirmeyi zaten gerektiren şeyler.

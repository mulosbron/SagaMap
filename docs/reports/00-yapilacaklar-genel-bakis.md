# saga_map — Yapılacaklar Genel Bakış

**Kaynak:** `saga_map_rapor.md` (SudokuLens tüketici raporu, 2026-09-05)
**Yöntem:** Rapordaki her madde paket kaynağına karşı doğrulandı; ardından
`software-architecture-skills/` beceri setiyle mimari çerçeveye oturtuldu.
**Kapsam:** `saga_map` 1.0.0 → 2.0.0 hazırlığı.

---

## 1. Doğrulama sonucu

Raporun 20 maddesinin tamamı kaynakta doğrulandı. Üç noktada rapor
**eksik kalıyor** (durum rapordakinden daha ağır), bir noktada **fazla iddialı**:

| Madde | Durum | Not |
|---|---|---|
| H1 `isBossLevel` | ✅ Doğrulandı | `loot_table.dart:45` — `levelId > 0 && levelId % 15 == 0` |
| H2 `Level 0` | ✅ Doğrulandı | `widget_renderer_adapter.dart:37` |
| H3 long-press koruması | ✅ Doğrulandı | `widget_renderer_adapter.dart:180-182` |
| H4 klavye/SR long-press | ✅ Doğrulandı | `widget_renderer_adapter.dart:125-145` — `Semantics` yalnız `onTap` |
| A1 loot enjekte edilemiyor | ✅ Doğrulandı | `complete_level_usecase.dart:95,102` doğrudan top-level çağrı |
| A5 `SagaProgress` kapalı | ✅ Doğrulandı | `saga_progress.dart:4-11` yalnız iki alan |
| A6 `saveGlobalSeed` yok | ✅ Doğrulandı | `saga_progress_repository.dart:4-13` |
| A7 builder bağlamsız | ✅ Doğrulandı | `saga_map_decoration.dart:87-90`, `saga_infinite_map_view.dart:143` |
| **A9 kapı** | ⚠️ **Rapordan daha ağır** | `clampTravelThroughGates` paket içinde **hiç çağrılmıyor** (`grep`: yalnız test + doc). Kapı, karakterin yürüyüşünü bile paket adına kesmiyor; host'un elle çağırması gereken saf bir yardımcı fonksiyon. |
| **A10 biyom teması** | ⚠️ **Rapor fazla iddialı** | Tema 4 değil 12 alan taşıyor (`backgroundGradient`, `upcomingPath*`, stroke/shadow tokenları dahil — `saga_biome_theme.dart:4-37`). Asıl sorun renk sayısı değil, **asset/sprite kancasının olmaması** ve `kSagaBiomeIds`'in `const` global olması (`biome_ids.dart:13`). |
| **A4 ödül kalıcılığı** | ⚠️ **Rapordan daha ağır** | `InventoryRepository` pakette var ama `CompleteLevelUseCase` ona **hiç dokunmuyor**; ödül döner, yazılmaz. Sözleşme sessiz. |
| B4-4 örnek H1'i çoğaltıyor | ✅ Doğrulandı | `example/lib/main.dart:349` |

---

## 2. Kök neden: üç mimari kusur, yirmi belirti

Rapordaki maddeler bağımsız hatalar değil; üç mimari kusurun türevleri:

### Kusur 1 — Kayıp sözleşme: `LevelData.id` tabanı yazılı değil
Paket iki yerde iki cevap veriyor (`generator: 0 tabanlı`, `isBossLevel: 1 tabanlı`).
Türevleri: **H1, H2, B4-2, B4-4.**
→ ADR-0001, ADR-0002.

### Kusur 2 — DIP ihlali: alan kuralları `const` global ve top-level fonksiyon
`kMvpLootTable`, `isBossLevel`, `kSagaBiomeIds` derleme zamanı sabitleri; yüksek
seviye iş mantığı (`CompleteLevelUseCase`) bunlara **doğrudan** bağlı. Soyutlama yok,
dolayısıyla enjeksiyon da yok.
Türevleri: **A1, A2, A3, A9, A10, B3-1, B3-2, B3-3.**
→ ADR-0003, ADR-0005, ADR-0007. Beceri: `applying-dip`, `applying-ocp`, `applying-strategy-pattern`.

### Kusur 3 — Kapalı veri modeli: uzatma noktası olmayan `final` alanlar
`SagaProgress`, `LevelProgress` ve builder imzaları host verisine yer bırakmıyor;
host paralel bir kayıt katmanı yazmak zorunda kalıyor.
Türevleri: **A5, A6, A7, A8, B3-4, B3-5, B3-6.**
→ ADR-0004, ADR-0006. Beceri: `applying-isp`, `applying-observer-pattern`.

> **Sonuç:** 20 maddenin tamamı, 3 ADR ailesi ve ~8 dosyalık bir değişiklikle kapanıyor.
> Tek tek yamamak yerine kusur bazında ilerlenmeli.

---

## 3. Rapor haritası

| Rapor | İçerik |
|---|---|
| [01 — SOLID Uyumluluk Denetimi](01-solid-uyumluluk-denetimi.md) | `verifying-solid-compliance` kontrol listesinin dosya/satır referanslı uygulaması |
| [02 — Görev Kartları](02-gorev-kartlari.md) | T-01…T-22: kabul kriteri, test, kırıcılık, efor |
| [03 — Kalite Nitelikleri (NFR)](03-kalite-nitelikleri.md) | `optimizing-quality-attributes`: erişilebilirlik, sürdürülebilirlik, test edilebilirlik, uyumluluk |
| [04 — Sürümleme ve Geçiş Planı](04-surumleme-ve-gecis-plani.md) | `balancing-architectural-tradeoffs`: 1.1.0 / 2.0.0 dalgaları, deprecation yolu |
| [05 — C4 Bileşen Görünümü](05-c4-genisleme-noktalari.md) | `documenting-with-c4`: paket ↔ host sınırı ve eksik genişleme dikişleri |
| [ADR-0001…0008](../adrs/) | Karar kayıtları (`writing-adrs`) |
| [**Görev panosu**](../tasks/000_index_tasks.md) | **526 mikro görev**, 23 dosya, dalga ve bağımlılık sırasıyla |

---

## 4. Yürütme sırası (dalgalar)

Rapordaki öncelik listesi doğru ama **kırıcılığa göre gruplanmamış**. Aşağıdaki
sıra aynı önceliği korurken tek bir kırıcı sürüm çıkarmayı sağlıyor:

### Dalga A — 1.1.0 (kırıcı değil, hemen)
Yalnızca ekleme yapan, mevcut tüketiciyi bozmayan işler.

| Sıra | Görev | Madde |
|---|---|---|
| 1 | T-02 `Level ${id + 1}` etiketi | H2 |
| 2 | T-19 Dokümantasyon: id tabanı, semver, kalıcılık | B4-1/2, A4 |
| 3 | T-03 `SagaProgress.extra` / `LevelProgress.extra` | A5 |
| 4 | T-09 `saveGlobalSeed` | A6 |
| 5 | T-05 Builder'lara `levels` + `progress` (yeni tipli builder, eskisi deprecated) | A7 |
| 6 | T-07 + T-08 `canLongPress`, `Semantics.onLongPress`, context-menu intent | H3, H4 |
| 7 | T-21 `onLevelLongPress` kısayolu | Rapor sonu notu |
| 8 | T-10 `SagaMapDecoration.atLevel` | A8 |
| 9 | T-12 `rarityOdds` | A2 |
| 10 | T-15 `onChunkEnter` / `onLevelReached` | B3-5 |
| 11 | T-17 Yıldız toplamı yardımcıları | B3-6 |

### Dalga B — 2.0.0 (kırıcı)
Kayıtlı oyuncu geçmişini veya derleme uyumluluğunu bozan işler.

| Sıra | Görev | Madde | Neden kırıcı |
|---|---|---|---|
| 1 | T-01 `isBossLevel` → `% 15 == 14` | H1 | Kayıtlı ödül geçmişi kayar |
| 2 | T-04 Enjekte edilebilir loot (`bossRule`, `lootTable`) | A1 | `rollBossReward` imzası değişir |
| 3 | T-06 Kapı ↔ ilerleme bağı (`isReachable`, `canUnlock`) | A9 | Varsayılan kilit açma davranışı genişler |
| 4 | T-11 `SagaMapConfig.biomeIds` | A10 | `kSagaBiomeIds` sabitinden kopuş |
| 5 | T-22 Örneği düzelt | B4-4 | T-01 ile birlikte |
| 6 | T-20 `flutter_svg` opsiyonelleştirme | B4-5 | Bağımlılık kaldırma |

### Dalga C — 2.1.0+ (yeni özellik)
| Görev | Madde |
|---|---|
| T-13 Pity kuralı | A3 |
| T-16 Yıldız ekonomisi (`spentStars`) | B3-1 |
| T-18 Tekrar oynama modları | B3-3 |
| T-14 Ödül kalıcılığı sözleşmesi (isteğe bağlı `InventoryRepository` enjeksiyonu) | A4 |

---

## 5. İzlenebilirlik matrisi

| Madde | Görev | ADR | Beceri (skill) |
|---|---|---|---|
| H1 | T-01 | ADR-0002 | `writing-adrs`, `balancing-architectural-tradeoffs` |
| H2 | T-02 | ADR-0001 | `optimizing-quality-attributes` |
| H3 | T-07 | — | `applying-ocp` |
| H4 | T-08 | — | `optimizing-quality-attributes` |
| A1 | T-04 | ADR-0003 | `applying-dip`, `applying-strategy-pattern` |
| A2 | T-12 | ADR-0003 | `applying-srp` |
| A3 | T-13 | ADR-0003 | `applying-strategy-pattern` |
| A4 | T-14 | ADR-0003 | `applying-dip` |
| A5 | T-03 | ADR-0004 | `applying-ocp`, `applying-memento-pattern` |
| A6 | T-09 | ADR-0004 | `applying-isp` |
| A7 | T-05 | ADR-0006 | `applying-builder-pattern` |
| A8 | T-10 | ADR-0006 | `applying-facade-pattern` |
| A9 | T-06 | ADR-0005 | `applying-dip`, `applying-state-pattern` |
| A10 | T-11 | ADR-0007 | `applying-ocp`, `applying-abstract-factory-pattern` |
| B3-1 | T-16 | ADR-0004 | `applying-srp` |
| B3-3 | T-18 | ADR-0004 | `applying-ocp` |
| B3-5 | T-15 | — | `applying-observer-pattern` |
| B3-6 | T-17 | — | `applying-facade-pattern` |
| B4-1/2/3 | T-19 | ADR-0001 | `writing-adrs` |
| B4-4 | T-22 | ADR-0002 | — |
| B4-5 | T-20 | ADR-0008 | `preventing-vendor-lock-in` |

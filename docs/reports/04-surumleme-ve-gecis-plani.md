# 04 — Sürümleme ve Geçiş Planı

**Beceri:** `software-architecture-skills/skills/balancing-architectural-tradeoffs/SKILL.md`
**Kapsam:** 1.0.0 → 1.1.0 → 2.0.0 → 2.1.0

---

## 1. Temel gerilim

Beceri dosyası mimariyi **çatışan iş hedefleri arasında denge** olarak tanımlıyor.
Burada çatışan iki hedef:

| Hedef | Talep | Baskı |
|---|---|---|
| **Tüketiciyi kırmama** | 1.0.0 "First stable release" olarak ilan edildi; `saga_map: ^1.0.0` üretimde kullanılıyor | Kırıcı değişiklik güven maliyeti |
| **Sessiz yanlışı düzeltme** | H1 boss'u en kolay tahtaya düşürüyor; oyuncu bunu bir hata olarak görmez, oyunun tasarımı sanır | Düzeltmeyi geciktirmek borcu büyütür |

Beceri dosyasının "Startup vs Growth" modeli buraya şöyle uyuyor: `saga_map`
tek bilinen tüketicisi olan, yeni yayımlanmış bir kütüphane — yani hâlâ
**startup fazında**. Bu fazda doğru tercih hızlı ve temiz düzeltme; kırıcı
değişikliğin maliyeti bugün en düşük olduğu noktada.

**Karar: 2.0.0'ı ertelemeyin. Ama tek seferde çıkarın.**

Yirmi maddeyi üç kırıcı sürüme yaymak, tek bir 2.0.0'dan çok daha pahalıdır —
her kırıcı sürüm tüketiciye ayrı bir geçiş bütçesi yazdırır.

---

## 2. Kırıcı değişiklik tanımı (bu paket için)

README'ye yazılması gereken politika. Bir değişiklik şu üç durumda kırıcıdır:

1. **Derleme kırar** — imza, tip veya ihraç değişir.
2. **Kayıtlı veriyi kırar** — mevcut `SagaProgress` JSON'u farklı yorumlanır.
3. **Kayıtlı verinin *anlamını* kırar** — JSON aynı okunur ama artık başka bir
   şey ifade eder.

Üçüncüsü, H1'in düştüğü kategoridir ve genelde gözden kaçar: `isBossLevel`
düzeltmesi hiçbir alanı değiştirmez, hiçbir imzayı bozmaz — ama oyuncunun
"boss geçtim" geçmişi bir seviye kayar. **Semver açısından bu majör bir değişikliktir.**

> Bu tanım README'ye girmelidir (T-19). Yazılı olmayan politika, politika değildir.

---

## 3. Sürüm planı

### 1.1.0 — "Contract & Access" (kırıcı değil)

**Tema:** Sözleşmeyi yaz, erişilebilirliği kapat, genişleme dikişlerini aç.

| Görev | Tür |
|---|---|
| T-19 Dokümantasyon (id tabanı, semver, kalıcılık) | docs |
| T-02 `Level ${id + 1}` | fix |
| T-03 `SagaProgress.extra` / `LevelProgress.extra` | feat |
| T-05 Builder'lara `SagaChunkContext` (eski imza deprecated) | feat |
| T-07 `canLongPress` | feat |
| T-08 Klavye/SR uzun basma | feat |
| T-21 `onLevelLongPress` | feat |
| T-10 `SagaMapDecoration.atLevel` | feat |
| T-12 `rarityOdds` | feat |
| T-15 `onChunkEnter` / `onLevelReached` | feat |
| T-17 Yıldız yardımcıları | feat |

**Neden bu sürümde:** Hepsi **ekleme**. Mevcut tüketici `pubspec.yaml`'a
dokunmadan `^1.0.0` kısıtıyla bu sürümü alır ve hiçbir şeyi değişmez.
Erişilebilirlik ve mevzuat uyumu (T-02, T-08, T-12) burada kapanıyor — kullanıcıya
dönük borç, kırıcı sürümü beklemiyor.

**1.1.0'a girmeyen ama girmesi tartışılan:** T-09 (`saveGlobalSeed`).
`abstract interface class`'a metot eklemek, arayüzü uygulayan host için
kaynak-kırıcıdır. Bkz. §5.

---

### 2.0.0 — "Injectable Rules" (kırıcı)

**Tema:** İş kurallarını sabitlerden çıkar, host'a ver.

| Görev | Kırıcılık türü |
|---|---|
| T-01 `isBossLevel` → `% 15 == 14` | Kayıtlı verinin anlamı (tip 3) |
| T-04 Enjekte edilebilir loot (`bossRule`, `lootTable`) | İmza (tip 1) |
| T-06 Kapı ↔ ilerleme bağı | Semantik + imza (tip 1, 3) |
| T-11 `SagaMapConfig.biomeIds` | Semantik (tip 3 — `biomeId` değerleri değişebilir) |
| T-09 `saveGlobalSeed` | Arayüz (tip 1) |
| T-20 `flutter_svg` düşürme | Bağımlılık (tip 1) |
| T-22 Örnek düzeltmesi | — |
| T-05 eski builder imzasının kaldırılması | **Hayır — 3.0.0'a bırakılır** |

**Deprecation politikası:** 1.1.0'da `@Deprecated` işaretlenen hiçbir şey
2.0.0'da kaldırılmaz. Kaldırma 3.0.0'a bırakılır. Böylece tüketicinin geçiş
penceresi bir majör sürüm boyunca açık kalır ve 2.0.0 geçişi yalnızca *zorunlu*
değişikliklerden ibaret olur.

---

### 2.1.0 — "Economy" (kırıcı değil)

| Görev |
|---|
| T-13 Pity kuralı |
| T-14 Ödül kalıcılığı enjeksiyonu |
| T-16 Yıldız ekonomisi (`spentStars`) |
| T-18 Mod bazlı skorlar (birinci sınıf) |

Bu dördü de 1.1.0'da `extra` üzerinden host tarafında çözülebiliyor. Yani
tüketici bunları beklemek zorunda değil — paket geç kalırsa maliyeti host'a
geçici bir çözüm, kalıcı bir engel değil. Önceliklendirmede en sona koyulmasının
gerekçesi bu.

---

## 4. 2.0.0 geçiş rehberi (CHANGELOG taslağı)

```markdown
## 2.0.0

### BREAKING — boss levels moved by one

`isBossLevel` now returns true for `id % 15 == 14`, not `id % 15 == 0`.

Level ids are zero-based, so "every fifteenth level" — the 15th, 30th and 45th
a player sees — is id 14, 29, 44. The old formula landed on the 16th, 31st and
46th node and, because difficulty is `1 + id % 5`, handed the boss the easiest
board in the cycle.

**Migration.** Players with saved progress may have already been rewarded at
ids 15/30/45 and were never rewarded at 14/29/44. The package does not migrate
this for you: rewards live in your `InventoryRepository`, which the package
never writes to. If your game grants items on boss clears, decide whether to
issue a one-time grant for the shifted ids.

To keep the old behaviour exactly:

    CompleteLevelUseCase(bossRule: (id) => id > 0 && id % 15 == 0)

### BREAKING — rewards are injectable

`CompleteLevelUseCase` now takes `bossRule` and `lootTable`. Both default to
the previous built-ins, so `const CompleteLevelUseCase()` still compiles and
behaves as before (apart from the boss-id fix above).

`rollBossReward` takes an optional `table`. An empty table now throws
`ArgumentError` rather than silently rolling from the built-in one.

### BREAKING — gates block progression

`SagaNodeInteractionPolicy.isReachable` and `CompleteLevelUseCase.canUnlock`
let a closed gate stop a player, not just the walking character.
`SagaInfiniteMapView` takes `gates` and applies `clampTravelThroughGates`
itself; hosts calling it by hand can drop that call.

Both hooks default to null, which keeps 1.x behaviour.

### BREAKING — biome ids come from config

`SagaMapConfig.biomeIds` replaces the fixed `kSagaBiomeIds` cycle.
`kSagaBiomeIds` remains as the default, so omitting `biomeIds` generates the
same ids as before.

### BREAKING — SagaProgressRepository gained saveGlobalSeed

Implementors must add `Future<void> saveGlobalSeed(int seed)`. If your
`loadGlobalSeed` wrote a default as a side effect, move that write here.

### BREAKING — flutter_svg is no longer a dependency

`SagaMapBackgroundConfig.svgAsset` is replaced by `backgroundBuilder`.
See README "Custom backgrounds" for a five-line equivalent.
```

---

## 5. Açık karar: T-09'un sürümü

`saveGlobalSeed`, `abstract interface class SagaProgressRepository`'ye eklenecek.
Bu, arayüzü uygulayan her host için kaynak-kırıcıdır.

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. 2.0.0'a al** | Semver dürüst; LSP korunur | Tüketici tohum yazma çözümünü bir sürüm daha taşır |
| B. 1.1.0'da varsayılan gövdeyle ekle (`UnimplementedError`) | Hemen çıkar | **LSP ihlali** — beceri dosyasının açık kırmızı bayrağı: "subclasses throwing NotImplementedException" |
| C. 1.1.0'da ikinci arayüz `SagaSeedWriter` | Kırıcı değil, ISP'ye uygun | İki arayüz, iki kayıt, host ikisini de uygulamak zorunda — karmaşıklık kazancı aşıyor |

**Öneri: A.** B, `verifying-solid-compliance` kontrol listesinin LSP maddesinin
tam olarak yasakladığı şeyi yapıyor: sözleşmeyi doldurmayan bir varsayılan.
Bir sürüm gecikme, kalıcı bir mimari kusurdan ucuzdur.

> Bu kararın sahibi paket sahibidir; ADR-0004 içinde kayda geçirilmeli.

---

## 6. Conway's Law notu

Beceri dosyası organizasyon yapısına bakmayı hatırlatıyor. Burada durum:
**tek geliştiricili bir paket, tek bilinen tüketici.**

Sonuçları:

- Uzun deprecation pencereleri, çok aşamalı geçişler ve paralel API'ler
  **gereksiz ağırlık**. Tüketici sayısı bir; koordinasyon maliyeti düşük.
- Ama bu, sözleşmeleri yazmamak için gerekçe **değil**: bu raporun kaynağı olan
  tüketici raporunun tamamı, yazılmamış sözleşmelerin faturası.
- Öneri: az sayıda, net sürüm; her kırıcı karar için bir ADR. ADR'ler bu ölçekte
  süreç değil, **geleceğe not**.

**Karşı-uyarı (`balancing-architectural-tradeoffs` kırmızı bayrağı):**
Bu paket için bir plugin mimarisi, kayıt defteri (registry) veya kural motoru
kurmayın. İhtiyaç, birkaç `typedef` ve constructor parametresiyle karşılanıyor.
"3 geliştiriciyle kanıtlanmamış bir MVP için yüksek ölçekli mimari" uyarısı
burada birebir geçerli.

---

## 7. Sürüm kontrol listesi

Her sürüm için:

- [ ] `CHANGELOG.md` — kırıcı maddeler **BREAKING** başlığıyla ve geçiş kodu ile
- [ ] `pubspec.yaml` sürümü
- [ ] `README.md` — değişen API örnekleri güncel
- [ ] `example/` derleniyor ve yeni davranışı gösteriyor
- [ ] `flutter test` tam geçiyor; golden'lar güncel
- [ ] Kırıcı sürümde: ilgili ADR'lerin `Status` alanı `Accepted`
- [ ] `dart pub publish --dry-run` temiz

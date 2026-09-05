# 01 — SOLID Uyumluluk Denetimi

**Beceri:** `software-architecture-skills/skills/verifying-solid-compliance/SKILL.md`
**Kapsam:** `lib/` (52 dosya, 5.595 satır)
**Tarih:** 2026-09-05

Beceri dosyasındaki beş kontrol, `saga_map` 1.0.0 kaynağına uygulandı. Her bulgu
dosya/satır referanslıdır ve [02 — Görev Kartları](02-gorev-kartlari.md) içindeki
bir göreve bağlanır.

---

## Özet skor

| İlke | Durum | Bulgu sayısı | Ağırlık |
|---|---|---|---|
| SRP — Tek Sorumluluk | 🟢 İyi | 1 | Düşük |
| OCP — Açık/Kapalı | 🔴 İhlal | 4 | **Kritik** |
| LSP — Liskov | 🟢 Temiz | 0 | — |
| ISP — Arayüz Ayrımı | 🟡 Kısmi | 2 | Orta |
| DIP — Bağımlılık Tersine Çevirme | 🔴 İhlal | 3 | **Kritik** |

**Genel değerlendirme:** Paketin katman ayrımı (`core/domain`, `core/data`,
`rendering`) örnek niteliğinde; `LevelGenerator`, `SagaMapRenderer`,
`SagaProgressRepository` gibi soyutlamalar zaten yerinde. Sorun mimarinin
kendisinde değil, **iş kurallarının bu soyutlamaların dışında kalmasında**:
ödül, boss ve biyom kuralları `const` global veya top-level fonksiyon olarak
kaçmış. Yani mimari doğru kurulmuş, kurallar mimarinin dışına sızmış.

---

## 1. SRP — Tek Sorumluluk

**Kontrol:** "Manager/Processor/System" adlı sınıflar, birden fazla değişme nedeni.

### Bulgu SRP-1 🟡 — `CompleteLevelUseCase.execute` üç işi birden yapıyor

`lib/src/core/domain/usecases/complete_level_usecase.dart:36-104`

Tek metot içinde:

1. Yıldız birleştirme ve ilerleme geçişi (satır 47-89)
2. Boss tespiti (satır 95)
3. Ödül çekilişi (satır 102)

Değişme nedeni sayısı: ilerleme kuralı değişirse de, ödül kuralı değişirse de
bu metot değişir. Ödül kolu enjekte edilebilir hale gelince (T-04) bu kendiliğinden
çözülür — sınıf "geçişi uygula, ödül kararını stratejiye sor" haline gelir.

→ **T-04**. Ayrı bir refactor gerekmez.

### Temiz noktalar

- 52 dosyanın hiçbiri "Manager"/"System"/"Helper" adı taşımıyor.
- `arch_tools.py check-god-classes --threshold 500` eşiğini aşan tek dosya
  `saga_infinite_map_view.dart` (657 satır); ancak bu bir `StatefulWidget` ve
  içeriği kamera/scroll/chunk yaşam döngüsü — Flutter idiyomunda kabul edilebilir.
  Yine de **T-15** (`onChunkEnter`) eklenirken bu dosyanın büyümesine dikkat edilmeli.

---

## 2. OCP — Açık/Kapalı 🔴

**Kontrol:** Yeni bir varyasyon eklemek için mevcut, test edilmiş kodu değiştirmek
gerekiyor mu?

### Bulgu OCP-1 🔴 — Boss kuralı top-level fonksiyon

`lib/src/core/domain/loot_table.dart:45`

```dart
bool isBossLevel(int levelId) => levelId > 0 && levelId % 15 == 0;
```

Boss aralığını 15'ten 10'a çekmek isteyen host, paketin kaynağını değiştirmek
zorunda. Uzatılabilir değil, **yalnızca değiştirilebilir**.

→ Beceri reçetesi: `applying-ocp` → Strategy. **T-04**.

### Bulgu OCP-2 🔴 — Loot tablosu `const` global

`lib/src/core/domain/loot_table.dart:21-42`, kullanımı `:54` ve `:57`

`rollBossReward` tabloyu parametre almıyor, `kMvpLootTable` sabitini doğrudan
okuyor. Kendi eşyalarını isteyen host için genişleme yolu yok.

→ **T-04**.

### Bulgu OCP-3 🔴 — Biyom listesi `const` global

`lib/src/core/domain/biome_ids.dart:13`, kullanımı `saga_map_level_generator.dart:51`

`SagaMapConfig.biomeSpan` döngü **uzunluğunu** ayarlanabilir kılıyor ama
döngünün **içeriği** sabit. 3 biyomdan fazlasını isteyen host, üretilen
`biomeId` alanını çöpe atıp kendi eşlemesini yazıyor — nitekim tüketici bunu yapmış.

→ **T-11**.

### Bulgu OCP-4 🟡 — Kilit açma kuralı koşulsuz

`lib/src/core/domain/usecases/complete_level_usecase.dart:69`

```dart
final unlockLevelId = levelId + 1;
```

"Boss geçilmeden sonraki blok açılmasın" gibi hiçbir kural araya giremiyor.
`enforceUnlockOrder` bayrağı yalnızca *geriye* doğru koruma sağlıyor (satır 52-55),
ileriye doğru kapı koyamıyor.

→ **T-06**.

---

## 3. LSP — Liskov Yerine Geçme 🟢

**Kontrol:** `UnimplementedError` fırlatan alt sınıf, sözleşmeyi doldurmayan override.

Bulgu yok. `lib/` içinde `UnimplementedError` / `UnsupportedError` fırlatan tek bir
override yok. `SagaMapRenderer<T>` iki uygulamasında da (`WidgetRendererAdapter`,
`PainterRendererAdapter`) sözleşme tam dolduruluyor. `LevelGenerator` tek metotlu.

---

## 4. ISP — Arayüz Ayrımı 🟡

**Kontrol:** İstemci kullanmadığı metotlara bağımlı mı? Yarısı boş bırakılan arayüz var mı?

### Bulgu ISP-1 🟡 — `SagaProgressRepository` asimetrik

`lib/src/core/data/repositories/saga_progress_repository.dart:4-13`

```dart
Future<SagaProgress> loadProgress();
Future<void>         saveProgress(SagaProgress progress);
Future<int>          loadGlobalSeed();   // saveGlobalSeed yok
```

Bu bir "fat interface" değil, tersi: **eksik arayüz**. Tohumun ilk yazılışı
sözleşme dışında kaldığı için tüketici `loadGlobalSeed()` içine yan etki koymak
zorunda kalmış. Bir `load` fonksiyonunun disk yazması, sözleşmenin istemciyi
kirli bir uygulamaya zorlamasıdır — ISP ihlalinin diğer yüzü.

ISP'nin saf okuması burada sözleşmeyi iki role ayırmayı önerir
(`SagaProgressReader` / `SagaProgressWriter`). Pragmatik seçim: simetriyi
tamamlamak — tek metot eklemek, iki arayüz doğurup tüm tüketicileri kırmaktan ucuz.

→ **T-09**.

### Bulgu ISP-2 🟡 — `SagaNodeInteractionPolicy` yalnız `canTap` biliyor

`lib/src/rendering/interaction/saga_node_interaction_policy.dart:17-27`

`SagaNodeInteractionHandler` dört olay taşıyor (`tap`, `longPress`, `hover`,
`focusChange`) ama policy yalnız birini kapıya alıyor. Sonuç
`widget_renderer_adapter.dart:180-182`'de görünüyor: `onTap` policy'den geçiyor,
`onLongPress` geçmiyor. Handler ile policy arasındaki rol eşleşmesi eksik.

→ **T-07**.

---

## 5. DIP — Bağımlılık Tersine Çevirme 🔴

**Kontrol:** Yüksek seviye modül düşük seviye somut sınıfa mı bağlı? Bağımlılıklar
constructor üzerinden soyutlama olarak mı geliyor?

### Bulgu DIP-1 🔴 — Use case, alan kurallarına doğrudan bağlı

`lib/src/core/domain/usecases/complete_level_usecase.dart:95,102`

```dart
if (!isBossLevel(levelId) || !firstClear) { ... }
reward: rollBossReward(levelId: levelId, globalSeed: globalSeed, now: now),
```

`CompleteLevelUseCase` **yüksek seviye** iş mantığı; `isBossLevel` ve
`rollBossReward` **düşük seviye** kurallar. Aralarında soyutlama yok, üstelik
`const CompleteLevelUseCase()` constructor'ı hiçbir bağımlılık kabul etmiyor
(satır 21). Dart'ta bir top-level fonksiyonu doğrudan çağırmak, beceri dosyasının
uyardığı `new SmtpEmailService()` anti-deseninin birebir karşılığıdır: derleme
zamanında sabitlenmiş, test edilemez, değiştirilemez bir bağ.

**Test edilebilirlik sonucu:** Ödül kolunu taklit etmenin (mock) yolu yok. Bugün
`test/complete_level_usecase_test.dart` ödülü ancak gerçek `kMvpLootTable`
üzerinden sınayabiliyor — tablo değişirse test kırılır, ki testin sınamak istediği
şey tablo değil geçiş mantığı.

→ **T-04**. Beceri reçetesi: `applying-dip` → Constructor Injection.

### Bulgu DIP-2 🔴 — Kapı kavramı hiçbir yere bağlı değil

`lib/src/rendering/character/saga_map_gate.dart:36`

`clampTravelThroughGates` paket içinde **hiçbir yerden çağrılmıyor**
(`grep -rn clampTravelThroughGates lib` → yalnızca kendi tanımı ve
`saga_character_controller.dart:39`'daki bir doküman yorumu). Ne karakter
denetleyicisi, ne etkileşim politikası, ne de use case kapıdan haberdar.
`SagaInfiniteMapView`'in hiçbir parametresi `gates` almıyor. Kapı, paketin
ihraç ettiği ama kendisinin hiç kullanmadığı bir yardımcı fonksiyon.

Bu, raporun A9 maddesinden daha ağır: kapı "yarım" değil, **hiç bağlanmamış**.

→ **T-06**.

### Bulgu DIP-3 🟡 — Ödül kalıcılığı sessiz sözleşme

`lib/src/core/domain/usecases/complete_level_usecase.dart:99-103` +
`lib/src/core/data/repositories/inventory_repository.dart`

Paket bir `InventoryRepository` soyutlaması **tanımlıyor** ama use case ona hiç
dokunmuyor; `CompleteLevelResult.reward` döner, yazılmaz. Soyutlama var,
enjeksiyon yok — DIP'in yarısı uygulanmış. Host bunu bilmezse ödül sessizce
kaybolur ve hiçbir yerde uyarı çıkmaz.

→ **T-14** (2.1.0'da isteğe bağlı enjeksiyon), **T-19** (1.1.0'da dokümantasyon).

---

## 6. Ek mimari koku: sözleşme çelişkisi

SOLID kontrol listesinin dışında kalan ama en pahalı bulgu:

**`LevelData.id`'nin tabanı iki farklı yerde iki farklı varsayılıyor.**

| Yer | Varsayım |
|---|---|
| `saga_map_level_generator.dart:34` (`startLevelId + offset`) | 0 tabanlı |
| `saga_map_level_generator.dart:52` (`1 + levelId % 5`) | 0 tabanlı |
| `saga_progress.dart:14-25` (`initial()` → level 0 unlocked) | 0 tabanlı |
| `loot_table.dart:45` (`id % 15 == 0`) | **1 tabanlı** |
| `widget_renderer_adapter.dart:37` (`'Level ${level.id}'`) | ham indeks |

Beş çağrı yerinin dördü 0 tabanlı; biri değil. Bu bir kod hatası değil,
**dokümante edilmemiş sözleşmenin** doğal sonucu. `README.md`'nin 458 satırında
tabandan hiç söz edilmiyor.

→ **ADR-0001**, **T-19**, **T-01**, **T-02**.

---

## 7. Yapılacaklar (bu rapordan çıkan)

| # | Bulgu | Görev | Öncelik |
|---|---|---|---|
| 1 | Sözleşme çelişkisi | T-01, T-02, T-19 | 🔴 |
| 2 | DIP-1 | T-04 | 🔴 |
| 3 | DIP-2 | T-06 | 🔴 |
| 4 | OCP-1, OCP-2 | T-04 | 🔴 |
| 5 | OCP-4 | T-06 | 🔴 |
| 6 | OCP-3 | T-11 | 🟡 |
| 7 | ISP-1 | T-09 | 🟡 |
| 8 | ISP-2 | T-07 | 🟡 |
| 9 | DIP-3 | T-14, T-19 | 🟡 |
| 10 | SRP-1 | T-04 ile kapanır | 🟢 |

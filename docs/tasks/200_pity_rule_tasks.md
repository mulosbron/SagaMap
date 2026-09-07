# 200 — Pity (acıma) kuralı

| | |
|---|---|
| **Dalga** | C — **2.1.0** |
| **Kaynak** | T-13 (A3) · ADR-0003 |
| **Kırıcı** | Hayır (`pityRule` null iken davranış 2.0.0 ile birebir) |
| **Bağımlılık** | **110** (tablo parametresi olmadan mümkün değil) |
| **Görev** | 17 |

**Gerekçe:** %75 yaygın oranıyla 10 kasa üst üste yaygın gelme olasılığı ≈ %5,6.
Uzun bir haritada bu, bazı oyuncular için kesinlik — ve o oyuncu kasanın bozuk
olduğu sonucuna varır.

---

## 200.A — Kural tipi

- [ ] **200.01** — `lib/src/core/domain/pity_rule.dart` dosyasını oluştur → *bitti:* dosya var
- [ ] **200.02** — `class SagaPityRule` · `final int threshold;` (varsayılan 10) → *bitti:* alan var
- [ ] **200.03** — `final InventoryRarity guaranteedRarity;` (varsayılan `rare`) → *bitti:* alan var
- [ ] **200.04** — `const` constructor → *bitti:* var
- [ ] **200.05** — doküman: "The counter lives with the host (it is save data); the rule lives here so every consumer applies the same one." → *bitti:* yazılı
- [ ] **200.06** — `threshold <= 0` → `ArgumentError` → *bitti:* uygulandı
- [ ] **200.07** — `lib/saga_map.dart` · ihraç et → *bitti:* `export` var

## 200.B — Çekilişe bağlama

- [ ] **200.08** — `rollBossReward` · `int pityCounter = 0` parametresi → *bitti:* var
- [ ] **200.09** — `rollBossReward` · `SagaPityRule? pityRule` parametresi → *bitti:* var
- [ ] **200.10** — `pityCounter >= threshold` iken çekiliş yalnız `guaranteedRarity` ve üstü girdiler arasında yapılıyor → *bitti:* uygulandı
- [ ] **200.11** — Uygun nadirlikte girdi yoksa normal çekilişe düşüyor (istisna **yok**) → *bitti:* uygulandı ve dokümanda
- [ ] **200.12** — Determinizm korunuyor: `pityCounter` de tohuma dahil değil, filtreye dahil → *bitti:* test geçiyor
- [ ] **200.13** — `CompleteLevelUseCase` · `pityRule` alanı ve `execute`'a `pityCounter` parametresi → *bitti:* uygulandı
- [ ] **200.14** — Sayacın host tarafından `SagaProgress.extra`'da tutulabileceği README'de örneklendi → *bitti:* yazılı

## 200.C — Testler

- [ ] **200.15** — test · `pityCounter >= threshold` → sonuç en az `guaranteedRarity` → *bitti:* geçiyor
- [ ] **200.16** — test · eşiğin altında normal dağılım → *bitti:* geçiyor
- [ ] **200.17** — test · `pityRule` null iken davranış 2.0.0 ile birebir + `CHANGELOG.md` girdisi → *bitti:* geçiyor

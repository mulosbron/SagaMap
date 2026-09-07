# 230 — Tekrar oynama modları

| | |
|---|---|
| **Dalga** | C — **2.1.0** |
| **Kaynak** | T-18 (B3-3) · ADR-0004 |
| **Kırıcı** | Hayır (`modeId` null iken davranış aynı) |
| **Bağımlılık** | 020 (`LevelProgress.extra` ile geçici çözüm), 220 |
| **Görev** | 18 |

**Gerekçe:** Aynı seviye, farklı kural (zor / ayna / hafıza). Mod başına ayrı
yıldız skoru `LevelProgress` içinde tutulamıyor.

**Not:** Bu iş 1.1.0'da `LevelProgress.extra` ile host tarafında zaten
çözülebilir. Bu dosya birinci sınıf desteği tanımlıyor.

---

## 230.A — Model

- [ ] **230.01** — `level_progress.dart` · `final Map<String, int> starsByMode;` (varsayılan `const {}`) → *bitti:* alan var
- [ ] **230.02** — doküman: varsayılan modun skoru `stars` alanında kalıyor, `starsByMode` yalnız alternatif modlar → *bitti:* yazılı
- [ ] **230.03** — `toJson` / `fromJson` · boşken anahtar yazılmıyor, bozuk değerde `{}` → *bitti:* uygulandı
- [ ] **230.04** — `fromJson` · negatif veya `kMaxLevelStars` üstü değerler kırpılıyor → *bitti:* uygulandı
- [ ] **230.05** — `copyWith(starsByMode: ...)` → *bitti:* var
- [ ] **230.06** — `int starsFor(String? modeId)` yardımcısı → *bitti:* uygulandı

## 230.B — Use case

- [ ] **230.07** — `execute({String? modeId})` parametresi → *bitti:* var
- [ ] **230.08** — `modeId == null` → varsayılan mod, davranış 2.0.0 ile birebir → *bitti:* test geçiyor
- [ ] **230.09** — `modeId` verildiğinde skor `starsByMode[modeId]` içine yazılıyor, `stars` **değişmiyor** → *bitti:* uygulandı
- [ ] **230.10** — Mod skorlarında da "en iyi kalır" kuralı (`math.max`, mevcut `:65` deseni) → *bitti:* uygulandı
- [ ] **230.11** — **Kilit açma yalnız varsayılan moddan tetikleniyor** — aksi hâlde zor mod ilerlemeyi çiftler → *bitti:* uygulandı ve dokümanda
- [ ] **230.12** — Boss ödülü yalnız varsayılan modda düşüyor → *bitti:* karar uygulandı ve dokümanda
- [ ] **230.13** — `modeId` boş string veya `'default'` gibi çakışan değerler → `ArgumentError` → *bitti:* uygulandı

## 230.C — Testler

- [ ] **230.14** — test · `modeId: 'hard'` skoru `stars`'ı ezmiyor → *bitti:* geçiyor
- [ ] **230.15** — test · zor modda tamamlama ardıl seviyeyi açmıyor → *bitti:* geçiyor
- [ ] **230.16** — test · zor modda boss ödülü düşmüyor → *bitti:* geçiyor
- [ ] **230.17** — test · mod skorları round-trip'te korunuyor → *bitti:* geçiyor
- [ ] **230.18** — `README.md` "Replay modes" bölümü + `extra` geçici çözümünden göç notu + `CHANGELOG.md` → *bitti:* yazılı

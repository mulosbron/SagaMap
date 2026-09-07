# 220 — Yıldız ekonomisi

| | |
|---|---|
| **Dalga** | C — **2.1.0** |
| **Kaynak** | T-16 (B3-1) · ADR-0004 |
| **Kırıcı** | Hayır (yeni alan, varsayılan `0`) |
| **Bağımlılık** | 020 (`extra` ile geçici çözüm üretmiş host için göç notu), 021 (`totalStars`) |
| **Görev** | 19 |

**Gerekçe:** Yıldız toplanıyor (`LevelProgress.stars`) ama harcanacak yer yok —
yıldız ölü para. Harcama muhasebesi her tüketicide yeniden yazılıyor.

---

## 220.A — Model

- [ ] **220.01** — `saga_progress.dart` · `final int spentStars;` (varsayılan `0`) → *bitti:* alan var
- [ ] **220.02** — `int get availableStars => totalStars - spentStars;` → *bitti:* uygulandı
- [ ] **220.03** — `totalStars` 021'deki extension'dan sınıfa taşınıyor mu, yoksa extension mı kalıyor — karar verilip uygulandı → *bitti:* tek tanım var, çift değil
- [ ] **220.04** — doküman: `spentStars` "Never exceeds [totalStars]." → *bitti:* yazılı
- [ ] **220.05** — `copyWith(spentStars: ...)` → *bitti:* var

## 220.B — Dayanıklılık

- [ ] **220.06** — `fromJson` · `spentStars` negatifse `0`'a kırpılıyor → *bitti:* uygulandı
- [ ] **220.07** — `fromJson` · `spentStars > totalStars` ise `totalStars`'a kırpılıyor → *bitti:* uygulandı
- [ ] **220.08** — Kırpma gerekçesi yorumda (mevcut `:59-66` deseniyle aynı üslup) → *bitti:* yazılı
- [ ] **220.09** — `availableStars` asla negatif değil → *bitti:* test geçiyor
- [ ] **220.10** — `toJson` · `spentStars == 0` iken anahtar yazılmıyor (geriye uyum) → *bitti:* uygulandı

## 220.C — Harcama yolu

- [ ] **220.11** — `SagaProgress.spendStars(int amount)` veya bir use case — karar verilip uygulandı → *bitti:* tek yol var
- [ ] **220.12** — Yetersiz yıldızda ne olur: `null` mu, istisna mı → *bitti:* davranış tanımlı ve dokümanda
- [ ] **220.13** — `amount <= 0` → `ArgumentError` → *bitti:* uygulandı

## 220.D — Testler ve göç

- [ ] **220.14** — test · harcama sonrası `availableStars` doğru → *bitti:* geçiyor
- [ ] **220.15** — test · yetersiz yıldızda tanımlı davranış → *bitti:* geçiyor
- [ ] **220.16** — test · bozuk kayıt (negatif / aşkın `spentStars`) kırpılıyor → *bitti:* geçiyor
- [ ] **220.17** — test · 2.0.0 JSON'u (`spentStars` yok) okunuyor → *bitti:* geçiyor
- [ ] **220.18** — `CHANGELOG.md` · `extra['spentStars']` ile geçici çözüm üretmiş host için göç notu → *bitti:* yazılı
- [ ] **220.19** — `README.md` · "Star economy" bölümü → *bitti:* yazılı

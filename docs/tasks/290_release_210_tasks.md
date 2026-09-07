# 290 — 2.1.0 yayın kontrol listesi

| | |
|---|---|
| **Dalga** | C — **2.1.0** |
| **Bağımlılık** | 200, 210, 220, 230 |
| **Görev** | 14 |

---

## 290.A — Kapsam

- [ ] **290.01** — 200 (17) kapalı → *bitti:* işaretli
- [ ] **290.02** — 210 (15) kapalı → *bitti:* işaretli
- [ ] **290.03** — 220 (19) kapalı → *bitti:* işaretli
- [ ] **290.04** — 230 (18) kapalı → *bitti:* işaretli

## 290.B — Kırıcı olmama denetimi

- [ ] **290.05** — Zorunlu parametre eklenmedi → *bitti:* `git diff` incelendi
- [ ] **290.06** — 2.0.0 formatındaki `SagaProgress` JSON'u okunuyor → *bitti:* test geçiyor
- [ ] **290.07** — Yeni alanlar varsayılanlarındayken JSON çıktısı 2.0.0 ile aynı → *bitti:* test geçiyor
- [ ] **290.08** — `extra` üzerinden geçici çözüm üretmiş host için göç notları CHANGELOG'da (220.18, 230.18) → *bitti:* yazılı

## 290.C — Kalite ve yayın

- [ ] **290.09** — `flutter analyze` temiz → *bitti:* temiz
- [ ] **290.10** — `flutter test` yeşil → *bitti:* yeşil
- [ ] **290.11** — `example/` yeni özellikleri gösteriyor → *bitti:* çalıştırıldı
- [ ] **290.12** — `pubspec.yaml` · `version: 2.1.0` → *bitti:* güncel
- [ ] **290.13** — `docs/adrs/` durumları güncel → *bitti:* güncel
- [ ] **290.14** — `dart pub publish --dry-run` temiz → *bitti:* temiz

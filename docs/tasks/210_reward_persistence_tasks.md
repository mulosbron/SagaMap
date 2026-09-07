# 210 — Ödül kalıcılığı enjeksiyonu

| | |
|---|---|
| **Dalga** | C — **2.1.0** |
| **Kaynak** | T-14 (A4, DIP-3) · ADR-0003 |
| **Kırıcı** | Hayır (`inventory` null iken davranış aynı) |
| **Bağımlılık** | 110 |
| **Görev** | 15 |

**Gerekçe:** Paket bir `InventoryRepository` soyutlaması tanımlıyor ama
`CompleteLevelUseCase` ona hiç dokunmuyor. Soyutlama var, enjeksiyon yok —
DIP'in yarısı uygulanmış. Doküman kısmı 1.1.0'da yapıldı (010.11-010.14);
bu dosya kodu tamamlıyor.

---

## 210.A — Enjeksiyon

- [ ] **210.01** — `complete_level_usecase.dart` · `final InventoryRepository? inventory;` → *bitti:* alan var
- [ ] **210.02** — constructor parametresi, varsayılan `null` → *bitti:* var
- [ ] **210.03** — doküman: "When supplied, the rolled reward is written here before the result returns." → *bitti:* yazılı
- [ ] **210.04** — `execute` senkron kalabiliyor mu? — repository `Future` döndürdüğü için `executeAsync` mi eklenecek, karar verilip dokümana yazıldı → *bitti:* karar net
- [ ] **210.05** — Karar uygulandı: senkron `execute` korunuyor, yazma için ayrı bir `Future<CompleteLevelResult> executeAndPersist(...)` → *bitti:* uygulandı
- [ ] **210.06** — `CompleteLevelResult` · `final bool rewardPersisted;` → *bitti:* alan var
- [ ] **210.07** — `inventory` null iken `rewardPersisted == false` ve davranış 2.0.0 ile birebir → *bitti:* test geçiyor

## 210.B — Hata davranışı

- [ ] **210.08** — Yazma başarısız olursa ne olur — istisna yayılıyor mu, sonuç yine dönüyor mu → *bitti:* karar dokümanda
- [ ] **210.09** — Karar uygulandı: istisna yayılıyor, ilerleme **yazılmamış** sayılıyor; host atomikliği kendi kuruyor → *bitti:* uygulandı ve dokümanda
- [ ] **210.10** — `firstClear` koruması yazma yolunda da geçerli (çift eşya yok) → *bitti:* test geçiyor

## 210.C — Testler

- [ ] **210.11** — test · `inventory` verildiğinde eşya repository'ye yazılıyor → *bitti:* geçiyor
- [ ] **210.12** — test · `rewardPersisted == true` → *bitti:* geçiyor
- [ ] **210.13** — test · aynı boss'u tekrar tamamlamak ikinci bir yazma yapmıyor → *bitti:* geçiyor
- [ ] **210.14** — test · yazma istisnası yayılıyor → *bitti:* geçiyor
- [ ] **210.15** — `README.md` "Rewards" bölümü güncellendi (1.1.0'daki elle yazma örneğinin yanına enjeksiyon örneği) + `CHANGELOG.md` girdisi → *bitti:* yazılı

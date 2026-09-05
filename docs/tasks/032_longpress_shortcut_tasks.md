# 032 — `onLevelLongPress` kısayolu

| | |
|---|---|
| **Dalga** | A — **1.1.0** |
| **Kaynak** | T-21 (tüketici raporu kapanış notu) |
| **Kırıcı** | Hayır |
| **PR** | `feat: long-press parity` |
| **Bağımlılık** | **030** |
| **Görev** | 14 |

**Bitti tanımı:** `SagaInfiniteMapView`'de `onLevelTap` ile `onLevelLongPress`
simetrik. Tüketicinin `onNodeLongPress`'i gözden kaçırmasına yol açan asimetri
kapandı.

---

## 032.A — Görünüm parametresi

- [x] **032.01** — `lib/src/rendering/widgets/saga_infinite_map_view.dart:80` yakını · `final ValueChanged<LevelData>? onLevelLongPress;` → *bitti:* alan var (ff15122)
  - Checked off using test-driven development.
- [x] **032.02** — aynı dosya `:166` yakını · constructor parametresi → *bitti:* var (ff15122)
  - Checked off using test-driven development.
- [x] **032.03** — aynı dosya · doküman: "Convenience shortcut, mirroring [onLevelTap]. Ignored when `interactionHandler.onNodeLongPress` is set." → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.
- [x] **032.04** — aynı dosya `:490` yakını · `MapChunkWidget`'a forward et → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.

## 032.B — Chunk widget bağlantısı

- [x] **032.05** — `lib/src/rendering/widgets/map_chunk_widget.dart:49` yakını · alanı ekle → *bitti:* var (ff15122)
  - Checked off using test-driven development.
- [x] **032.06** — aynı dosya `:137` yakını · constructor parametresi → *bitti:* var (ff15122)
  - Checked off using test-driven development.
- [x] **032.07** — aynı dosya `:363-370` · `_resolveHandler` desenini uzun basma için genişlet → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.
- [x] **032.08** — öncelik kuralı: `interactionHandler.onNodeLongPress != null` ise o kazanır (tap ile aynı, `:366`) → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.
- [x] **032.09** — iki callback birden verildiğinde davranış doküman yorumunda yazılı → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.

## 032.C — Testler

- [x] **032.10** — `test/saga_infinite_map_view_test.dart` · yalnız `onLevelLongPress` verildiğinde tetikleniyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **032.11** — aynı dosya · ikisi birden verildiğinde `interactionHandler` kazanıyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **032.12** — aynı dosya · `onLevelLongPress` de `canLongPress` kapısından geçiyor (kilitli düğümde tetiklenmiyor) → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **032.13** — aynı dosya · `onLevelTap` davranışı değişmedi → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.

## 032.D — Kapanış

- [x] **032.14** — `README.md` etkileşim örneğine `onLevelLongPress` satırı + `CHANGELOG.md` girdisi → *bitti:* yazılı, `flutter test` temiz (ff15122)
  - Checked off using test-driven development.

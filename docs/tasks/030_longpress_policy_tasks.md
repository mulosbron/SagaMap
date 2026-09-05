# 030 — `canLongPress` politikası

| | |
|---|---|
| **Dalga** | A — **1.1.0** |
| **Kaynak** | T-07 (H3, ISP-2) |
| **Kırıcı** | Hayır — ama **davranış değişikliği**: kilitli düğümde uzun basma artık callback üretmiyor |
| **PR** | `feat: long-press parity` (030 + 031 + 032 tek PR) |
| **Bağımlılık** | Yok |
| **Görev** | 21 |

**Bitti tanımı:** Uzun basma da `SagaNodeInteractionPolicy`'den geçiyor;
`emitTapForLockedNode: false` diyen host kilitli düğümde uzun basma callback'i
almıyor, onun yerine `locked` durum bildirimi alıyor.

---

## 030.A — Politika

- [x] **030.01** — `lib/src/rendering/interaction/saga_node_interaction_policy.dart` · `bool canLongPress(LevelData level, LevelProgress? progress) => canTap(level, progress);` ekle → *bitti:* metot var (ff15122)
  - Checked off using test-driven development.
- [x] **030.02** — aynı yer · doküman: "Defaults to [canTap]: a node you cannot open is a node you cannot open a context menu on either." → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.
- [x] **030.03** — aynı yer · dokümana override senaryosu: kilitli düğümde "bunu nasıl açarım?" ipucu → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.
- [x] **030.04** — sınıfın `final` olmadığını doğrula (alt sınıflandırma mümkün olmalı) → *bitti:* `class SagaNodeInteractionPolicy` sade (ff15122)
  - Checked off using test-driven development.
- [x] **030.05** — constructor `const` kalıyor → *bitti:* `const SagaNodeInteractionPolicy(...)` derleniyor (ff15122)
  - Checked off using test-driven development.

## 030.B — Adaptör bağlantısı

- [x] **030.06** — `lib/src/rendering/adapters/widget_renderer_adapter.dart` · `emitTap` yanına `emitLongPress()` yerel fonksiyonu ekle → *bitti:* fonksiyon var (ff15122)
  - Checked off using test-driven development.
- [x] **030.07** — `emitLongPress` · `interactionPolicy.canLongPress(level, progress)` true ise `interactionHandler.onNodeLongPress?.call(level)` → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.
- [x] **030.08** — `emitLongPress` · false ise `onNodeFocusChange?.call(level, SagaNodeInteractionState.locked)` (tap ile aynı geri bildirim, `:106-111`) → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.
- [x] **030.09** — `:114` yakınında `final canLongPress = interactionPolicy.canLongPress(level, progress);` → *bitti:* değişken var (ff15122)
  - Checked off using test-driven development.
- [x] **030.10** — `:180-182` · `GestureDetector.onLongPress` → `canLongPress && handler.onNodeLongPress != null ? emitLongPress : null` → *bitti:* satır değişti (ff15122)
  - Checked off using test-driven development.
- [x] **030.11** — `canLongPress` `false` iken `onLongPress` **null** veriliyor (gesture arena'ya hiç girmesin) → *bitti:* doğrulandı (ff15122)
  - Checked off using test-driven development.
- [x] **030.12** — `canTap`/`canLongPress` her düğüm için **birer kez** hesaplanıyor, `build` içinde tekrarlanmıyor → *bitti:* kod incelendi (ff15122)
  - Checked off using test-driven development.

## 030.C — Testler

- [x] **030.13** — `test/saga_longpress_policy_test.dart` oluştur → *bitti:* dosya var (ff15122)
  - Checked off using test-driven development.
- [x] **030.14** — test · `emitTapForLockedNode: false` + kilitli düğüm + uzun basma → `onNodeLongPress` **çağrılmıyor** → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.15** — test · aynı senaryoda `onNodeFocusChange(level, locked)` **çağrılıyor** → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.16** — test · `emitTapForLockedNode: true` + kilitli düğüm → callback geliyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.17** — test · `unlocked` düğümde uzun basma bugünkü gibi çalışıyor (regresyon) → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.18** — test · `emitTapForCompletedNode: false` + tamamlanmış düğüm → uzun basma da kesiliyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.19** — test · `canLongPress`'i override eden özel politika, `canTap`'ten bağımsız davranıyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **030.20** — `test/map_chunk_widget_test.dart` · mevcut etkileşim testleri geçiyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.

## 030.D — Kapanış

- [x] **030.21** — `CHANGELOG.md` 1.1.0 · `Added — SagaNodeInteractionPolicy.canLongPress` + davranış değişikliği notu ("locked nodes no longer emit long-press callbacks") → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.

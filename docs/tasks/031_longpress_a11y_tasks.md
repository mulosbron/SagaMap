# 031 — Uzun basmanın klavye ve ekran okuyucuya açılması

| | |
|---|---|
| **Dalga** | A — **1.1.0** |
| **Kaynak** | T-08 (H4) · WCAG 2.1 · 2.1.1 Keyboard (Level A) |
| **Kırıcı** | Hayır |
| **PR** | `feat: long-press parity` |
| **Bağımlılık** | **030** (`canLongPress` ve `emitLongPress` önce gelmeli) |
| **Görev** | 24 |

**Bitti tanımı:** İkincil eylem üç giriş yolundan da erişilebilir — dokunma,
klavye, ekran okuyucu. `canLongPress` false iken üçü de kapalı.

---

## 031.A — Semantik eylem

- [x] **031.01** — `lib/src/rendering/adapters/widget_renderer_adapter.dart:125` · `Semantics`'e `onLongPress: canLongPress ? emitLongPress : null` ekle → *bitti:* satır var (ff15122)
  - Checked off using test-driven development.
- [x] **031.02** — `excludeSemantics: true` (`:132`) korunuyor; düğüm görseli hâlâ dekoratif → *bitti:* değişmedi (ff15122)
  - Checked off using test-driven development.
- [x] **031.03** — `enabled` / `focusable` bayrakları `canTap`'e bağlı kalıyor (uzun basma odaklanabilirliği değiştirmiyor) → *bitti:* doğrulandı (ff15122)
  - Checked off using test-driven development.
- [x] **031.04** — `onNodeLongPress == null` iken `Semantics.onLongPress` de `null` (boş eylem duyurulmasın) → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.

## 031.B — Klavye kısayolu

- [x] **031.05** — aynı dosya · `class _SagaContextMenuIntent extends Intent` (private) tanımla → *bitti:* tip var (ff15122)
  - Checked off using test-driven development.
- [x] **031.06** — `package:flutter/services.dart` import'u ekle (`LogicalKeyboardKey`) → *bitti:* derleniyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.07** — `FocusableActionDetector.shortcuts` haritası ekle → *bitti:* alan var (ff15122)
  - Checked off using test-driven development.
- [x] **031.08** — kısayol · `SingleActivator(LogicalKeyboardKey.f10, shift: true)` → *bitti:* eşleniyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.09** — kısayol · `SingleActivator(LogicalKeyboardKey.contextMenu)` → *bitti:* eşleniyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.10** — `actions` haritasına `_SagaContextMenuIntent: CallbackAction(...)` → `emitLongPress()` → *bitti:* uygulandı (ff15122)
  - Checked off using test-driven development.
- [x] **031.11** — `canLongPress` false iken kısayol **hiç kaydedilmiyor** (boş `shortcuts` haritası) → *bitti:* doğrulandı (ff15122)
  - Checked off using test-driven development.
- [x] **031.12** — mevcut `ActivateIntent` / `ButtonActivateIntent` eylemleri değişmedi (`:138-145`) → *bitti:* regresyon yok (ff15122)
  - Checked off using test-driven development.
- [x] **031.13** — macOS'ta bağlam menüsü tuşu bulunmadığı için `Shift+F10`'un platformlar arası birincil kısayol olduğu doküman yorumunda → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.

## 031.C — Testler

- [x] **031.14** — `test/saga_keyboard_test.dart` · odaklı düğümde `Shift+F10` → `onNodeLongPress` tetikleniyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.15** — aynı dosya · bağlam menüsü tuşu aynı sonucu veriyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.16** — aynı dosya · `canLongPress` false iken `Shift+F10` hiçbir şey yapmıyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.17** — aynı dosya · Tab sırası ve `Enter`/`Space` davranışı değişmedi → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.18** — `test/saga_semantics_test.dart` · düğümün `SemanticsAction.longPress` taşıdığı doğrulanıyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.19** — aynı dosya · `onNodeLongPress` verilmemişken `longPress` eylemi **yok** → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.20** — aynı dosya · kilitli düğümde `longPress` eylemi yok → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.
- [x] **031.21** — `test/saga_rtl_test.dart` · RTL'de kısayol davranışı bozulmuyor → *bitti:* geçiyor (ff15122)
  - Checked off using test-driven development.

## 031.D — Doküman ve kapanış

- [x] **031.22** — `README.md` · "Accessibility" bölümüne ikincil eylem satırı: "Shift+F10 or the context-menu key triggers the long-press action" → *bitti:* yazılı (ff15122)
  - Checked off using test-driven development.
- [x] **031.23** — `README.md` · CHANGELOG'un "Enter and Space activate" ifadesinin artık eksik olmadığı, ikincil eylemin de listelendiği → *bitti:* güncel (ff15122)
  - Checked off using test-driven development.
- [x] **031.24** — `CHANGELOG.md` 1.1.0 · `Added — the long-press action is reachable from the keyboard and screen readers` → *bitti:* yazılı, `flutter test` temiz (ff15122)
  - Checked off using test-driven development.

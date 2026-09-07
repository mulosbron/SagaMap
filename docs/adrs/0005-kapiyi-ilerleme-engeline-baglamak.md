# 5. Kapıyı hareket engelinden ilerleme engeline yükseltmek

Date: 2026-09-05

## Status

Accepted — implemented in 2.0.0.

## Context

`SagaMapGate` ve `clampTravelThroughGates` (`saga_map_gate.dart`) kapıyı bir
**hareket** engeli olarak modelliyor. Doküman yorumu bunu açıkça söylüyor:
"The library positions the gate and stops the character at it."

Kaynak taraması bundan daha ağır bir tablo gösteriyor:

```
$ grep -rn "clampTravelThroughGates" lib
lib/src/rendering/character/saga_character_controller.dart:39:  /// [clampTravelThroughGates].   ← yalnızca bir doküman yorumu
lib/src/rendering/character/saga_map_gate.dart:36:double clampTravelThroughGates(  ← tanımın kendisi
```

Yani fonksiyon paket içinde **hiçbir yerden çağrılmıyor.** `SagaInfiniteMapView`'in
`gates` parametresi yok (`saga_infinite_map_view.dart:60-152`). Kapı, paketin
ihraç ettiği ama kendisinin hiç kullanmadığı bir yardımcı fonksiyon: host onu elle
çağırmazsa kapı hiçbir şey yapmaz.

Dahası, kapı üç sistemden hiçbirine bağlı değil:

| Sistem | Kapıdan haberdar mı |
|---|---|
| Karakter yürüyüşü | ❌ host elle çağırmalı |
| Düğüme dokunma (`SagaNodeInteractionPolicy`) | ❌ |
| Kilit açma (`CompleteLevelUseCase`) | ❌ `:69` koşulsuz `levelId + 1` |

Sonuç: "önceki boss geçilmeden sonraki blok açılmasın" mekaniği pakette **yok**.
Üretimdeki tüketici bunu host tarafında `BossRules.isUnlocked(...)` olarak yeniden
yazdı ve paketin kendi kilit mantığının **yerine geçirdi**. Paketin ilerleme
modeli devre dışı bırakıldı.

Kavramsal kök: oyun tasarımında kapı bir **ilerleme** engelidir; paket onu bir
görsel/hareket engeli sanıyor. Modelin kendisi eksik.

## Decision

Kapı, üç dikişle ilerleme sistemine bağlanır. Üçü de isteğe bağlı; hiçbiri
verilmediğinde davranış 1.x ile birebir aynı kalır.

**1. Etkileşim — dokunma kapıya danışır**
```dart
class SagaNodeInteractionPolicy {
  /// Host veto on reaching a node at all — a closed gate, a ticket, a purchase.
  ///
  /// Consulted before [canTap]: returning false makes the node unreachable
  /// regardless of its recorded progress state, and the node is announced,
  /// focused and cursored as locked.
  final bool Function(LevelData level, LevelProgress? progress)? isReachable;
}
```

**2. İlerleme — kilit açma kapıya danışır**
```dart
class CompleteLevelUseCase {
  /// Vetoes unlocking the successor. Returning false completes the level but
  /// leaves the next one locked — the gate stays shut.
  final bool Function(int levelId)? canUnlock;
}
```

**3. Görünüm — kapıları paket taşır**
```dart
class SagaInfiniteMapView {
  /// Barriers on the path. The view applies [clampTravelThroughGates] itself.
  final List<SagaMapGate> gates;
}
```

Kapının **açık olup olmadığı** host'un kararı olmaya devam eder — bilet, arkadaş,
satın alma oyun ekonomisidir, harita geometrisi değil. Paket yalnızca kararın
sonuçlarını üç sisteme birden uygular.

Kapı durumunu paketin kendi modeline (`SagaProgress`) yazmak reddedildi: kapı
koşulları oyuna özgüdür ve paketin bilemeyeceği verilere dayanır. Kanca doğru
soyutlama düzeyi.

## Consequences

### Olumlu
- Kapı kavramı tamamlanır: aynı kapı hem karakteri durdurur, hem dokunmayı keser,
  hem kilit açmayı engeller. Üç sistem tek kaynaktan beslenir.
- Host'un paketin ilerleme mantığını **yerine geçirmesi** gerekmez; genişletmesi yeterli.
  Bugünkü durumda `CompleteLevelUseCase` fiilen kullanılamıyordu.
- `isReachable` erişilebilirlikle bedavaya hizalanır: ulaşılamayan düğüm Tab'da
  atlanır ve ekran okuyucuya "locked" duyurulur — çünkü `canTap` zaten bu üç şeyi
  birden sürüyor (`widget_renderer_adapter.dart:127-135`).
- `gates` parametresiyle kapı ilk kez paketin kendi kullandığı bir kavram olur;
  ihraç edilip kullanılmayan fonksiyon anomalisi kapanır.

### Olumsuz
- **`CompleteLevelResult`'ta yeni bir durum doğar:** "tamamlandı ama ardıl açılmadı."
  Bunu okumayan host, oyuncunun neden ilerleyemediğini gösteremez. Sonuç nesnesine
  açıklayıcı bir alan gerekebilir (`unlockBlocked`) — uygulama sırasında karara bağlanacak.
- İki yeni kanca, iki yeni yanlış kullanım yolu: `isReachable` ile `canUnlock`
  çelişirse (dokunulabilir ama açılmayan seviye) tuhaf bir durum çıkar. Doküman
  yorumları ikisinin birlikte kullanımını göstermeli.
- `canUnlock`, `enforceUnlockOrder` bayrağıyla üst üste binen bir kavram alanı
  yaratır. İkisinin ilişkisi netleştirilmeli: `enforceUnlockOrder` geriye dönük
  koruma (atlama engelleme), `canUnlock` ileriye dönük koruma (kapı).
- `SagaInfiniteMapView` bir parametre daha alır; sınıf zaten 657 satır
  (SRP-1 notu). Kapı mantığı ayrı bir yardımcıya çıkarılmalı, `build` içine gömülmemeli.
- Kırıcı: semantik değişim ve yeni imzalar 2.0.0 gerektirir.

## Related

- Görev: T-06
- Bulgu: DIP-2, OCP-4 (`.old/docs/reports/01-solid-uyumluluk-denetimi.md`)

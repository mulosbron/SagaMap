# 11. Kilit işaretçisini kayıtlarla uzlaştırmak ve 1.x için açık bir geçiş girişi

Date: 2026-09-07

## Status

Accepted — implemented in 2.0.0.

## Context

`694bca7` birbirini besleyen iki değişikliği aynı sürüme koydu:

1. `SagaProgress.fromJson`, `currentMaxUnlockedLevelId`'yi `max(levels.keys) + 1`'e
   kırpmaya başladı.
2. `CompleteLevelUseCase.enforceUnlockOrder` varsayılan olarak `true` oldu.

Denetim (`sast/verification-report-2.0.0.md`, V-1 ve V-2) ikisinin de eksik
olduğunu gösterdi:

**Katlama her anahtarı sayıyordu.** Kayıt durumu okunmuyordu, dolayısıyla
`locked` durumundaki tek bir sahte kayıt tavanı istediği yere taşıyordu.
Çalıştırılarak doğrulandı: `{'currentMaxUnlockedLevelId': 999999,
'levels': {'0': unlocked, '999998': locked}}` yüklendiğinde işaretçi 999999'da
kalıyor ve koruma açıkken `CompleteLevelUseCase()` 999998'i tamamlıyordu. Yani
2.0.0'ın en görünür güvenlik iddiası — "kurcalanmış bir kayıt korumanın
dayandığı işaretçiyi kendine veremez" — tutmuyordu.

**Kırpma 1.x kurulumlarını sessizce vuruyordu.** 1.x, kaydı olmayan bir seviyeyi
"işaretçinin altındaysa açık" diye okuyordu; bu yüzden 1.x host'unun seyrek bir
`levels` map'i ile ileri bir işaretçi persist etmesi tamamen olağandı. 2.0.0'da
aynı kayıt yüklendiğinde işaretçi düşüyor, ardından `enforceUnlockOrder`
üstündeki her seviyeyi reddediyor. Oyuncu için bu, ilerlemenin silinmesidir.
CHANGELOG kırpmayı yalnız kurcalama önlemi olarak anlatıyor, geçişten hiç söz
etmiyordu.

## Decision

**Tavan tamamlanmış kayıtlar üzerinden katlanır, ama işaretçi kendi kaydıyla da
kendini haklı çıkarabilir.**

Kural tek cümlede: *bir işaretçi ya altındaki bir tamamlanma ile ya da kendi
kaydıyla haklı çıkarılmalıdır; ilgisiz bir seviyenin kaydıyla asla.*

- `completed`, paketin oyunun sonucu olarak kendi yazdığı tek durumdur; tavanın
  üzerine oturabileceği tek kayıt odur. Hiç tamamlanma yoksa tavan `0`'dır.
- İşaretçinin **kendisinde** `unlocked` ya da `completed` bir kayıt varsa
  işaretçi olduğu gibi kalır. Bu, bilerek ileri atlayan host'tur — bölüm-atlama
  satın alması, hata ayıklama derlemesi, `enforceUnlockOrder: false` — ve kaydı
  yazarak bunu söylemiştir. Yalnız tamamlanmalar üzerinden katlamak bu host'un
  kayıtlarını her yüklemede bozardı.

Saldırgan elbette `999999: unlocked` yazabilir; ama o zaman istediği seviyenin
kaydını yazmış olur. Kapanan boşluk şudur: **bir seviyenin kaydı artık başka bir
seviye hakkında bir iddia değildir.** Bir kayıt dosyası tümüyle host'un
denetimindedir, dolayısıyla burada kazanılacak mutlak bir güvenlik sınırı yoktur
(ADR-0009); kazanılan şey, işaretçinin artık dosyanın kendi içinde tutarlı
olmasıdır.

**Kırpma korunur, sessizliği korunmaz** (denetimin (a) seçeneği):
`fromJson` isteğe bağlı bir `onClamp` geri çağrısı alır ve işaretçi gerçekten
oynadığında `SagaProgressClamp` verir. Varsayılan davranış değişmez — `fromJson`
her yüklemede koşar, gürültü yapamaz — ama artık raporlanamaz değildir.

**Ayrıca açık bir geçiş girişi eklenir** (denetimin (c) seçeneği):
`SagaProgress.migrateFrom1x`, `[0, işaretçi]` aralığındaki kaydı olmayan her
id'yi `unlocked` olarak doldurur ve saklanan işaretçiyi olduğu gibi korur. Yıldız
vermez, hiçbir şeyi tamamlamaz; yalnız 1.x okumasının verdiği erişilebilirliği
geri koyar. `maxBackfill` (varsayılan `10000`) düşmanca bir işaretçinin
yaptırabileceği işi sınırlar.

## Consequences

- Denetimin V-1 saldırı yükü artık işaretçiyi `0`'a düşürüyor; koruma açıkken
  999998 tamamlanamıyor.
- `migrateFrom1x` **saklanan işaretçiye güvenir** — `fromJson`'ın esirgediği
  garanti tam da budur. Sözleşmesi: yalnız kendi 1.x derlemenizin yazdığını
  bildiğiniz bir yükte, bir kez, yükseltme anında çağrılır; sonucu persist
  edilir; sonraki her yükleme yine `fromJson`'dan geçer.
- Yeni bir kayıt dosyasının tavanı artık `1` değil `0`'dır: `initial()` seviye
  0'ı `unlocked` yazar, `completed` değil. Hiçbir şey temizlenmemişken hiçbir
  şey açılmamıştır.
- `SagaProgressClamp` yeni bir public tiptir; `saga_map.dart` üzerinden ihraç
  edilir.
- Geçiş, CHANGELOG 2.0.0'da "Migration — 1.x saves" başlığı ve README'nin
  "Upgrading from 1.x" bölümüyle adlandırılmıştır; sürüm kapısı
  (`test/saga_2_0_0_upgrade_test.dart`) artık kırpmayı gerçekten tetikleyen
  **boşluklu** bir ikinci 1.1.0 fixture'ı taşır. Eski fixture'da işaretçi 16 ve
  en yüksek tamamlanma 15 olduğu için kırpma orada no-op'tur; tehlike o kapıdan
  hiç geçmiyordu.

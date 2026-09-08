# 9. İstemci tarafında yuvarlanan ödülü tavsiye niteliğinde saymak

Date: 2026-09-07

## Status

Accepted — implemented in 2.0.0.

## Context

Boss ödülü saf bir fonksiyon: `rollBossReward` tohumu `levelId ^ globalSeed`
olarak kuruyor ve aynı üçlü `(levelId, globalSeed, table)` her zaman aynı
eşyayı veriyor. Bu, paketin baştan beri istediği özellik — aynı tohum aynı
dünyayı üretsin, bir hata yeniden oynatılabilsin, altın testler kararlı olsun.

2.0.0 ile `saveGlobalSeed` eklendi (ADR-0004). Artık tohum host tarafından
yazılabilir. Cihazı elinde tutan oyuncu için bu şu demek:

1. Kaydedilen tohumu değiştir,
2. `rollBossReward(levelId: 14, globalSeed: adayTohum)` çağrısını çevrimdışı,
   boss'u geçmeden çalıştır,
3. efsanevi eşyayı düşüren tohumu bul, onu kaydet, sonra boss'u geç.

Bu bir "açık" değil, mimarinin doğrudan sonucu: istemcide çalışan saf ve
deterministik bir fonksiyonun girdisini yine istemci yazıyor. Ancak paketin
kendi yorumları `execute` içinde "ilk geçiş bütünlüğü"nden söz ediyor
(`complete_level_usecase.dart`), ve envanteri bir sunucuya yükselten bir host
bu ifadeye güvenip deliği devralıyor.

## Decision

| Seçenek | Artı | Eksi |
|---|---|---|
| **A. Güven sınırını yaz, davranışı değiştirme** | Yeniden üretilebilirlik korunur; altın testler ve hata ayıklama bozulmaz; host kendi otoritesini kendi kurar | Tohum alışverişi ücretsiz kalır |
| B. Yuvarlamaya oyuncunun seçmediği bir değer karıştır (ilk geçiş zaman damgası, kurulum başına tuz) | Tohum alışverişi ücretsiz olmaktan çıkar | Aynı tohum artık aynı dünyayı vermez; determinizm, ADR-0004'ün ve altın testlerin dayandığı özellik, kaybolur |
| C. Ödülü tamamen host'a bırak | Paket hiçbir şey iddia etmez | `kMvpLootTable` ile birlikte gelen "çalışan varsayılan" gider |

**A seçildi.** Belirleyicilik ile istemci tarafı bütünlük aynı anda elde
edilemez: biri girdiden çıktının hesaplanabilmesini ister, diğeri tam olarak
bunun engellenmesini. İstemcide çalışan bir pakette, cihazın sahibi girdiyi
yazabildiği sürece ikincisi zaten sağlanamaz — sunucu tarafı bir otorite
olmadan "engellendi" demek, engeli değil yalnızca yanılsamayı üretir.

Dolayısıyla paket belirleyiciliği korur ve sınırı açıkça yazar: **istemcide
yuvarlanan ödül tavsiye niteliğindedir, otorite değildir.** Otorite isteyen
host ödülü sunucuda yuvarlar; `rollBossReward` ona ne düşeceğini *önizlemek*
için kalır.

B seçeneğinin bir tuz ile yapılabileceği doğru, ancak tuz da cihazda saklanır;
oyuncu tuzu da okuyabildiği için maliyet artar, sınır değişmez. Yalnızca
belirleyicilik gider.

## Consequences

### Olumlu

- Aynı tohum aynı dünyayı ve aynı ödülü verir; altın testler, hata raporlarının
  yeniden üretimi ve `--platform chrome` eşliği (T-03) korunur.
- Sınır yazılı: `saveGlobalSeed` ve `rollBossReward` doküman yorumları ile
  README güvenlik notu aynı şeyi söylüyor, host neyi devraldığını biliyor.
- Sunucu otoritesi isteyen host için yol açık ve tek adımlı: ödülü sunucuda
  yuvarla, istemcideki çağrıyı önizlemeye indir.

### Olumsuz

- Cihazı elinde tutan oyuncu için tohum alışverişi ücretsiz kalır.
- Paket, kendi başına "ilk geçiş bütünlüğü" garanti edemez; `execute` içindeki
  ilk geçiş koruması bir kolaylıktır, bir güvenlik sınırı değil (T-13).

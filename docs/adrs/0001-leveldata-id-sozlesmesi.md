# 1. LevelData.id sözleşmesi: 0 tabanlı, gösterimde id + 1

Date: 2026-09-05

## Status

Accepted — implemented in 1.1.0.

## Context

`LevelData.id`'nin tabanı hiçbir yerde yazılı değil. `README.md`'nin 458 satırında
konu hiç geçmiyor. Sonuç, kaynağın kendi içinde çelişmesi:

| Yer | Varsayım |
|---|---|
| `saga_map_level_generator.dart:34` — `levelId = startLevelId + offset`, host ilk chunk için `0` geçiyor | 0 tabanlı |
| `saga_map_level_generator.dart:52` — `difficulty: 1 + (levelId % 5)`, id 0 → zorluk 1 (en kolay) | 0 tabanlı |
| `saga_progress.dart:14-25` — `SagaProgress.initial()` seviye `0`'ı açıyor | 0 tabanlı |
| `loot_table.dart:45` — `isBossLevel(id) => id > 0 && id % 15 == 0` | **1 tabanlı** |
| `widget_renderer_adapter.dart:37` — `'Level ${level.id}'` | ham indeks |

Beş çağrı yerinin dördü 0 tabanlı, biri değil, biri de kararsız. Bu bir kod hatası
değil; yazılmamış bir sözleşmenin kaçınılmaz sonucu. Üretimdeki ilk tüketici
(SudokuLens) tam bu noktada tökezledi ve rapor etti.

Türev sorunlar: H1 (boss bir seviye kayıyor), H2 (ekran okuyucu "Level 0" diyor),
B4-2 (README sessiz), B4-4 (örnek hatayı çoğaltıyor).

## Decision

`LevelData.id` **0 tabanlıdır**. Bu, kodda zaten baskın olan varsayımdır ve
`SagaProgress.initial()` ile jeneratörün sözleşmesidir; değiştirilemez.

Buna bağlı iki kural:

1. **Depolama ve mantık ham `id` kullanır.** Kilit açma, ilerleme, kalıcılık,
   dizin erişimi — hepsi 0 tabanlı.
2. **Oyuncuya gösterilen her sayı `id + 1`'dir.** Düğüm üstündeki rakam, ekran
   okuyucu etiketi, bölüm başlığı, "15. seviye" gibi her metin.

Sözleşme üç yere yazılır:
- `LevelData` sınıf dokümanına bir cümle,
- `README.md`'ye "Level ids" başlığı,
- Tabanla ilgili karar veren her fonksiyonun doküman yorumuna
  (`isBossLevel`, `defaultSagaNodeSemanticsLabel`).

## Consequences

### Olumlu
- Türev dört sorun (H1, H2, B4-2, B4-4) tek bir sözleşmenin uygulanmasına indirgenir.
- Yeni tüketicinin ilk yapacağı hata kapanır.
- `difficulty`, `isBossLevel` ve kilometre taşı sistemleri aynı tabanda hizalanır:
  `id % 15 == 14` aynı anda `id % 5 == 4` olduğu için boss her zaman en zor tahtaya düşer.
- Gelecekteki her API kararının cevaplayacağı bir referans doğar ("bu sayı ham mı,
  gösterim mi?").

### Olumsuz
- `isBossLevel`'ın düzeltilmesi kırıcıdır (bkz. ADR-0002); sözleşmeyi yazmak
  otomatik olarak bir majör sürüm doğurur.
- Host kodunda `id + 1` ile `id` arasında sürekli bir zihinsel çeviri kalır.
  Ayrı bir `DisplayLevelNumber` tipi bunu kapatabilirdi ama tek alanlı bir sarmalayıcı
  tip, bu ölçekte kazandığından fazlasını maliyet yazar — reddedildi.
- Mevcut tüketicilerin, kendi UI'larında `id`'yi ham gösterip göstermediklerini
  denetlemesi gerekir.

## Related

- ADR-0002 (boss formülü)
- Görev: T-19, T-02, T-01, T-22

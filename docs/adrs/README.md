# Architecture Decision Records

`software-architecture-skills/skills/writing-adrs/SKILL.md` şablonu:
**Title · Status · Context · Decision · Consequences (olumlu + olumsuz).**

| # | Karar | Durum | Sürüm | Görevler |
|---|---|---|---|---|
| [0001](0001-leveldata-id-sozlesmesi.md) | `LevelData.id` 0 tabanlı, gösterimde `id + 1` | Proposed | 1.1.0 | T-19, T-02 |
| [0002](0002-boss-seviye-formulunu-duzeltmek.md) | Boss formülü `% 15 == 14`, 2.0.0'a çıkış | Proposed | 2.0.0 | T-01, T-22 |
| [0003](0003-odul-sistemini-enjekte-edilebilir-kilmak.md) | Ödül sistemi Strategy + Constructor Injection | Proposed | 2.0.0 | T-04, T-12, T-13, T-14 |
| [0004](0004-saga-progress-genisletilebilirligi.md) | `SagaProgress.extra` + `saveGlobalSeed` | Proposed | 1.1.0 / 2.0.0 | T-03, T-09 |
| [0005](0005-kapiyi-ilerleme-engeline-baglamak.md) | Kapı = ilerleme engeli (3 kanca) | Proposed | 2.0.0 | T-06 |
| [0006](0006-builder-baglami-ve-seviye-hizali-dekor.md) | `SagaChunkContext` + `atLevel` dekor | Proposed | 1.1.0 | T-05, T-10, T-15 |
| [0007](0007-host-tanimli-biyomlar.md) | `SagaMapConfig.biomeIds` + tema asset kancası | Proposed | 2.0.0 | T-11 |
| [0008](0008-flutter-svg-bagimliligini-ayirmak.md) | `flutter_svg` bağımlılığını düşür | Proposed | 2.0.0 | T-20 |

## Durum akışı

Her ADR `Proposed` başlar. Uygulanan görev birleştirildiğinde `Accepted`,
vazgeçilirse `Rejected`, sonraki bir kararla değişirse `Superseded by ADR-XXXX`
olur. Sürüm yayımlanmadan önce ilgili ADR'lerin durumu güncellenmelidir
(bkz. `../reports/04-surumleme-ve-gecis-plani.md` §7).

## Yeni ADR

    python software-architecture-skills/tools/arch_tools.py adr-new "Karar başlığı"

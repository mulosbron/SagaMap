# Architecture Decision Records

Her ADR aynı şablonu izler — **Title · Status · Context · Decision · Consequences**
(**Olumlu** ve **Olumsuz** alt başlıklarıyla):

- **Title** — kararın tek satırlık adı (dosya başlığı `# N. ...`).
- **Status** — `Proposed`, `Accepted`, `Rejected` veya `Superseded by ADR-XXXX`.
- **Context** — kararı gerektiren durum ve kısıtlar.
- **Decision** — alınan karar, reddedilen seçenekler ve gerekçesi.
- **Consequences** — **Olumlu** / **Olumsuz** başlıkları altında sonuçlar.

| # | Karar | Durum | Sürüm | Görevler |
|---|---|---|---|---|
| [0001](0001-leveldata-id-sozlesmesi.md) | `LevelData.id` 0 tabanlı, gösterimde `id + 1` | Accepted | 1.1.0 | T-19, T-02 |
| [0002](0002-boss-seviye-formulunu-duzeltmek.md) | Boss formülü `% 15 == 14`, 2.0.0'a çıkış | Accepted | 2.0.0 | T-01, T-22 |
| [0003](0003-odul-sistemini-enjekte-edilebilir-kilmak.md) | Ödül sistemi Strategy + Constructor Injection | Accepted | 2.0.0 | T-04, T-12, T-13, T-14 |
| [0004](0004-saga-progress-genisletilebilirligi.md) | `SagaProgress.extra` + `saveGlobalSeed` | Accepted | 1.1.0 / 2.0.0 | T-03, T-09 |
| [0005](0005-kapiyi-ilerleme-engeline-baglamak.md) | Kapı = ilerleme engeli (3 kanca) | Accepted | 2.0.0 | T-06 |
| [0006](0006-builder-baglami-ve-seviye-hizali-dekor.md) | `SagaChunkContext` + `atLevel` dekor | Accepted | 1.1.0 | T-05, T-10, T-15 |
| [0007](0007-host-tanimli-biyomlar.md) | `SagaMapConfig.biomeIds` + tema asset kancası | Accepted | 2.0.0 | T-11 |
| [0008](0008-flutter-svg-bagimliligini-ayirmak.md) | `flutter_svg` bağımlılığını düşür | Accepted | 2.0.0 | T-20 |
| [0009](0009-istemci-tarafi-odul-guven-siniri.md) | İstemcide yuvarlanan ödül tavsiye niteliğindedir | Accepted | 2.0.0 | T-14 |

## Durum akışı

Her ADR `Proposed` başlar. Uygulanan görev birleştirildiğinde `Accepted`,
vazgeçilirse `Rejected`, sonraki bir kararla değişirse `Superseded by ADR-XXXX`
olur. Sürüm yayımlanmadan önce ilgili ADR'lerin durumu güncellenmelidir
(bkz. `../reports/04-surumleme-ve-gecis-plani.md` §7).

## Yeni ADR

`docs/adrs/` içinde `NNNN-kisa-baslik.md` adında yeni bir dosya açın; numara olarak
mevcut en yüksek ADR numarasının bir fazlasını kullanın. Dosyayı yukarıdaki şablonu
izleyerek doldurun (**Title · Status · Context · Decision · Consequences**) ve
`README.md`'deki tabloya yeni satırı ekleyin.

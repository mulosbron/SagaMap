# 05 â€” C4 GÃ¶rÃ¼nÃ¼mÃ¼: Paket â†” Host SÄ±nÄ±rÄ± ve Eksik GeniÅŸleme DikiÅŸleri

**Beceri:** `software-architecture-skills/skills/documenting-with-c4/SKILL.md`

C4'Ã¼n Ã¼Ã§ seviyesi bu pakete uyarlandÄ±. AmaÃ§ estetik deÄŸil teÅŸhis: **paketin
nerede bitip host'un nerede baÅŸladÄ±ÄŸÄ±nÄ±** Ã§izmek ve tÃ¼ketici raporundaki her
maddenin bu sÄ±nÄ±rÄ±n hangi noktasÄ±nda bir delik olduÄŸunu gÃ¶stermek.

> C4 notu: bir "Container" burada bir Docker konteyneri deÄŸil, ayrÄ± daÄŸÄ±tÄ±labilir
> bir birim â€” yani `saga_map` paketi ile onu tÃ¼keten uygulama.

---

## Seviye 1 â€” BaÄŸlam (Context)

```mermaid
graph TB
    player["ğŸ‘¤ Oyuncu<br/>Haritada ilerler, seviye oynar"]
    a11y["ğŸ‘¤ Ekran okuyucu /<br/>klavye kullanÄ±cÄ±sÄ±"]
    host["ğŸ® Host Uygulama<br/>(SudokuLens)<br/>Oyun dÃ¶ngÃ¼sÃ¼, ekonomi, envanter"]
    pkg["ğŸ“¦ saga_map<br/>Harita Ã¼retimi, Ã§izim, ilerleme"]
    store["ğŸ’¾ KalÄ±cÄ± depo<br/>(host: saga_box)"]

    player -->|"DÃ¼ÄŸÃ¼me dokunur,<br/>haritayÄ± kaydÄ±rÄ±r"| host
    a11y -->|"Tab / Enter /<br/>ekran okuyucu"| host
    host -->|"Konfig, tema, builder'lar;<br/>LevelData ve olay alÄ±r"| pkg
    host -->|"SagaProgress JSON'u<br/>+ kendi anahtarlarÄ±"| store
    pkg -.->|"âŒ Ã–dÃ¼l yazmaz<br/>(A4/DIP-3)"| store
```

**Okuma:** Paket depoya hiÃ§ dokunmuyor â€” bu doÄŸru bir tasarÄ±m tercihi. Sorun,
bunun **hiÃ§bir yerde yazÄ±lÄ± olmamasÄ±**: `CompleteLevelResult.reward` dÃ¶ner,
host onu yazmazsa eÅŸya sessizce kaybolur ve hiÃ§bir uyarÄ± Ã§Ä±kmaz (â†’ T-14, T-19).

---

## Seviye 2 â€” Konteyner (Container)

```mermaid
graph LR
    subgraph host["Host Uygulama"]
        game["Oyun mantÄ±ÄŸÄ±"]
        realm["SagaRealm<br/>(10 diyar â€” paketin<br/>biyom sistemi yerine)"]
        boss["BossRules<br/>(paketin kilit<br/>mantÄ±ÄŸÄ± yerine)"]
        loot2["Kendi loot sistemi<br/>(paketinki yerine)"]
        repo2["Ä°kinci kayÄ±t katmanÄ±<br/>(SagaProgress'e<br/>sÄ±ÄŸmayan veriler)"]
    end

    subgraph pkg["saga_map paketi"]
        domain["core/domain<br/>Ãœretim, ilerleme, Ã¶dÃ¼l"]
        data["core/data<br/>Repository sÃ¶zleÅŸmeleri"]
        render["rendering<br/>Widget, painter, etkileÅŸim"]
    end

    game --> render
    game --> domain
    domain --> data

    realm -.->|"ğŸ”´ A10: biyom listesi<br/>geniÅŸletilemedi"| domain
    boss -.->|"ğŸ”´ A9: kapÄ± ilerlemeye<br/>baÄŸlanamadÄ±"| domain
    loot2 -.->|"ğŸ”´ A1: loot enjekte<br/>edilemedi"| domain
    repo2 -.->|"ğŸ”´ A5: SagaProgress<br/>geniÅŸletilemedi"| data
```

**TeÅŸhis:** Kesikli oklar, host'un paketin bir alt sistemini **yeniden yazmak
zorunda kaldÄ±ÄŸÄ±** yerler. DÃ¶rt tane var ve hepsi aynÄ± sebepten: paketin o alt
sistemi, host'un uzatabileceÄŸi bir dikiÅŸ sunmuyor.

Bu diyagramÄ±n en Ã§arpÄ±cÄ± okumasÄ± ÅŸu: **paketin `core/domain` katmanÄ±nÄ±n dÃ¶rt alt
sistemi de host tarafÄ±nda ikizlenmiÅŸ.** KÃ¼tÃ¼phane, Ã§izim motoru olarak
kullanÄ±lÄ±yor; alan modeli olarak kullanÄ±lamÄ±yor.

---

## Seviye 3 â€” BileÅŸen: `core/domain`

```mermaid
graph TB
    uc["CompleteLevelUseCase<br/><i>complete_level_usecase.dart</i>"]
    boss["isBossLevel()<br/><i>top-level fonksiyon</i>"]
    roll["rollBossReward()<br/><i>top-level fonksiyon</i>"]
    table["kMvpLootTable<br/><i>const global</i>"]
    prog["SagaProgress<br/><i>final alanlar</i>"]
    gen["SagaMapLevelGenerator"]
    ids["kSagaBiomeIds<br/><i>const global</i>"]
    lgen["LevelGenerator<br/><i>abstract</i>"]
    repo["SagaProgressRepository<br/><i>abstract interface</i>"]

    uc -->|"ğŸ”´ doÄŸrudan Ã§aÄŸrÄ±<br/>DIP-1"| boss
    uc -->|"ğŸ”´ doÄŸrudan Ã§aÄŸrÄ±<br/>DIP-1"| roll
    roll -->|"ğŸ”´ sabit okuma<br/>OCP-2"| table
    uc --> prog
    gen -->|"ğŸ”´ sabit okuma<br/>OCP-3"| ids
    gen -.->|"âœ… uygular"| lgen
    uc -.-> repo

    style boss fill:#fee,stroke:#c00
    style roll fill:#fee,stroke:#c00
    style table fill:#fee,stroke:#c00
    style ids fill:#fee,stroke:#c00
    style lgen fill:#efe,stroke:#0a0
    style repo fill:#efe,stroke:#0a0
```

### DiyagramÄ±n sÃ¶ylediÄŸi

YeÅŸil kutular (`LevelGenerator`, `SagaProgressRepository`) paketin **doÄŸru
kurulmuÅŸ** soyutlamalarÄ± â€” host bunlarÄ± deÄŸiÅŸtirebiliyor.

KÄ±rmÄ±zÄ± kutular ise aynÄ± katmanda duran ama soyutlanmamÄ±ÅŸ kurallar. AralarÄ±ndaki
fark tesadÃ¼fi gÃ¶rÃ¼nÃ¼yor: seviye Ã¼retimi enjekte edilebilir, Ã¶dÃ¼l Ã¼retimi deÄŸil.
Oysa ikisi de aynÄ± tÃ¼rden bir alan kuralÄ±.

**Bu, tek bir cÃ¼mlelik teÅŸhis:** paket "nasÄ±l Ã§izilir" ve "nasÄ±l Ã¼retilir"
sorularÄ±nÄ± soyutlamÄ±ÅŸ, "hangi kural geÃ§erlidir" sorusunu soyutlamamÄ±ÅŸ.

### Hedef durum (2.0.0 sonrasÄ±)

```mermaid
graph TB
    uc["CompleteLevelUseCase<br/>bossRule, lootTable, canUnlock"]
    rule["SagaBossRule<br/><i>typedef</i>"]
    table["List&lt;LootTableEntry&gt;<br/><i>parametre</i>"]
    unlock["canUnlock<br/><i>typedef</i>"]
    defb["isBossLevel<br/><i>varsayÄ±lan</i>"]
    deft["kMvpLootTable<br/><i>varsayÄ±lan</i>"]
    hostb["Host kuralÄ±"]
    hostt["Host tablosu"]

    uc --> rule
    uc --> table
    uc --> unlock
    rule -.-> defb
    rule -.-> hostb
    table -.-> deft
    table -.-> hostt

    style rule fill:#efe,stroke:#0a0
    style table fill:#efe,stroke:#0a0
    style unlock fill:#efe,stroke:#0a0
```

DeÄŸiÅŸim maliyeti: **bir `typedef`, Ã¼Ã§ constructor parametresi, bir opsiyonel
fonksiyon argÃ¼manÄ±.** Yeni sÄ±nÄ±f yok, kayÄ±t defteri yok, plugin mimarisi yok â€”
`balancing-architectural-tradeoffs`'un aÅŸÄ±rÄ± mÃ¼hendislik uyarÄ±sÄ±na uygun.

---

## Seviye 3 â€” BileÅŸen: `rendering` etkileÅŸim yolu

```mermaid
graph LR
    gd["GestureDetector"]
    sem["Semantics"]
    fad["FocusableActionDetector"]
    pol["SagaNodeInteractionPolicy"]
    h["SagaNodeInteractionHandler"]

    gd -->|"onTap â†’ emitTap"| pol
    pol -->|"canTap âœ…"| h
    gd -->|"onLongPress<br/>ğŸ”´ H3: kapÄ±dan geÃ§mez"| h
    sem -->|"onTap âœ…"| pol
    sem -.->|"ğŸ”´ H4: onLongPress yok"| h
    fad -->|"ActivateIntent âœ…"| pol
    fad -.->|"ğŸ”´ H4: ikincil eylem<br/>intent'i yok"| h
```

**Okuma:** Tek bir kutu (`SagaNodeInteractionPolicy`) tÃ¼m giriÅŸ yollarÄ±nÄ±n
kapÄ±sÄ± olmalÄ±. BugÃ¼n Ã¼Ã§ yoldan yalnÄ±z biri tam geÃ§iyor:

| GiriÅŸ yolu | Birincil eylem | Ä°kincil eylem |
|---|---|---|
| Dokunmatik | âœ… kapÄ±dan geÃ§er | ğŸ”´ kapÄ±dan geÃ§mez (H3) |
| Klavye | âœ… kapÄ±dan geÃ§er | ğŸ”´ **yol yok** (H4) |
| Ekran okuyucu | âœ… kapÄ±dan geÃ§er | ğŸ”´ **yol yok** (H4) |

| **Uzun basma politikası** | ✅ var | T-07 | ✅ |
yapÄ±lmasÄ±nÄ±n gerekÃ§esi bu diyagramda gÃ¶rÃ¼nÃ¼yor: aynÄ± kapÄ±nÄ±n Ã¼Ã§ kolu.

---

## GeniÅŸleme dikiÅŸleri karnesi

| DikiÅŸ | 1.0.0 | GÃ¶rev | Hedef |
|---|---|---|---|
| Seviye Ã¼retimi (`LevelGenerator`) | âœ… | â€” | âœ… |
| Ã‡izim (`SagaMapRenderer`, `nodeBuilder`) | âœ… | â€” | âœ… |
| KalÄ±cÄ±lÄ±k (`SagaProgressRepository`) | ğŸŸ¡ asimetrik | T-09 | âœ… |
| Tema Ã§Ã¶zÃ¼mÃ¼ (`SagaBiomeThemeResolver`) | âœ… | â€” | âœ… |
| DuyarlÄ±lÄ±k (`SagaResponsiveResolver`) | âœ… | â€” | âœ… |
| Ekran okuyucu etiketi (`semanticsLabelBuilder`) | âœ… | T-02 (varsayÄ±lan) | âœ… |
| **Boss kuralÄ±** | ğŸ”´ yok | T-04 | âœ… |
| **Loot tablosu** | ğŸ”´ yok | T-04 | âœ… |
| **Biyom listesi** | ğŸ”´ yok | T-11 | âœ… |
| **Ä°lerleme verisi** | ğŸ”´ yok | T-03 | âœ… |
| **Kilit aÃ§ma kuralÄ±** | ğŸ”´ yok | T-06 | âœ… |
| **UlaÅŸÄ±labilirlik (kapÄ±)** | ğŸ”´ yok | T-06 | âœ… |
| **Uzun basma politikası** | ✅ var | T-07 | ✅ |
| **Chunk baÄŸlamÄ± (dekor/baÅŸlÄ±k)** | ğŸ”´ yok | T-05 | âœ… |
| **Chunk olaylarÄ±** | ğŸ”´ yok | T-15 | âœ… |

**14 dikiÅŸin 6'sÄ± var, 8'i yok.** Var olanlarÄ±n hepsi *Ã§izim ve altyapÄ±*
tarafÄ±nda; olmayanlarÄ±n hepsi *alan kuralÄ±* tarafÄ±nda. YapÄ±lacaklar listesinin
tamamÄ± bu tek asimetriyi kapatmaktan ibaret.

---

## DiyagramlarÄ± gÃ¼ncel tutmak

Bu dosyadaki diyagramlar mermaid; Markdown iÃ§inde canlÄ± kalÄ±rlar ve ayrÄ± bir
araÃ§ gerektirmezler. PlantUML/C4-PlantUML tercih edilirse iskeleti
`software-architecture-skills/tools/arch_tools.py init-c4` Ã¼retiyor.

**BakÄ±m kuralÄ±:** bir gÃ¶rev tamamlandÄ±ÄŸÄ±nda "geniÅŸleme dikiÅŸleri karnesi"
tablosundaki satÄ±r gÃ¼ncellenir. Karne yeÅŸile dÃ¶ndÃ¼ÄŸÃ¼nde bu rapor arÅŸivlenebilir.


# saga_map example

This example demonstrates core `saga_map` capabilities:

- responsive map rendering (`MapChunkWidget`)
- infinite section loading (`SagaInfiniteMapView` + `SagaInfiniteMapController`)
- generator and progression demo (`SagaMapLevelGenerator`, `CompleteLevelUseCase`)
- the 2.1.0 economy: `SagaPityRule`, `executeAndPersist` into an injected
  `InventoryRepository`, `spendStars` paying a gate toll, and hard replays
  scored in `LevelProgress.starsByMode`

## Run

```bash
flutter pub get
flutter run
```

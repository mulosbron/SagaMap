import 'models/inventory_item.dart';

/// A bad-luck guarantee for boss rewards.
///
/// Once [threshold] boss rewards in a row have come up below
/// [guaranteedRarity], the next roll is drawn only from the entries of
/// [guaranteedRarity] or better. At the default table's 75% common rate, ten
/// commons in a row happen to roughly one player in eighteen. On a long map
/// that is a certainty for somebody, and that player concludes the chest is
/// broken.
///
/// The counter lives with the host (it is save data); the rule lives here so
/// every consumer applies the same one. Keep the counter wherever the rest of
/// the save goes — `SagaProgress.extra` is the obvious place — pass it to
/// `CompleteLevelUseCase.execute` as `pityCounter`, and store [nextCounter]
/// after every boss reward.
///
/// Rarity is ordered by [InventoryRarity]'s declaration: `common`, then
/// `rare`, then `legendary`.
class SagaPityRule {
  const SagaPityRule({
    this.threshold = 10,
    this.guaranteedRarity = InventoryRarity.rare,
  }) : assert(threshold > 0, 'threshold must be greater than 0');

  /// How many rewards below [guaranteedRarity] in a row make the next roll a
  /// guaranteed one. Must be greater than `0`.
  ///
  /// A `const` constructor cannot throw, so the check that survives a release
  /// build runs where the rule is applied: [isDue] throws an [ArgumentError]
  /// for a threshold of `0` or less, matching how a malformed loot table is
  /// refused at roll time.
  final int threshold;

  /// The lowest rarity a guaranteed roll may produce.
  final InventoryRarity guaranteedRarity;

  /// Whether a roll made with [pityCounter] is a guaranteed one.
  bool isDue(int pityCounter) {
    if (threshold <= 0) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'Must be greater than 0.',
      );
    }
    return pityCounter >= threshold;
  }

  /// Whether a reward of [rarity] meets the guarantee.
  bool satisfies(InventoryRarity rarity) =>
      rarity.index >= guaranteedRarity.index;

  /// The counter to store after a boss reward of [rolled] rarity.
  ///
  /// A reward that meets the guarantee resets it to `0` — whether pity forced
  /// it or luck did, since either way the drought is over — and anything else
  /// adds one. A negative counter, which only a tampered save can hold, counts
  /// from `0`.
  int nextCounter(int pityCounter, InventoryRarity rolled) {
    if (satisfies(rolled)) return 0;
    return (pityCounter < 0 ? 0 : pityCounter) + 1;
  }
}

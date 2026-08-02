import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../engine/render/palette.dart';
import 'design.dart';

/// One purchasable cosmetic.
///
/// Everything in the shop is bought with coins earned by playing. There are no
/// real-money purchases and nothing here touches gameplay â€” the brief is
/// explicit that the shop sells cosmetics only.
class Cosmetic {
  const Cosmetic(
    this.id,
    this.slot,
    this.name,
    this.price,
    this.colours, {
    this.description = '',
  });

  final String id;
  final String slot;
  final String name;
  final int price;

  /// Material slot -> ARGB. Applied to the model at load time.
  final Map<int, int> colours;
  final String description;

  bool get isDefault => price == 0;
}

class ShopCatalogue {
  const ShopCatalogue._();

  static int _c(Color c) => Toy.argb(c);

  static final List<Cosmetic> all = <Cosmetic>[
    // ---- cannon skins -------------------------------------------------
    Cosmetic(
      'cannon_default',
      'cannon',
      'Sky Blue',
      0,
      const <int, int>{},
      description: 'The original',
    ),
    Cosmetic('cannon_sunset', 'cannon', 'Sunset', 120, <int, int>{
      0: _c(Toy.orange),
      1: _c(Toy.yellowLight),
      2: _c(Toy.redDark),
    }),
    Cosmetic('cannon_mint', 'cannon', 'Mint', 120, <int, int>{
      0: _c(Toy.greenLight),
      1: _c(Toy.white),
      2: _c(Toy.greenDark),
    }),
    Cosmetic('cannon_grape', 'cannon', 'Grape', 180, <int, int>{
      0: _c(Toy.purple),
      1: _c(Toy.pink),
      2: _c(Toy.blueDark),
    }),

    // ---- car skins ----------------------------------------------------
    Cosmetic('car_default', 'car', 'Taxi Yellow', 0, const <int, int>{}),
    Cosmetic('car_racer', 'car', 'Racer Red', 100, <int, int>{
      0: _c(Toy.red),
      3: _c(Toy.yellowLight),
    }),
    Cosmetic('car_police', 'car', 'Patrol', 140, <int, int>{
      0: _c(Toy.blue),
      3: _c(Toy.white),
    }),
    Cosmetic('car_lime', 'car', 'Lime', 100, <int, int>{0: _c(Toy.green)}),

    // ---- ball skins ---------------------------------------------------
    Cosmetic('ball_default', 'ball', 'Classic Yellow', 0, const <int, int>{}),
    Cosmetic('ball_cherry', 'ball', 'Cherry', 80, <int, int>{0: _c(Toy.red)}),
    Cosmetic('ball_ocean', 'ball', 'Ocean', 80, <int, int>{0: _c(Toy.cyan)}),
    Cosmetic('ball_violet', 'ball', 'Violet', 130, <int, int>{
      0: _c(Toy.purple),
    }),

    // ---- domino colour sets -------------------------------------------
    Cosmetic(
      'domino_default',
      'domino',
      'Toy Primaries',
      0,
      const <int, int>{},
    ),
    Cosmetic('domino_pastel', 'domino', 'Pastel Set', 150, <int, int>{
      0: _c(Toy.pink),
    }, description: 'Softer domino palette'),
    Cosmetic('domino_mono', 'domino', 'Monochrome', 150, <int, int>{
      0: _c(Toy.greyDeep),
    }, description: 'Slate and white'),

    // ---- celebration effects ------------------------------------------
    Cosmetic(
      'confetti_default',
      'celebration',
      'Confetti',
      0,
      const <int, int>{},
    ),
    Cosmetic(
      'confetti_gold',
      'celebration',
      'Gold Rush',
      200,
      const <int, int>{},
      description: 'Golden burst on completion',
    ),
    Cosmetic(
      'confetti_stars',
      'celebration',
      'Star Shower',
      220,
      const <int, int>{},
      description: 'Stars instead of strips',
    ),

    // ---- city decorations ---------------------------------------------
    Cosmetic(
      'deco_trees',
      'city',
      'Extra Trees',
      90,
      const <int, int>{},
      description: 'More greenery in your Toy City',
    ),
    Cosmetic('deco_lamps', 'city', 'Street Lamps', 90, const <int, int>{}),
    Cosmetic('deco_balloons', 'city', 'Balloon Arch', 160, const <int, int>{}),
  ];

  static List<Cosmetic> forSlot(String slot) =>
      all.where((Cosmetic c) => c.slot == slot).toList(growable: false);

  static Cosmetic? byId(String id) {
    for (final Cosmetic c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static const List<(String, String, IconData)> slots =
      <(String, String, IconData)>[
        ('cannon', 'Cannons', Icons.rocket_launch_rounded),
        ('car', 'Cars', Icons.directions_car_rounded),
        ('ball', 'Balls', Icons.sports_baseball_rounded),
        ('domino', 'Dominoes', Icons.view_week_rounded),
        ('celebration', 'Celebrations', Icons.celebration_rounded),
        ('city', 'City Decor', Icons.park_rounded),
      ];
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final SaveService save = SaveService.instance;
    final (String slot, String title, IconData _) = ShopCatalogue.slots[_tab];
    final List<Cosmetic> items = ShopCatalogue.forSlot(slot);

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s2),
                child: Row(
                  children: <Widget>[
                    ToyIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () {
                        AudioService.instance.uiTap();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: D.s3),
                    Expanded(
                      child: Text('Shop', style: D.title(Toy.inkStrong)),
                    ),
                    ToyChip(
                      icon: Icons.monetization_on_rounded,
                      value: '${save.coins}',
                      colour: Toy.yellowDark,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: D.s4),
                  itemCount: ShopCatalogue.slots.length,
                  separatorBuilder: (BuildContext _, int _) =>
                      const SizedBox(width: D.s2),
                  itemBuilder: (BuildContext ctx, int i) {
                    final bool on = i == _tab;
                    return GestureDetector(
                      onTap: () {
                        AudioService.instance.uiTap();
                        setState(() => _tab = i);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: D.s4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? Toy.blue : Toy.white,
                          borderRadius: BorderRadius.circular(D.rPill),
                          boxShadow: D.chip,
                        ),
                        child: Text(
                          ShopCatalogue.slots[i].$2,
                          style: D.label(on ? Toy.white : Toy.inkSoft),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(D.s4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: D.s3,
                    mainAxisSpacing: D.s3,
                    childAspectRatio: 0.94,
                  ),
                  itemCount: items.length,
                  itemBuilder: (BuildContext ctx, int i) =>
                      _Item(item: items[i], onChanged: () => setState(() {})),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(D.s5, 0, D.s5, D.s4),
                child: Text(
                  'Everything here is cosmetic and bought with coins you earn '
                  'by playing. No real-money purchases.',
                  style: D.tiny(Toy.inkSoft),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item, required this.onChanged});
  final Cosmetic item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final SaveService save = SaveService.instance;
    final bool owned = save.ownedCosmetics.contains(item.id);
    final bool equipped = save.equipped[item.slot] == item.id;
    final Color swatch = item.colours.isEmpty
        ? Toy.blue
        : Color(item.colours.values.first);

    return ToyCard(
      padding: const EdgeInsets.all(D.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: swatch.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(D.rMd),
              ),
              alignment: Alignment.center,
              child: Icon(
                equipped ? Icons.check_circle_rounded : Icons.palette_rounded,
                size: 34,
                color: equipped ? Toy.green : swatch,
              ),
            ),
          ),
          const SizedBox(height: D.s2),
          Text(item.name, style: D.label(Toy.inkStrong), maxLines: 1),
          if (item.description.isNotEmpty)
            Text(item.description, style: D.tiny(Toy.inkSoft), maxLines: 1),
          const SizedBox(height: D.s2),
          SizedBox(
            height: 36,
            child: equipped
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Toy.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(D.rMd),
                    ),
                    child: Text('Equipped', style: D.tiny(Toy.greenDark)),
                  )
                : GestureDetector(
                    onTap: () async {
                      if (owned) {
                        AudioService.instance.uiTap();
                        await save.equip(item.slot, item.id);
                      } else {
                        final bool ok = await save.buy(item.id, item.price);
                        AudioService.instance.play(
                          ok ? 'star_reward' : 'ui_tap',
                          volume: 0.8,
                        );
                        if (ok) await save.equip(item.slot, item.id);
                      }
                      onChanged();
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: owned
                            ? Toy.blue
                            : (save.canAfford(item.price)
                                  ? Toy.yellow
                                  : Toy.grey),
                        borderRadius: BorderRadius.circular(D.rMd),
                      ),
                      child: owned
                          ? Text('Equip', style: D.tiny(Toy.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const Icon(
                                  Icons.monetization_on_rounded,
                                  size: 14,
                                  color: Toy.inkStrong,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${item.price}',
                                  style: D.tiny(Toy.inkStrong),
                                ),
                              ],
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

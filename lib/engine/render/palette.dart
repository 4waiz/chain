import 'dart:ui' show Color;

/// The official Chain Reaction City colour palette.
///
/// Every value here was sampled from `logo.png`, which is the project art
/// bible. Nothing in the game should introduce a colour that is not derived
/// from this file — that is what keeps the whole product looking like one
/// coherent toy set photographed in a bright white studio.
class Toy {
  const Toy._();

  // ---------------------------------------------------------------- studio
  /// The studio backdrop. Very light neutral grey, never pure white, so that
  /// white props (bumpers, windows, flags) still read against it.
  static const Color studio = Color(0xFFF2F2F3);
  static const Color studioDeep = Color(0xFFE8E9EB);
  static const Color studioLift = Color(0xFFFAFAFB);

  /// Soft slate used for the wordmark and all primary text.
  static const Color ink = Color(0xFF7C8494);
  static const Color inkStrong = Color(0xFF5C6474);
  static const Color inkSoft = Color(0xFFA6ADBA);

  // ------------------------------------------------------------ primaries
  static const Color red = Color(0xFFE8453C);
  static const Color redDark = Color(0xFFC4342C);
  static const Color redLight = Color(0xFFF26A62);

  static const Color yellow = Color(0xFFF5C518);
  static const Color yellowDark = Color(0xFFD9A806);
  static const Color yellowLight = Color(0xFFFFD84A);

  static const Color blue = Color(0xFF2A7FD4);
  static const Color blueDark = Color(0xFF1F63A8);
  static const Color blueLight = Color(0xFF5BA3E8);

  static const Color green = Color(0xFF3DAE55);
  static const Color greenDark = Color(0xFF2E8A42);
  static const Color greenLight = Color(0xFF63C878);

  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF4F5F6);
  static const Color grey = Color(0xFFC9CBCD);
  static const Color greyDark = Color(0xFF9AA0A6);
  static const Color greyDeep = Color(0xFF6E747A);

  // ------------------------------------------------------- cannon (hero)
  /// The cannon in the logo is a lighter, friendlier cyan-blue than the
  /// domino blue, with a noticeably darker blue for its wheels and cradle.
  static const Color cannonBody = Color(0xFF6EC6E8);
  static const Color cannonBodyLight = Color(0xFF93D8F2);
  static const Color cannonMount = Color(0xFF3B7FB5);
  static const Color cannonWheel = Color(0xFF2F6B9E);
  static const Color fuse = Color(0xFF8A5A3C);

  // ------------------------------------------------------------- accents
  static const Color orange = Color(0xFFF2882E);
  static const Color purple = Color(0xFF8B5FCF);
  static const Color cyan = Color(0xFF35BFD4);
  static const Color pink = Color(0xFFEF6EA8);

  // ------------------------------------------------------------ material
  static const Color tyre = Color(0xFF33383D);
  static const Color metal = Color(0xFFB6BCC4);
  static const Color wood = Color(0xFFC98A4B);
  static const Color water = Color(0xFF57B7E8);
  static const Color waterDeep = Color(0xFF2E8FC4);

  /// Ordered list used by cosmetics, level authoring and celebration pieces.
  static const List<Color> confetti = <Color>[
    red,
    yellow,
    blue,
    green,
    orange,
    cyan,
    purple,
    pink,
  ];

  /// Packed 0xAARRGGBB values, which is the form the software rasteriser and
  /// the GLB loader both work in.
  static int argb(Color c) =>
      (((c.a * 255.0).round() & 0xff) << 24) |
      (((c.r * 255.0).round() & 0xff) << 16) |
      (((c.g * 255.0).round() & 0xff) << 8) |
      ((c.b * 255.0).round() & 0xff);
}

import 'package:flutter/material.dart';

import '../../data/audio_service.dart';
import '../../data/save_service.dart';
import '../../data/settings.dart';
import '../../engine/render/palette.dart';
import 'design.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final Settings s = Settings.instance;

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _Header(title: 'Settings', onBack: () => Navigator.pop(context)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s7),
                  children: <Widget>[
                    _Section(
                      title: 'Audio',
                      children: <Widget>[
                        _Toggle(
                          icon: Icons.volume_up_rounded,
                          label: 'Sound effects',
                          value: s.sound,
                          onChanged: (bool v) => setState(() => s.sound = v),
                        ),
                        _Toggle(
                          icon: Icons.music_note_rounded,
                          label: 'Music',
                          value: s.music,
                          onChanged: (bool v) {
                            setState(() => s.music = v);
                            AudioService.instance.syncMusic();
                          },
                        ),
                        _Toggle(
                          icon: Icons.vibration_rounded,
                          label: 'Haptics',
                          value: s.haptics,
                          onChanged: (bool v) => setState(() => s.haptics = v),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Motion',
                      children: <Widget>[
                        _Toggle(
                          icon: Icons.accessibility_new_rounded,
                          label: 'Reduced motion',
                          subtitle: 'Calmer camera, no shake, softer lighting',
                          value: s.reducedMotion,
                          onChanged: (bool v) =>
                              setState(() => s.reducedMotion = v),
                        ),
                        _Toggle(
                          icon: Icons.vibration_rounded,
                          label: 'Camera shake',
                          value: s.cameraShake,
                          enabled: !s.reducedMotion,
                          onChanged: (bool v) =>
                              setState(() => s.cameraShake = v),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Graphics',
                      children: <Widget>[
                        _QualityPicker(
                          value: s.quality,
                          onChanged: (GraphicsQuality q) =>
                              setState(() => s.quality = q),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Privacy',
                      children: <Widget>[
                        const _Info(
                          icon: Icons.lock_rounded,
                          label: 'Fully offline',
                          subtitle:
                              'Chain Reaction City collects nothing, sends nothing, '
                              'and needs no network permission. All progress stays '
                              'on this device.',
                        ),
                        const _Info(
                          icon: Icons.shopping_bag_rounded,
                          label: 'Purchases',
                          subtitle:
                              'The shop sells cosmetics for coins earned by playing. '
                              'There are no real-money purchases, so there is nothing '
                              'to restore.',
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Progress',
                      children: <Widget>[
                        _Danger(
                          label: 'Reset all progress',
                          onConfirm: () async {
                            await SaveService.instance.resetAll();
                            if (context.mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: D.s4),
                    Center(
                      child: Text(
                        'Chain Reaction City  Â·  v1.0.0',
                        style: D.tiny(Toy.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(D.s4, D.s3, D.s4, D.s2),
      child: Row(
        children: <Widget>[
          ToyIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: () {
              AudioService.instance.uiTap();
              onBack();
            },
          ),
          const SizedBox(width: D.s3),
          Expanded(child: Text(title, style: D.title(Toy.inkStrong))),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: D.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: D.s3, bottom: D.s2),
            child: Text(title.toUpperCase(), style: D.tiny(Toy.inkSoft)),
          ),
          ToyCard(
            padding: const EdgeInsets.all(D.s2),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color c = enabled ? Toy.inkStrong : Toy.inkSoft;
    final String? sub = subtitle;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: D.s2, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 21, color: enabled ? Toy.blue : Toy.grey),
          const SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: D.body(c)),
                if (sub != null) Text(sub, style: D.tiny(Toy.inkSoft)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled
                ? (bool v) {
                    AudioService.instance.uiTap();
                    onChanged(v);
                  }
                : null,
            activeThumbColor: Toy.white,
            activeTrackColor: Toy.green,
            inactiveThumbColor: Toy.white,
            inactiveTrackColor: Toy.grey,
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.icon,
    required this.label,
    required this.subtitle,
  });
  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(D.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 21, color: Toy.green),
          const SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: D.body(Toy.inkStrong)),
                const SizedBox(height: 2),
                Text(subtitle, style: D.tiny(Toy.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityPicker extends StatelessWidget {
  const _QualityPicker({required this.value, required this.onChanged});
  final GraphicsQuality value;
  final ValueChanged<GraphicsQuality> onChanged;

  static const Map<GraphicsQuality, String> _labels = <GraphicsQuality, String>{
    GraphicsQuality.low: 'Low',
    GraphicsQuality.medium: 'Medium',
    GraphicsQuality.high: 'High',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(D.s2),
      child: Row(
        children: <Widget>[
          const Icon(Icons.tune_rounded, size: 21, color: Toy.blue),
          const SizedBox(width: D.s3),
          Expanded(child: Text('Quality', style: D.body(Toy.inkStrong))),
          for (final GraphicsQuality q in GraphicsQuality.values)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () {
                  AudioService.instance.uiTap();
                  onChanged(q);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: q == value ? Toy.blue : Toy.studio,
                    borderRadius: BorderRadius.circular(D.rPill),
                  ),
                  child: Text(
                    _labels[q]!,
                    style: D.tiny(q == value ? Toy.white : Toy.inkSoft),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Danger extends StatelessWidget {
  const _Danger({required this.label, required this.onConfirm});
  final String label;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(D.s2),
      child: Row(
        children: <Widget>[
          const Icon(Icons.restart_alt_rounded, size: 21, color: Toy.red),
          const SizedBox(width: D.s3),
          Expanded(child: Text(label, style: D.body(Toy.inkStrong))),
          TextButton(
            onPressed: () async {
              AudioService.instance.uiTap();
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  backgroundColor: Toy.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(D.rLg),
                  ),
                  title: Text(
                    'Reset everything?',
                    style: D.heading(Toy.inkStrong),
                  ),
                  content: Text(
                    'Stars, coins, cosmetics and your Toy City will all be '
                    'cleared. This cannot be undone.',
                    style: D.body(Toy.inkSoft),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: D.label(Toy.inkSoft)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Reset', style: D.label(Toy.red)),
                    ),
                  ],
                ),
              );
              if (ok == true) await onConfirm();
            },
            child: Text('Reset', style: D.label(Toy.red)),
          ),
        ],
      ),
    );
  }
}

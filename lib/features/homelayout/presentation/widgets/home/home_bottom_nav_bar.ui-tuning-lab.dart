// UI tuning lab for the home bottom tab bar. Debug builds only: every
// reference from production code sits inside `if (kDebugMode)`.
// The marker in the file name is what the lab's naming rule requires.
// ignore_for_file: file_names
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../../core/utils/app_colors.dart';
import '../../../../../core/utils/assets.dart';
import '../../../../../core/utils/extensions/context_extensions.dart';
import '../../../../../core/utils/screen_util_like.dart';

// ---------------------------------------------------------------------------
// Agent path: flutter run --dart-define=UITUNINGLAB_NAV_OPEN=true (in CI: the
// `dart_defines` input of cloud-run.yml). Honored once per isolate.
// ---------------------------------------------------------------------------
const bool _uiTuningLabOpenRequested = bool.fromEnvironment(
  'UITUNINGLAB_NAV_OPEN',
);
bool _uiTuningLabLaunchConsumed = false;

bool uiTuningLabNavConsumeRequest() {
  if (_uiTuningLabLaunchConsumed) return false;
  _uiTuningLabLaunchConsumed = true;
  return _uiTuningLabOpenRequested;
}

// ---------------------------------------------------------------------------
// Configuration. `original` is the production bar and the baseline; the other
// designs are built below and start from their own defaults.
//   cornerRadius: floating = bar radius, lifted = top-corner radius.
//   inset:        floating = side/bottom margin, indicator = line thickness,
//                 lifted = how far the active bubble rises above the bar.
// ---------------------------------------------------------------------------
@immutable
class UITuningLabNavStyle {
  const UITuningLabNavStyle({
    this.design = 'original',
    this.cornerRadius = 28,
    this.inset = 12,
    this.accent = 'brand',
    this.motionMs = 280,
  });

  final String design;
  final double cornerRadius;
  final double inset;
  final String accent; // 'brand' (green light / gold dark) | 'gold'
  final double motionMs; // 0 = no animation

  UITuningLabNavStyle copyWith({
    double? cornerRadius,
    double? inset,
    String? accent,
    double? motionMs,
  }) => UITuningLabNavStyle(
    design: design,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    inset: inset ?? this.inset,
    accent: accent ?? this.accent,
    motionMs: motionMs ?? this.motionMs,
  );
}

const _baseline = UITuningLabNavStyle(design: 'original');

const _defaults = <String, UITuningLabNavStyle>{
  'original': _baseline,
  'floating': UITuningLabNavStyle(
    design: 'floating',
    cornerRadius: 28,
    inset: 12,
  ),
  'indicator': UITuningLabNavStyle(
    design: 'indicator',
    cornerRadius: 0,
    inset: 3,
  ),
  'lifted': UITuningLabNavStyle(design: 'lifted', cornerRadius: 28, inset: 14),
};

const _designLabels = <String, String>{
  'original': 'Original',
  'floating': 'Floating',
  'indicator': 'Indicator',
  'lifted': 'Lifted',
};

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const _presets = <String, UITuningLabNavStyle>{
  'floating-gold': UITuningLabNavStyle(
    design: 'floating',
    cornerRadius: 32,
    inset: 16,
    accent: 'gold',
  ),
  'floating-tight': UITuningLabNavStyle(
    design: 'floating',
    cornerRadius: 20,
    inset: 6,
  ),
  'indicator-bold': UITuningLabNavStyle(
    design: 'indicator',
    cornerRadius: 0,
    inset: 5,
    accent: 'gold',
  ),
  'lifted-high': UITuningLabNavStyle(
    design: 'lifted',
    cornerRadius: 28,
    inset: 20,
    accent: 'gold',
  ),
};

// The diff against the selected design's defaults, plus the design itself.
Map<String, Object> _values(UITuningLabNavStyle s) {
  if (s.design == 'original') return <String, Object>{};
  final b = _defaults[s.design] ?? _baseline;
  return <String, Object>{
    'design': s.design,
    if (s.cornerRadius != b.cornerRadius) 'cornerRadius': s.cornerRadius,
    if (s.inset != b.inset) 'inset': s.inset,
    if (s.accent != b.accent) 'accent': s.accent,
    if (s.motionMs != b.motionMs) 'motionMs': s.motionMs,
  };
}

UITuningLabNavStyle _fromValues(Map<String, Object> v) {
  final design = v['design'] as String? ?? 'original';
  final b = _defaults[design] ?? _baseline;
  return UITuningLabNavStyle(
    design: design,
    cornerRadius: (v['cornerRadius'] as num?)?.toDouble() ?? b.cornerRadius,
    inset: (v['inset'] as num?)?.toDouble() ?? b.inset,
    accent: v['accent'] as String? ?? b.accent,
    motionMs: (v['motionMs'] as num?)?.toDouble() ?? b.motionMs,
  );
}

// JSON with sorted keys and two-decimal rounding; whole numbers print as 12.
String _sortedJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_sortedJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_sortedJson).join(',')}]';
  if (v is double) {
    final r = (v * 100).round() / 100;
    return r == r.truncateToDouble() ? r.toInt().toString() : r.toString();
  }
  return jsonEncode(v);
}

void _log(String tag, Object? payload) {
  if (kDebugMode) debugPrint('$tag ${_sortedJson(payload)}');
}

// Temporary file, then rename: a reader never sees half a pick.
Future<void> _uiTuningLabWriteResult(Map<String, Object?> done) async {
  final dir = await Directory(
    '${(await getApplicationSupportDirectory()).path}/.ui-tuning-lab',
  ).create(recursive: true);
  final temp = File('${dir.path}/nav-result.json.tmp');
  await temp.writeAsString(
    _sortedJson({...done, 'savedAt': DateTime.now().toUtc().toIso8601String()}),
    flush: true,
  );
  await temp.rename('${dir.path}/nav-result.json');
}

class _Candidate {
  const _Candidate(this.name, this.basedOn, this.values);
  final String name;
  final String basedOn;
  final Map<String, Object> values;
  Map<String, Object> toJson() => {
    'basedOn': basedOn,
    'name': name,
    'values': values,
  };
}

// ---------------------------------------------------------------------------
// Shared helpers for the designs.
// ---------------------------------------------------------------------------
typedef _Item = ({String icon, String label});

List<_Item> _items(BuildContext c) => [
  (icon: Assets.homeNavBarIcon, label: c.strings.navHome),
  (icon: Assets.quranNavBarIcon, label: c.strings.navQuran),
  (icon: Assets.azkharNavBarIcon, label: c.strings.navAthkar),
  (icon: Assets.occasionsNavBarIcon, label: c.strings.navOccasions),
  (icon: Assets.moreNavBarIcon, label: c.strings.navMore),
];

Duration _dur(BuildContext c, UITuningLabNavStyle s) =>
    MediaQuery.disableAnimationsOf(c)
    ? Duration.zero
    : Duration(milliseconds: s.motionMs.round());

class _Pal {
  const _Pal({
    required this.surface,
    required this.border,
    required this.inactive,
    required this.fill,
    required this.on,
    required this.label,
    required this.line,
    required this.cutout,
  });

  factory _Pal.of(BuildContext context, String accent) {
    final d = context.isDark;
    final gold = accent == 'gold';
    final fill = gold || d ? AppColors.accentGold : AppColors.primaryDark;
    return _Pal(
      surface: d ? AppColors.darkSurface : AppColors.lightSurface,
      border: d
          ? AppColors.darkBorderUnselected
          : AppColors.lightBorderUnselected,
      // Secondary (not muted) text: the original's muted grey is below 4.5:1.
      inactive: d ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      fill: fill,
      on: fill == AppColors.accentGold
          ? AppColors.primaryDarkHeader
          : AppColors.white,
      label: d ? AppColors.accentGold : AppColors.primaryDark,
      line: d
          ? AppColors.accentGold
          : (gold ? AppColors.accentGoldDark : AppColors.primaryDark),
      cutout: Theme.of(context).scaffoldBackgroundColor,
    );
  }

  final Color surface;
  final Color border;
  final Color inactive; // unselected icon and label
  final Color fill; // active fill
  final Color on; // icon/label on the active fill
  final Color label; // selected label/icon on the plain surface
  final Color line; // the indicator line
  final Color cutout; // ring around the lifted bubble
}

/// One tappable tab cell: full-cell hit area, press feedback, and semantics.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.radius = 16,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.path,
    required this.color,
    required this.size,
    required this.duration,
  });
  final String path;
  final Color color;
  final double size;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: duration,
      builder: (context, c, _) => SvgPicture.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(c ?? color, BlendMode.srcIn),
      ),
    );
  }
}

class _NavLabel extends StatelessWidget {
  const _NavLabel({
    required this.text,
    required this.color,
    required this.selected,
    required this.duration,
  });
  final String text;
  final Color color;
  final bool selected;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final base = context.textTheme.bodySmall ?? const TextStyle();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedDefaultTextStyle(
        duration: duration,
        style: base.copyWith(
          color: color,
          fontSize: 11.sp,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        child: Text(text, maxLines: 1),
      ),
    );
  }
}

// Position of cell `index` in a row of `n`, for AnimatedAlign. The bars are
// forced right-to-left (as in production), and AlignmentDirectional mirrors.
AlignmentDirectional _slot(int index, int n) =>
    AlignmentDirectional(-1 + 2 * index / (n - 1), 0);

// ---------------------------------------------------------------------------
// Design 1: Floating. A detached rounded bar with a shadow; one filled tile
// slides behind the active tab, and every tab keeps its label.
// ---------------------------------------------------------------------------
class UITuningLabNavFloating extends StatelessWidget {
  const UITuningLabNavFloating({
    super.key,
    required this.style,
    required this.currentIndex,
    required this.onTabSelected,
  });
  final UITuningLabNavStyle style;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context, style.accent);
    final items = _items(context);
    final n = items.length;
    final dur = _dur(context, style);
    final m = style.inset.clamp(0.0, 24.0).toDouble();
    final r = style.cornerRadius.clamp(8.0, 36.0).toDouble();
    final tileRadius = (r - 5).clamp(6.0, 36.0).toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(m, 6, m, m < 6 ? 6 : m),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: pal.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    alignment: _slot(currentIndex, n),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: pal.fill,
                            borderRadius: BorderRadius.circular(tileRadius),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _Cell(
                            label: items[i].label,
                            selected: i == currentIndex,
                            onTap: () => onTabSelected(i),
                            radius: tileRadius,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _NavIcon(
                                  path: items[i].icon,
                                  color: i == currentIndex
                                      ? pal.on
                                      : pal.inactive,
                                  size: 24,
                                  duration: dur,
                                ),
                                const SizedBox(height: 3),
                                _NavLabel(
                                  text: items[i].label,
                                  color: i == currentIndex
                                      ? pal.on
                                      : pal.inactive,
                                  selected: i == currentIndex,
                                  duration: dur,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design 2: Indicator. A flat, quiet bar: a thin line slides along the top
// edge over the active tab, which also gets a soft wash and a slightly larger
// icon. The lightest change from the original.
// ---------------------------------------------------------------------------
class UITuningLabNavIndicator extends StatelessWidget {
  const UITuningLabNavIndicator({
    super.key,
    required this.style,
    required this.currentIndex,
    required this.onTabSelected,
  });
  final UITuningLabNavStyle style;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context, style.accent);
    final items = _items(context);
    final n = items.length;
    final dur = _dur(context, style);
    final t = style.inset.clamp(2.0, 8.0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(top: BorderSide(color: pal.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: dur,
                    curve: Curves.easeOutCubic,
                    alignment: _slot(currentIndex, n),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              pal.line.withValues(alpha: 0.14),
                              pal.line.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: 40,
                            height: t,
                            decoration: BoxDecoration(
                              color: pal.line,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(t),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _Cell(
                            label: items[i].label,
                            selected: i == currentIndex,
                            onTap: () => onTabSelected(i),
                            radius: 8,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedScale(
                                  scale: i == currentIndex ? 1.12 : 1,
                                  duration: dur,
                                  curve: Curves.easeOutBack,
                                  child: _NavIcon(
                                    path: items[i].icon,
                                    color: i == currentIndex
                                        ? pal.label
                                        : pal.inactive,
                                    size: 24,
                                    duration: dur,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _NavLabel(
                                  text: items[i].label,
                                  color: i == currentIndex
                                      ? pal.label
                                      : pal.inactive,
                                  selected: i == currentIndex,
                                  duration: dur,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design 3: Lifted. The bar has rounded top corners; the active icon rises
// out of it in a filled bubble ringed by the screen background.
// ---------------------------------------------------------------------------
class UITuningLabNavLifted extends StatelessWidget {
  const UITuningLabNavLifted({
    super.key,
    required this.style,
    required this.currentIndex,
    required this.onTabSelected,
  });
  final UITuningLabNavStyle style;
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  static const double _barH = 64;
  static const double _maxLift = 20;
  static const double _bubble = 48;

  @override
  Widget build(BuildContext context) {
    final pal = _Pal.of(context, style.accent);
    final items = _items(context);
    final n = items.length;
    final dur = _dur(context, style);
    final lift = style.inset.clamp(10.0, _maxLift).toDouble();
    final r = style.cornerRadius.clamp(0.0, 36.0).toDouble();

    return SafeArea(
      top: false,
      child: SizedBox(
        height: _barH + _maxLift,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(r)),
                  border: Border(top: BorderSide(color: pal.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _Cell(
                          label: items[i].label,
                          selected: i == currentIndex,
                          onTap: () => onTabSelected(i),
                          radius: 20,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedPositioned(
                                duration: dur,
                                curve: Curves.easeOutBack,
                                top: i == currentIndex
                                    ? _maxLift - lift
                                    : _maxLift + 10,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: dur,
                                    curve: Curves.easeOutCubic,
                                    width: i == currentIndex ? _bubble : 28,
                                    height: i == currentIndex ? _bubble : 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: i == currentIndex
                                          ? pal.fill
                                          : Colors.transparent,
                                      border: i == currentIndex
                                          ? Border.all(
                                              color: pal.cutout,
                                              width: 4,
                                            )
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: _NavIcon(
                                      path: items[i].icon,
                                      color: i == currentIndex
                                          ? pal.on
                                          : pal.inactive,
                                      size: 24,
                                      duration: dur,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 2,
                                right: 2,
                                bottom: 7,
                                child: Center(
                                  child: _NavLabel(
                                    text: items[i].label,
                                    color: i == currentIndex
                                        ? pal.label
                                        : pal.inactive,
                                    selected: i == currentIndex,
                                    duration: dur,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _DesignBuilder =
    Widget Function(
      UITuningLabNavStyle style,
      int currentIndex,
      ValueChanged<int> onTabSelected,
    );
final Map<String, _DesignBuilder> _designs = {
  'floating': (s, i, t) => UITuningLabNavFloating(
    style: s,
    currentIndex: i,
    onTabSelected: t,
  ),
  'indicator': (s, i, t) => UITuningLabNavIndicator(
    style: s,
    currentIndex: i,
    onTabSelected: t,
  ),
  'lifted': (s, i, t) =>
      UITuningLabNavLifted(style: s, currentIndex: i, onTabSelected: t),
};

// ---------------------------------------------------------------------------
// Host: wraps only the tab bar. The pill and panel live in the app's Overlay,
// so they pin to the screen; the panel is built only while open and sits above
// the bar so the bar stays visible and tappable.
// ---------------------------------------------------------------------------
class UITuningLabNavHost extends StatefulWidget {
  const UITuningLabNavHost({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  /// The production bar, rendered whenever the design is `original`.
  final Widget child;

  @override
  State<UITuningLabNavHost> createState() => _UITuningLabNavHostState();
}

class _UITuningLabNavHostState extends State<UITuningLabNavHost> {
  UITuningLabNavStyle draft = _baseline;
  UITuningLabNavStyle? stash; // Now, while Original or a favorite is shown
  // Favorites the lab opens with; a later session seeds kept finalists here.
  final List<_Candidate> candidates = [];
  final Set<String> issued = {'draft', 'now', 'original', 'baseline'};
  final Set<String> logged = {};
  String basedOn = 'baseline';
  String? lastPreset;
  String shown = 'draft'; // "draft" (Now), "original", or a favorite's name
  String? status;
  String? result; // the last pick; while set, the panel is the result bar
  bool replaying = false;
  final portal = OverlayPortalController();
  bool isOpen = false;

  @override
  void initState() {
    super.initState();
    issued.addAll(candidates.map((c) => c.name));
    final requested = uiTuningLabNavConsumeRequest();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      portal.show(); // the pill; the panel is built only while isOpen
      if (requested) open();
    });
  }

  void update(VoidCallback change) => setState(change);

  void open() {
    if (isOpen) return;
    for (final c in candidates) {
      if (logged.add(c.name)) _log('UITUNINGLAB_CANDIDATE', c.toJson());
    }
    update(() {
      isOpen = true;
      status = null;
    });
  }

  void close() {
    show('draft');
    update(() => isOpen = false);
  }

  // Tapping a chip shows it on the real bar; Now is stashed meanwhile.
  void show(String target) {
    update(() {
      if (target == 'draft') {
        if (stash != null) draft = stash!;
        stash = null;
      } else {
        stash ??= draft;
        final c = candidates.where((c) => c.name == target).firstOrNull;
        draft = c == null ? _baseline : _fromValues(c.values);
      }
      shown = target;
    });
  }

  // Every control edits Now. Moved while a favorite is shown, it loads that
  // favorite into Now first; the favorite itself does not change.
  void edit(UITuningLabNavStyle next, [String? from]) {
    final source = from ?? (shown == 'draft' ? basedOn : shown);
    update(() {
      stash = null;
      draft = next;
      basedOn = source;
      shown = 'draft';
    });
  }

  void pickDesign(String key) {
    lastPreset = null;
    edit(_defaults[key] ?? _baseline);
  }

  void applyPreset(String name) {
    lastPreset = name;
    edit(_presets[name]!, name);
  }

  void reset() {
    lastPreset = null;
    edit(_baseline, 'baseline');
  }

  // Always reports Now, whichever chip is shown.
  Future<void> copyValues() async {
    final values = _values(stash ?? draft);
    final json = _sortedJson(values);
    _log('UITUNINGLAB_VALUES', values);
    await Clipboard.setData(ClipboardData(text: json));
    update(
      () => status = json == '{}' ? 'No changes from Original' : 'Copied $json',
    );
  }

  void keep() {
    final values = _values(draft);
    if (values.isEmpty) {
      update(() => status = 'Same as Original');
      return;
    }
    final same = candidates
        .where((c) => _sortedJson(c.values) == _sortedJson(values))
        .firstOrNull;
    if (same != null) {
      update(() => status = 'Same as ${same.name}');
      return;
    }
    final stem = draft.design != 'original'
        ? draft.design
        : (lastPreset ?? 'tweak');
    var name = stem;
    for (var i = 2; issued.contains(name); i++) {
      name = '$stem-$i';
    }
    final c = _Candidate(name, basedOn, values);
    issued.add(c.name);
    logged.add(c.name);
    _log('UITUNINGLAB_CANDIDATE', c.toJson());
    update(() {
      candidates.add(c);
      status = 'Kept as ${c.name}';
    });
  }

  void remove(String name) {
    if (shown == name) show('draft');
    _log('UITUNINGLAB_CANDIDATE_REMOVED', {'name': name});
    update(() => candidates.removeWhere((c) => c.name == name));
  }

  // Picks the shown chip and finishes. Picking again replaces the result.
  Future<void> useThis() async {
    final picked = candidates.where((c) => c.name == shown).firstOrNull;
    final winner =
        picked?.name ?? (shown == 'original' ? 'original' : 'draft');
    final values =
        picked?.values ??
        (shown == 'original' ? <String, Object>{} : _values(draft));
    final done = <String, Object?>{
      'candidates': [for (final c in candidates) c.toJson()],
      'values': values,
      'winner': winner,
    };
    _log('UITUNINGLAB_DONE', done);
    String? failure;
    try {
      await _uiTuningLabWriteResult(done);
    } catch (e) {
      failure = 'Result file failed: $e';
    }
    await Clipboard.setData(ClipboardData(text: 'land $winner'));
    update(() {
      result = winner;
      status = failure;
    });
  }

  // Steps through every tab and back, so the motion can be judged hands-free.
  Future<void> replay() async {
    if (replaying) return;
    final start = widget.currentIndex;
    update(() => replaying = true);
    final step = Duration(milliseconds: draft.motionMs.round() + 450);
    for (var i = 0; i < 5; i++) {
      if (i == start) continue;
      if (!mounted || !isOpen) break;
      widget.onTabSelected(i);
      await Future<void>.delayed(step);
    }
    if (mounted) {
      widget.onTabSelected(start);
      update(() => replaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final variant = _designs[draft.design];
    final body = variant != null
        ? variant(draft, widget.currentIndex, widget.onTabSelected)
        : widget.child;
    return OverlayPortal(
      controller: portal,
      overlayChildBuilder: (overlayContext) {
        final bottom = MediaQuery.paddingOf(overlayContext).bottom + 108;
        if (isOpen) {
          return result == null
              ? panel(overlayContext, bottom)
              : resultBar(result!, bottom);
        }
        return Positioned(
          right: 12,
          bottom: bottom,
          child: Semantics(
            label: 'Open UI tuning lab for the tab bar',
            button: true,
            excludeSemantics: true,
            child: FilledButton(onPressed: open, child: const Text('Tune nav')),
          ),
        );
      },
      child: body,
    );
  }

  Widget resultBar(String name, double bottom) {
    return Positioned(
      right: 12,
      bottom: bottom,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(liveRegion: true, child: Text('✓ Sent: $name')),
              TextButton(
                onPressed: () => update(() => result = null),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget slider(
    String label,
    double value,
    double max,
    int divisions,
    bool editable,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max).toDouble(),
            max: max,
            divisions: divisions,
            label: label,
            onChanged: editable
                ? (v) => onChanged((v * 100).round() / 100)
                : null,
          ),
        ),
        ExcludeSemantics(child: Text('${value.round()}')),
      ],
    );
  }

  Widget panel(BuildContext overlayContext, double bottom) {
    final editable = shown != 'original';
    final size = MediaQuery.sizeOf(overlayContext);
    // Phones: a near-full-width panel above the bar, at most 40% tall, so the
    // bar stays visible. Wider screens: a 340-wide corner panel.
    final compact = size.width < 600;
    final design = draft.design;
    final tunable = design != 'original';
    final hasRadius = design == 'floating' || design == 'lifted';
    final insetLabel = switch (design) {
      'floating' => 'Margin',
      'indicator' => 'Line',
      _ => 'Lift',
    };
    final insetMax = switch (design) {
      'floating' => 24.0,
      'indicator' => 8.0,
      _ => 20.0,
    };

    return Positioned(
      left: compact ? 8 : null,
      right: compact ? 8 : 16,
      bottom: bottom,
      width: compact ? null : 340,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: compact ? size.height * 0.40 : size.height - 200,
          ),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: const Text('UI tuning lab · tab bar'),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: (choice) {
                          if (choice == 'reset') {
                            reset();
                          } else {
                            copyValues();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'reset', child: Text('Reset')),
                          PopupMenuItem(
                            value: 'copy',
                            child: Text('Copy values'),
                          ),
                        ],
                      ),
                      TextButton(onPressed: close, child: const Text('Close')),
                    ],
                  ),
                  // The chips: Original, Now, then each favorite.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('Original'),
                        selected: shown == 'original',
                        onSelected: (_) => show('original'),
                      ),
                      ChoiceChip(
                        label: const Text('Now'),
                        selected: shown == 'draft',
                        onSelected: (_) => show('draft'),
                      ),
                      for (final c in candidates)
                        InputChip(
                          label: Text(c.name),
                          selected: shown == c.name,
                          onSelected: (_) => show(c.name),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          deleteButtonTooltipMessage: 'Remove ${c.name}',
                          onDeleted: () => remove(c.name),
                        ),
                    ],
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Design'),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final key in _designLabels.keys)
                                ChoiceChip(
                                  label: Text(_designLabels[key]!),
                                  selected: design == key,
                                  onSelected: editable
                                      ? (_) => pickDesign(key)
                                      : null,
                                ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final name in _presets.keys)
                                OutlinedButton(
                                  onPressed: editable
                                      ? () => applyPreset(name)
                                      : null,
                                  child: Text(name),
                                ),
                            ],
                          ),
                          if (tunable) ...[
                            if (hasRadius)
                              slider(
                                'Radius',
                                draft.cornerRadius,
                                36,
                                36,
                                editable,
                                (v) => edit(draft.copyWith(cornerRadius: v)),
                              ),
                            slider(
                              insetLabel,
                              draft.inset,
                              insetMax,
                              insetMax.toInt(),
                              editable,
                              (v) => edit(draft.copyWith(inset: v)),
                            ),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text('Accent'),
                                for (final a in const ['brand', 'gold'])
                                  ChoiceChip(
                                    label: Text(a),
                                    selected: draft.accent == a,
                                    onSelected: editable
                                        ? (_) => edit(draft.copyWith(accent: a))
                                        : null,
                                  ),
                              ],
                            ),
                            slider(
                              'Motion ms',
                              draft.motionMs,
                              600,
                              12,
                              editable,
                              (v) => edit(draft.copyWith(motionMs: v)),
                            ),
                          ] else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Original is the shipped bar: pick a design or a preset to tune.',
                              ),
                            ),
                          OutlinedButton(
                            onPressed: replaying ? null : replay,
                            child: Text(
                              replaying ? 'Replaying…' : 'Replay (step tabs)',
                            ),
                          ),
                          if (status != null)
                            Semantics(
                              liveRegion: true,
                              child: SelectableText(status!),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: shown == 'draft' ? keep : null,
                          child: const Text('★ Keep'),
                        ),
                        FilledButton(
                          onPressed: useThis,
                          child: const Text('✓ Use this'),
                        ),
                      ],
                    ),
                  ),
                  // Pinned below the controls, visible however long they grow.
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Keep favorites · Use this to finish'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

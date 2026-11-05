// UI tuning lab for the home "Prayer Times" list. Debug builds only: every
// reference from production code sits inside `if (kDebugMode)`.
// The marker in the file name is what the lab's naming rule requires.
// ignore_for_file: file_names
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/app_colors.dart';
import '../../../../../core/utils/extensions/context_extensions.dart';
import '../../../../../core/utils/screen_util_like.dart';
import '../../../data/models/prayer_time_model.dart';
import '../../../data/models/prayers_helper.dart';
import '../../bloc/homelayout_bloc.dart';
import '../../bloc/homelayout_event.dart';
import '../../bloc/homelayout_state.dart';
import '../prayer_times/prayer_type_icon_widget.dart';

// ---------------------------------------------------------------------------
// Agent path: flutter run --dart-define=UITUNINGLAB_OPEN=true (in CI: the
// `dart_defines` input of cloud-run.yml). Honored once per isolate.
// ---------------------------------------------------------------------------
const bool _uiTuningLabOpenRequested = bool.fromEnvironment('UITUNINGLAB_OPEN');
bool _uiTuningLabLaunchConsumed = false;

bool uiTuningLabConsumeRequest() {
  if (_uiTuningLabLaunchConsumed) return false;
  _uiTuningLabLaunchConsumed = true;
  return _uiTuningLabOpenRequested;
}

// ---------------------------------------------------------------------------
// Configuration. `original` is the production list and the baseline; the other
// designs are built below and start from their own defaults.
// ---------------------------------------------------------------------------
@immutable
class UITuningLabPrayerStyle {
  const UITuningLabPrayerStyle({
    this.design = 'original',
    this.cornerRadius = 16,
    this.spacing = 4,
    this.accent = 'green',
    this.showWindow = true,
  });

  final String design;
  final double cornerRadius;
  final double spacing;
  final String accent; // 'green' | 'gold'
  final bool showWindow;

  UITuningLabPrayerStyle copyWith({
    double? cornerRadius,
    double? spacing,
    String? accent,
    bool? showWindow,
  }) => UITuningLabPrayerStyle(
    design: design,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    spacing: spacing ?? this.spacing,
    accent: accent ?? this.accent,
    showWindow: showWindow ?? this.showWindow,
  );
}

const _baseline = UITuningLabPrayerStyle(design: 'original');

// Each design's own defaults; Copy values reports knobs against these.
const _defaults = <String, UITuningLabPrayerStyle>{
  'original': _baseline,
  'timeline': UITuningLabPrayerStyle(
    design: 'timeline',
    cornerRadius: 16,
    spacing: 4,
    accent: 'green',
    showWindow: true,
  ),
  'strip': UITuningLabPrayerStyle(
    design: 'strip',
    cornerRadius: 14,
    spacing: 6,
    accent: 'green',
    showWindow: false,
  ),
  'capsule': UITuningLabPrayerStyle(
    design: 'capsule',
    cornerRadius: 16,
    spacing: 6,
    accent: 'green',
    showWindow: true,
  ),
};

const _designLabels = <String, String>{
  'original': 'Original',
  'timeline': 'Timeline',
  'strip': 'Strip',
  'capsule': 'Capsule',
};

// Preset keys are kebab-case: the key is what a candidate records as basedOn.
const _presets = <String, UITuningLabPrayerStyle>{
  'timeline-airy': UITuningLabPrayerStyle(
    design: 'timeline',
    cornerRadius: 20,
    spacing: 10,
    accent: 'green',
    showWindow: true,
  ),
  'strip-compact': UITuningLabPrayerStyle(
    design: 'strip',
    cornerRadius: 10,
    spacing: 4,
    accent: 'green',
    showWindow: false,
  ),
  'strip-gold': UITuningLabPrayerStyle(
    design: 'strip',
    cornerRadius: 16,
    spacing: 8,
    accent: 'gold',
    showWindow: false,
  ),
  'capsule-gold': UITuningLabPrayerStyle(
    design: 'capsule',
    cornerRadius: 22,
    spacing: 8,
    accent: 'gold',
    showWindow: true,
  ),
};

// The diff against the selected design's defaults, plus the design itself.
Map<String, Object> _values(UITuningLabPrayerStyle s) {
  if (s.design == 'original') return <String, Object>{};
  final b = _defaults[s.design] ?? _baseline;
  return <String, Object>{
    'design': s.design,
    if (s.cornerRadius != b.cornerRadius) 'cornerRadius': s.cornerRadius,
    if (s.spacing != b.spacing) 'spacing': s.spacing,
    if (s.accent != b.accent) 'accent': s.accent,
    if (s.showWindow != b.showWindow) 'showWindow': s.showWindow,
  };
}

UITuningLabPrayerStyle _fromValues(Map<String, Object> v) {
  final design = v['design'] as String? ?? 'original';
  final b = _defaults[design] ?? _baseline;
  return UITuningLabPrayerStyle(
    design: design,
    cornerRadius: (v['cornerRadius'] as num?)?.toDouble() ?? b.cornerRadius,
    spacing: (v['spacing'] as num?)?.toDouble() ?? b.spacing,
    accent: v['accent'] as String? ?? b.accent,
    showWindow: v['showWindow'] as bool? ?? b.showWindow,
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

// 1 -> a, 26 -> z, 27 -> aa (bijective base 26).
String _candidateName(int index) {
  var name = '';
  for (var n = index; n > 0; n ~/= 26) {
    n -= 1;
    name = String.fromCharCode(97 + n % 26) + name;
  }
  return name;
}

// ---------------------------------------------------------------------------
// Shared helpers for the designs.
// ---------------------------------------------------------------------------
enum _St { passed, current, next, upcoming }

List<_St> _statuses(List<PrayerTimeModel> ps) {
  final idx = ps.indexWhere((p) => p.isCurrent || p.isNext);
  return [
    for (var i = 0; i < ps.length; i++)
      ps[i].isNext
          ? _St.next
          : ps[i].isCurrent
          ? _St.current
          : (idx != -1 && i < idx)
          ? _St.passed
          : _St.upcoming,
  ];
}

String _prayerName(BuildContext context, PrayerType type) {
  switch (type) {
    case PrayerType.fajr:
      return context.strings.fajr;
    case PrayerType.dhuhr:
      return context.strings.dhuhr;
    case PrayerType.asr:
      return context.strings.asr;
    case PrayerType.maghrib:
      return context.strings.maghrib;
    case PrayerType.isha:
      return context.strings.isha;
  }
}

String _timeText(BuildContext context, PrayerTimeModel p) => p.dateTime != null
    ? PrayersHelper.formatTimeTo12Hour(
        p.dateTime!,
        language: Localizations.localeOf(context).languageCode,
      )
    : p.time;

void _toggle(BuildContext context, PrayerType type) => context
    .read<HomelayoutBloc>()
    .add(TogglePrayerNotificationEvent(type));

TextStyle _text(
  BuildContext context,
  double size,
  FontWeight weight,
  Color color, {
  bool tabular = false,
}) => (context.textTheme.titleMedium ?? const TextStyle()).copyWith(
  fontSize: size.sp,
  fontWeight: weight,
  color: color,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

class _Pal {
  const _Pal({
    required this.surface,
    required this.border,
    required this.text,
    required this.sub,
    required this.muted,
    required this.selectedBg,
    required this.fill,
    required this.on,
  });

  factory _Pal.of(BuildContext context, String accent) {
    final d = context.isDark;
    final gold = accent == 'gold';
    return _Pal(
      surface: d ? AppColors.darkCardUnselected : AppColors.lightSurface,
      border: d
          ? AppColors.darkBorderUnselected
          : AppColors.lightBorderUnselected,
      text: d ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      sub: d ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
      muted: d ? AppColors.darkTextMuted : AppColors.lightTextMuted,
      selectedBg: d ? AppColors.darkCardSelected : AppColors.lightCardSelected,
      fill: gold
          ? AppColors.accentGold
          : (d
                ? Color.lerp(
                    AppColors.darkBorderUnselected,
                    AppColors.white,
                    0.15,
                  )!
                : AppColors.primaryDark),
      on: gold ? AppColors.primaryDarkHeader : AppColors.white,
    );
  }

  final Color surface;
  final Color border;
  final Color text;
  final Color sub;
  final Color muted;
  final Color selectedBg;
  final Color fill; // accent fill for the next prayer
  final Color on; // text/icon color on the accent fill
}

/// Notification toggle with a 44x44 hit area and press feedback.
class _Bell extends StatelessWidget {
  const _Bell({
    required this.prayer,
    required this.color,
    required this.height,
  });
  final PrayerTimeModel prayer;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: prayer.isNotificationEnabled,
      label: _prayerName(context, prayer.type),
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: () => _toggle(context, prayer.type),
          radius: 22,
          child: SizedBox(
            width: 44,
            height: height,
            child: Center(
              child: Icon(
                prayer.isNotificationEnabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: 20.r,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.pal, required this.filled});
  final String label;
  final _Pal pal;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ring = context.isDark ? AppColors.white : AppColors.primaryDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: filled ? pal.fill : Colors.transparent,
        borderRadius: BorderRadius.circular(6.r),
        border: filled ? null : Border.all(color: ring, width: 1),
      ),
      child: Text(
        label,
        style: _text(
          context,
          10,
          FontWeight.w700,
          filled ? pal.on : (context.isDark ? AppColors.white : ring),
        ),
      ),
    );
  }
}

String? _window(PrayerTimeModel p) =>
    (p.startWindow.isNotEmpty && p.endWindow.isNotEmpty)
    ? '${p.startWindow} – ${p.endWindow}'
    : null;

// ---------------------------------------------------------------------------
// Design 1: Timeline. A vertical rail shows the day: passed (check), current
// (gold ring), next (accent dot with halo), upcoming (hollow ring).
// ---------------------------------------------------------------------------
class UITuningLabPrayerTimeline extends StatelessWidget {
  const UITuningLabPrayerTimeline({super.key, required this.style});
  final UITuningLabPrayerStyle style;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomelayoutBloc, HomelayoutState>(
      builder: (context, state) {
        final ps = state.prayerTimes;
        final st = _statuses(ps);
        final pal = _Pal.of(context, style.accent);
        return Container(
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(style.cornerRadius.r),
            border: Border.all(color: pal.border),
          ),
          padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
          child: Column(
            children: [
              for (var i = 0; i < ps.length; i++)
                _TimelineRow(
                  prayer: ps[i],
                  status: st[i],
                  first: i == 0,
                  last: i == ps.length - 1,
                  pal: pal,
                  style: style,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.prayer,
    required this.status,
    required this.first,
    required this.last,
    required this.pal,
    required this.style,
  });
  final PrayerTimeModel prayer;
  final _St status;
  final bool first;
  final bool last;
  final _Pal pal;
  final UITuningLabPrayerStyle style;

  Widget _dot() {
    switch (status) {
      case _St.passed:
        return Container(
          width: 18.r,
          height: 18.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pal.sub.withValues(alpha: 0.18),
          ),
          child: Icon(Icons.check_rounded, size: 12.r, color: pal.sub),
        );
      case _St.current:
        return Container(
          width: 18.r,
          height: 18.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pal.surface,
            border: Border.all(color: AppColors.accentGold, width: 2),
          ),
          child: Center(
            child: Container(
              width: 7.r,
              height: 7.r,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentGold,
              ),
            ),
          ),
        );
      case _St.next:
        return Container(
          width: 20.r,
          height: 20.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pal.fill,
            boxShadow: [
              BoxShadow(
                color: pal.fill.withValues(alpha: 0.25),
                spreadRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 6.r,
              height: 6.r,
              decoration: BoxDecoration(shape: BoxShape.circle, color: pal.on),
            ),
          ),
        );
      case _St.upcoming:
        return Container(
          width: 14.r,
          height: 14.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pal.surface,
            border: Border.all(color: pal.muted, width: 2),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final railW = 28.w;
    final gap = style.spacing;
    final isNext = status == _St.next;
    final passed = status == _St.passed;
    final nameColor = passed ? pal.sub : pal.text;
    final window = style.showWindow ? _window(prayer) : null;
    final badge = status == _St.next
        ? _Badge(label: context.strings.nextPrayerBadge, pal: pal, filled: true)
        : status == _St.current
        ? _Badge(
            label: context.strings.currentPrayerBadge,
            pal: pal,
            filled: false,
          )
        : null;

    return Stack(
      children: [
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: railW,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: first
                    ? Alignment.bottomCenter
                    : last
                    ? Alignment.topCenter
                    : Alignment.center,
                child: FractionallySizedBox(
                  heightFactor: (first || last) ? 0.5 : 1.0,
                  child: Container(
                    width: 2,
                    color: pal.muted.withValues(alpha: 0.35),
                  ),
                ),
              ),
              _dot(),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: railW + 4.w,
            top: gap / 2,
            bottom: gap / 2,
          ),
          child: Container(
            padding: EdgeInsetsDirectional.only(
              start: 10.w,
              end: 2.w,
              top: 4.h,
              bottom: 4.h,
            ),
            decoration: BoxDecoration(
              color: isNext ? pal.selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(
                (style.cornerRadius * 0.75).r,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _prayerName(context, prayer.type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _text(
                                context,
                                15,
                                FontWeight.w700,
                                nameColor,
                              ),
                            ),
                          ),
                          if (badge != null) ...[SizedBox(width: 8.w), badge],
                        ],
                      ),
                      if (window != null)
                        Padding(
                          padding: EdgeInsets.only(top: 2.h),
                          child: Text(
                            window,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              context,
                              11,
                              FontWeight.w500,
                              pal.sub,
                              tabular: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _timeText(context, prayer),
                  style: _text(
                    context,
                    15,
                    FontWeight.w700,
                    nameColor,
                    tabular: true,
                  ),
                ),
                _Bell(
                  prayer: prayer,
                  color: prayer.isNotificationEnabled ? pal.sub : pal.muted,
                  height: 44,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Design 2: Strip. Five compact cards in one row; the next prayer is the only
// filled card. Smallest height of the three.
// ---------------------------------------------------------------------------
class UITuningLabPrayerStrip extends StatelessWidget {
  const UITuningLabPrayerStrip({super.key, required this.style});
  final UITuningLabPrayerStyle style;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomelayoutBloc, HomelayoutState>(
      builder: (context, state) {
        final ps = state.prayerTimes;
        final st = _statuses(ps);
        final pal = _Pal.of(context, style.accent);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < ps.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: i == 0 ? 0 : style.spacing,
                  ),
                  child: _StripCard(
                    prayer: ps[i],
                    status: st[i],
                    pal: pal,
                    style: style,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.prayer,
    required this.status,
    required this.pal,
    required this.style,
  });
  final PrayerTimeModel prayer;
  final _St status;
  final _Pal pal;
  final UITuningLabPrayerStyle style;

  @override
  Widget build(BuildContext context) {
    final isNext = status == _St.next;
    final isCurrent = status == _St.current;
    final passed = status == _St.passed;
    final nameColor = isNext ? pal.on : (passed ? pal.sub : pal.text);
    final subColor = isNext ? pal.on : pal.sub;

    return Container(
      decoration: BoxDecoration(
        color: isNext ? pal.fill : pal.surface,
        borderRadius: BorderRadius.circular(style.cornerRadius.r),
        border: Border.all(
          color: isNext
              ? pal.fill
              : (isCurrent ? AppColors.accentGold : pal.border),
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      padding: EdgeInsets.fromLTRB(4.w, 12.h, 4.w, 0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: AlignmentDirectional.topCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22.r,
                height: 22.r,
                child: Opacity(
                  opacity: passed ? 0.55 : 1,
                  child: PrayerTypeIconWidget(
                    type: prayer.type,
                    color: isNext ? pal.on : null,
                  ),
                ),
              ),
              SizedBox(height: 6.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _prayerName(context, prayer.type),
                  style: _text(context, 12, FontWeight.w700, nameColor),
                ),
              ),
              SizedBox(height: 2.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _timeText(context, prayer),
                  style: _text(
                    context,
                    12,
                    FontWeight.w600,
                    subColor,
                    tabular: true,
                  ),
                ),
              ),
              _Bell(
                prayer: prayer,
                color: isNext
                    ? pal.on
                    : (prayer.isNotificationEnabled ? pal.sub : pal.muted),
                height: 40,
              ),
            ],
          ),
          if (passed)
            PositionedDirectional(
              top: -6.h,
              end: 0,
              child: Icon(Icons.check_rounded, size: 12.r, color: pal.sub),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Design 3: Capsule. Quiet rows with no dividers; the next prayer becomes a
// filled capsule that also shows its time window. Passed prayers get a check
// and dim.
// ---------------------------------------------------------------------------
class UITuningLabPrayerCapsule extends StatelessWidget {
  const UITuningLabPrayerCapsule({super.key, required this.style});
  final UITuningLabPrayerStyle style;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomelayoutBloc, HomelayoutState>(
      builder: (context, state) {
        final ps = state.prayerTimes;
        final st = _statuses(ps);
        final pal = _Pal.of(context, style.accent);
        return Container(
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(style.cornerRadius.r),
            border: Border.all(color: pal.border),
          ),
          padding: EdgeInsets.all(8.r),
          child: Column(
            children: [
              for (var i = 0; i < ps.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == ps.length - 1 ? 0 : style.spacing,
                  ),
                  child: _CapsuleRow(
                    prayer: ps[i],
                    status: st[i],
                    pal: pal,
                    style: style,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CapsuleRow extends StatelessWidget {
  const _CapsuleRow({
    required this.prayer,
    required this.status,
    required this.pal,
    required this.style,
  });
  final PrayerTimeModel prayer;
  final _St status;
  final _Pal pal;
  final UITuningLabPrayerStyle style;

  @override
  Widget build(BuildContext context) {
    final isNext = status == _St.next;
    final isCurrent = status == _St.current;
    final passed = status == _St.passed;
    final textColor = isNext ? pal.on : (passed ? pal.sub : pal.text);
    final subColor = isNext ? pal.on : pal.sub;
    final radius = (style.cornerRadius - 4).clamp(0.0, 40.0).r;
    final window = (style.showWindow && (isNext || isCurrent))
        ? _window(prayer)
        : null;

    return Container(
      constraints: BoxConstraints(minHeight: 56.h),
      padding: EdgeInsetsDirectional.only(start: 10.w, end: 2.w),
      decoration: BoxDecoration(
        color: isNext ? pal.fill : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: isCurrent
            ? Border.all(color: AppColors.accentGold, width: 1.4)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36.r,
            height: 36.r,
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNext
                  ? pal.on.withValues(alpha: 0.18)
                  : pal.selectedBg,
            ),
            child: Opacity(
              opacity: passed ? 0.55 : 1,
              child: PrayerTypeIconWidget(
                type: prayer.type,
                color: isNext ? pal.on : null,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (passed) ...[
                      Icon(Icons.check_rounded, size: 14.r, color: pal.sub),
                      SizedBox(width: 4.w),
                    ],
                    Flexible(
                      child: Text(
                        _prayerName(context, prayer.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(context, 15, FontWeight.w700, textColor),
                      ),
                    ),
                    if (isCurrent) ...[
                      SizedBox(width: 8.w),
                      _Badge(
                        label: context.strings.currentPrayerBadge,
                        pal: pal,
                        filled: false,
                      ),
                    ],
                  ],
                ),
                if (window != null)
                  Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: Text(
                      window,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        context,
                        11,
                        FontWeight.w500,
                        subColor,
                        tabular: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _timeText(context, prayer),
            style: _text(context, 15, FontWeight.w700, textColor, tabular: true),
          ),
          _Bell(
            prayer: prayer,
            color: isNext
                ? pal.on
                : (prayer.isNotificationEnabled ? pal.sub : pal.muted),
            height: 52,
          ),
        ],
      ),
    );
  }
}

typedef _DesignBuilder = Widget Function(UITuningLabPrayerStyle style);
final Map<String, _DesignBuilder> _designs = {
  'timeline': (s) => UITuningLabPrayerTimeline(style: s),
  'strip': (s) => UITuningLabPrayerStrip(style: s),
  'capsule': (s) => UITuningLabPrayerCapsule(style: s),
};

// ---------------------------------------------------------------------------
// Host: wraps only the prayer list. The pill and panel live in the app's
// Overlay, so they pin to the screen. The panel is built only while open.
// ---------------------------------------------------------------------------
class UITuningLabHost extends StatefulWidget {
  const UITuningLabHost({super.key, required this.child});

  /// The production list, rendered whenever the design is `original`.
  final Widget child;

  @override
  State<UITuningLabHost> createState() => _UITuningLabHostState();
}

class _UITuningLabHostState extends State<UITuningLabHost> {
  UITuningLabPrayerStyle draft = _baseline;
  UITuningLabPrayerStyle? stash; // the draft while baseline/candidate is shown
  final List<_Candidate> candidates = []; // seeded from the project later
  final Set<String> issued = {}; // every name issued, removed ones included
  final Set<String> logged = {};
  String basedOn = 'baseline';
  String shown = 'draft'; // "draft", "baseline", or a candidate's name
  String? status;
  final portal = OverlayPortalController();
  bool isOpen = false;

  @override
  void initState() {
    super.initState();
    issued.addAll(candidates.map((c) => c.name));
    final requested = uiTuningLabConsumeRequest();
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

  void _restore() {
    if (stash != null) draft = stash!;
    stash = null;
    shown = 'draft';
  }

  void close() => update(() {
    _restore();
    isOpen = false;
  });

  void show(String target) {
    update(() {
      if (target == 'draft') {
        _restore();
      } else {
        stash ??= draft;
        final c = candidates.where((c) => c.name == target).firstOrNull;
        draft = c == null ? _baseline : _fromValues(c.values);
        shown = target;
      }
    });
  }

  void pickDesign(String key) => update(() {
    draft = _defaults[key] ?? _baseline;
  });

  void applyPreset(String name) => update(() {
    draft = _presets[name]!;
    basedOn = name;
  });

  void reset() => update(() {
    draft = _baseline;
    basedOn = 'baseline';
  });

  Future<void> copyValues() async {
    final values = _values(draft);
    final json = _sortedJson(values);
    _log('UITUNINGLAB_VALUES', values);
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = json == '{}' ? 'No changes from baseline' : 'Copied $json');
  }

  void keep() {
    final values = _values(draft);
    if (values.isEmpty) {
      update(() => status = 'Matches the baseline; nothing to keep');
      return;
    }
    final same = candidates
        .where((c) => _sortedJson(c.values) == _sortedJson(values))
        .firstOrNull;
    if (same != null) {
      update(() => status = 'Same as ${same.name}');
      return;
    }
    var i = 1;
    while (issued.contains(_candidateName(i))) {
      i++;
    }
    final c = _Candidate(_candidateName(i), basedOn, values);
    issued.add(c.name);
    logged.add(c.name);
    _log('UITUNINGLAB_CANDIDATE', c.toJson());
    update(() {
      candidates.add(c);
      status = 'Kept as ${c.name}';
    });
  }

  void load(_Candidate c) => update(() {
    stash = null;
    draft = _fromValues(c.values);
    basedOn = c.name;
    shown = 'draft';
  });

  void remove(String name) {
    _log('UITUNINGLAB_CANDIDATE_REMOVED', {'name': name});
    update(() => candidates.removeWhere((c) => c.name == name));
    if (shown == name) show('draft');
  }

  // Like Copy values, and it tells the agent the session is over. While Compare
  // shows a candidate, that candidate becomes the draft first: it is the winner.
  Future<void> done() async {
    final picked = candidates.where((c) => c.name == shown).firstOrNull;
    if (picked != null) load(picked);
    final values = picked != null ? picked.values : _values(draft);
    final winner = candidates
        .where((c) => _sortedJson(c.values) == _sortedJson(values))
        .firstOrNull;
    _log('UITUNINGLAB_DONE', {
      'candidates': [for (final c in candidates) c.toJson()],
      'values': values,
      'winner': winner?.name,
    });
    final json = _sortedJson(values);
    await Clipboard.setData(ClipboardData(text: json));
    update(() => status = 'Done. Copied $json');
  }

  @override
  Widget build(BuildContext context) {
    final variant = _designs[draft.design];
    final body = variant != null ? variant(draft) : widget.child;
    return OverlayPortal(
      controller: portal,
      overlayChildBuilder: (overlayContext) {
        // Off while this screen is an offstage tab or a covered route.
        if (!TickerMode.of(overlayContext)) return const SizedBox.shrink();
        if (isOpen) return panel(overlayContext);
        return Positioned(
          left: 12,
          bottom: MediaQuery.paddingOf(overlayContext).bottom + 96,
          child: Semantics(
            label: 'Open UI tuning lab',
            button: true,
            excludeSemantics: true,
            child: FilledButton(onPressed: open, child: const Text('Tune')),
          ),
        );
      },
      child: body,
    );
  }

  Widget slider(
    String label,
    double value,
    double max,
    bool editing,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max).toDouble(),
            max: max,
            divisions: max.toInt(),
            label: label,
            onChanged: editing ? (v) => onChanged(v.roundToDouble()) : null,
          ),
        ),
        ExcludeSemantics(child: Text('${value.round()}')),
      ],
    );
  }

  Widget panel(BuildContext overlayContext) {
    final editing = shown == 'draft';
    final size = MediaQuery.sizeOf(overlayContext);
    // Phones: a full-width panel docked to the bottom, at most 42% tall, so the
    // list stays visible above it. Wider screens: a 340-wide corner panel.
    final compact = size.width < 600;
    final design = draft.design;
    final tunable = design != 'original';
    final gapLabel = design == 'strip' ? 'Card gap' : 'Row gap';

    return Positioned(
      left: compact ? 0 : null,
      right: compact ? 0 : 16,
      bottom: compact ? 0 : 72,
      width: compact ? null : 340,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: compact ? size.height * 0.42 : size.height - 120,
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
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  header: true,
                                  child: const Text('UI tuning lab'),
                                ),
                              ),
                              TextButton(
                                onPressed: close,
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                          const Text('Design'),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final key in _designLabels.keys)
                                ChoiceChip(
                                  label: Text(_designLabels[key]!),
                                  selected: design == key,
                                  onSelected: editing
                                      ? (_) => pickDesign(key)
                                      : null,
                                ),
                            ],
                          ),
                          SwitchListTile(
                            title: const Text('Show baseline'),
                            value: shown == 'baseline',
                            onChanged: (on) => show(on ? 'baseline' : 'draft'),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final name in _presets.keys)
                                OutlinedButton(
                                  onPressed: editing
                                      ? () => applyPreset(name)
                                      : null,
                                  child: Text(name),
                                ),
                            ],
                          ),
                          if (tunable) ...[
                            slider(
                              'Radius',
                              draft.cornerRadius,
                              28,
                              editing,
                              (v) => update(
                                () => draft = draft.copyWith(cornerRadius: v),
                              ),
                            ),
                            slider(
                              gapLabel,
                              draft.spacing,
                              16,
                              editing,
                              (v) => update(
                                () => draft = draft.copyWith(spacing: v),
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text('Accent'),
                                for (final a in const ['green', 'gold'])
                                  ChoiceChip(
                                    label: Text(a),
                                    selected: draft.accent == a,
                                    onSelected: editing
                                        ? (_) => update(
                                            () => draft = draft.copyWith(
                                              accent: a,
                                            ),
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                            if (design != 'strip')
                              SwitchListTile(
                                title: const Text('Show time window'),
                                value: draft.showWindow,
                                onChanged: editing
                                    ? (v) => update(
                                        () => draft = draft.copyWith(
                                          showWindow: v,
                                        ),
                                      )
                                    : null,
                              ),
                          ] else
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Original is the shipped list: pick a design or a preset to tune.',
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: editing ? reset : null,
                                child: const Text('Reset'),
                              ),
                              TextButton(
                                onPressed: editing ? copyValues : null,
                                child: const Text('Copy values'),
                              ),
                              TextButton(
                                onPressed: editing ? keep : null,
                                child: const Text('Keep as candidate'),
                              ),
                            ],
                          ),
                          if (candidates.isNotEmpty) ...[
                            for (final c in candidates)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${c.name}: ${_sortedJson(c.values)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: editing ? () => load(c) : null,
                                    child: Text(
                                      'Load',
                                      semanticsLabel: 'Load ${c.name}',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => remove(c.name),
                                    child: Text(
                                      'Remove',
                                      semanticsLabel: 'Remove ${c.name}',
                                    ),
                                  ),
                                ],
                              ),
                            const Text('Compare'),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final target in [
                                  'draft',
                                  ...candidates.map((c) => c.name),
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      target == 'draft' ? 'Draft' : target,
                                    ),
                                    selected: shown == target,
                                    onSelected: (_) => show(target),
                                  ),
                              ],
                            ),
                          ],
                          FilledButton(
                            onPressed: shown == 'baseline' ? null : done,
                            child: const Text('Done'),
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
                  // Pinned below the scrolling controls.
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Finished? Keep the ones you like, then press Done, or tell the agent "land b".',
                    ),
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

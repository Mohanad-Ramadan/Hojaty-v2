import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../../core/utils/app_colors.dart';
import '../../../../../core/utils/assets.dart';
import '../../../../../core/utils/extensions/context_extensions.dart';
import '../../../../../core/utils/screen_util_like.dart';

/// Floating tab bar: a detached rounded bar with a filled tile that slides
/// behind the active tab. Every tab keeps its label.
class HomeBottomNavBarWidget extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const HomeBottomNavBarWidget({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  static const double _margin = 19;
  static const double _radius = 36;
  static const double _tileRadius = _radius - 5;
  static const double _height = 68;
  static const Duration _motion = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final items = [
      (icon: Assets.homeNavBarIcon, label: context.strings.navHome),
      (icon: Assets.quranNavBarIcon, label: context.strings.navQuran),
      (icon: Assets.azkharNavBarIcon, label: context.strings.navAthkar),
      (icon: Assets.occasionsNavBarIcon, label: context.strings.navOccasions),
      (icon: Assets.moreNavBarIcon, label: context.strings.navMore),
    ];
    final n = items.length;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _motion;

    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark
        ? AppColors.darkBorderUnselected
        : AppColors.lightBorderUnselected;
    // Secondary (not muted) text keeps inactive labels at 4.5:1 contrast.
    final inactive = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_margin, 6, _margin, _margin),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: border),
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
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    alignment: AlignmentDirectional(
                      -1 + 2 * currentIndex / (n - 1),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / n,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.accentGold,
                            borderRadius: BorderRadius.circular(_tileRadius),
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
                          child: _NavCell(
                            label: items[i].label,
                            iconPath: items[i].icon,
                            selected: i == currentIndex,
                            activeColor: AppColors.primaryDarkHeader,
                            inactiveColor: inactive,
                            duration: duration,
                            onTap: () => onTabSelected(i),
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

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.label,
    required this.iconPath,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final String iconPath;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final base = context.textTheme.bodySmall ?? const TextStyle();
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            HomeBottomNavBarWidget._tileRadius,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: duration,
                builder: (context, c, _) => SvgPicture.asset(
                  iconPath,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  colorFilter: ColorFilter.mode(c ?? color, BlendMode.srcIn),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: duration,
                  style: base.copyWith(
                    color: color,
                    fontSize: 11.sp,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(label, maxLines: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

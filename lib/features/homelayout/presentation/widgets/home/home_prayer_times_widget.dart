import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../config/routes/app_router.dart';
import '../../../../../core/utils/app_colors.dart';
import '../../../../../core/utils/extensions/context_extensions.dart';
import '../../../../../core/utils/screen_util_like.dart';
import '../../bloc/homelayout_bloc.dart';
import '../../bloc/homelayout_event.dart';
import '../../bloc/homelayout_state.dart';
import 'home_prayer_row_widget.dart';
import 'home_prayer_times.ui-tuning-lab.dart';

class HomePrayerTimesWidget extends StatelessWidget {
  const HomePrayerTimesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.strings.prayerTimesSectionTitle,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18.sp,
                ),
              ),
              InkWell(
                onTap: () => context.pushNamed(AppRoutes.prayerTimes),
                borderRadius: BorderRadius.circular(8.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.strings.details,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.sp,
                        ),
                      ),
                      4.hor,
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12.r,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          12.ver,
          _uiTuningLabHost(
            BlocBuilder<HomelayoutBloc, HomelayoutState>(
              builder: (context, state) =>
                  _buildOriginal(context, state, isDark),
            ),
          ),
        ],
      ),
    );
  }

  // Debug builds only: kDebugMode is a compile-time constant, so release AOT
  // builds drop the host and the lab file. Removed at landing.
  Widget _uiTuningLabHost(Widget child) =>
      kDebugMode ? UITuningLabHost(child: child) : child;

  Widget _buildOriginal(
    BuildContext context,
    HomelayoutState state,
    bool isDark,
  ) {
    return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkCardUnselected
                      : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorderUnselected
                        : AppColors.lightBorderUnselected,
                    width: 1.0,
                  ),
                ),
                padding: EdgeInsets.symmetric(vertical: 6.h),
                child: Column(
                  children: List.generate(state.prayerTimes.length, (index) {
                    final prayer = state.prayerTimes[index];
                    return Column(
                      children: [
                        HomePrayerRowWidget(
                          prayer: prayer,
                          onToggleNotification: () {
                            context.read<HomelayoutBloc>().add(
                              TogglePrayerNotificationEvent(prayer.type),
                            );
                          },
                        ),
                        if (index < state.prayerTimes.length - 1)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isDark
                                ? AppColors.darkBorderUnselected.withValues(
                                    alpha: 0.5,
                                  )
                                : AppColors.lightBorderUnselected.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                      ],
                    );
                  }),
                ),
    );
  }
}

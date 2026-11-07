import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/utils/local_notification_service.dart';
import '../bloc/homelayout_bloc.dart';
import '../bloc/homelayout_event.dart';
import '../bloc/homelayout_state.dart';
import '../widgets/athkar/athkar_grid_view.dart';
import '../widgets/shared/exit_app_dialog.dart';
import '../widgets/home/home_bottom_nav_bar_widget.dart';
import '../widgets/home/home_dashboard_view.dart';
import '../widgets/occasions/occasions_tab_view.dart';
import '../widgets/quran/quran_tab_view.dart';
import '../widgets/settings/settings_tab_view.dart';

class HomelayoutPage extends StatefulWidget {
  const HomelayoutPage({super.key});

  @override
  State<HomelayoutPage> createState() => _HomelayoutPageState();
}

class _HomelayoutPageState extends State<HomelayoutPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await LocalNotificationService.requestPermission();
      if (granted && mounted) {
        context.read<HomelayoutBloc>().add(const LoadHomelayoutEvent());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomelayoutBloc, HomelayoutState>(
      builder: (context, state) {
        final tabs = [
          const HomeDashboardView(),
          const QuranTabView(),
          const AthkarGridView(),
          const OccasionsTabView(),
          const SettingsTabView(),
        ];

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, dynamic result) async {
            if (didPop) return;
            if (state.currentTabIndex != 0) {
              context.read<HomelayoutBloc>().add(
                const ChangeBottomNavTabEvent(0),
              );
            } else {
              final shouldExit = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => const ExitAppDialog(),
              );
              if (shouldExit == true) {
                SystemNavigator.pop();
              }
            }
          },
          child: Scaffold(
            body: IndexedStack(index: state.currentTabIndex, children: tabs),
            bottomNavigationBar: HomeBottomNavBarWidget(
              currentIndex: state.currentTabIndex,
              onTabSelected: (index) {
                context.read<HomelayoutBloc>().add(
                  ChangeBottomNavTabEvent(index),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// ARCHIVED ORIGINAL HOMELAYOUT CODE
// ==========================================
// class HomelayoutView extends StatelessWidget {
//   const HomelayoutView({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Homelayout')),
//       body: Center(
//         child: BlocBuilder<HomelayoutBloc, HomelayoutState>(
//           builder: (context, state) {
//             switch (state.status) {
//               case HomelayoutStatus.initial:
//               case HomelayoutStatus.loading:
//                 return const CircularProgressIndicator();
//               case HomelayoutStatus.loaded:
//                 return const Text('Data Loaded ✅');
//               case HomelayoutStatus.error:
//                 return Text('Error: ${state.message}');
//             }
//           },
//         ),
//       ),
//        floatingActionButton: FloatingActionButton(
//         onPressed: () => context.read<HomelayoutBloc>().add(LoadHomelayoutEvent()),
//         child: const Icon(Icons.refresh),
//        ),
//     );
//   }
// }

// Copyright 2024 The Memex team. All rights reserved.
// Compass-aligned: GoRouter for declarative routing.
// ViewModels are created in route builders and passed to screens.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/calendar/view_models/calendar_viewmodel.dart';
import 'package:memex/ui/calendar/widgets/calendar_screen.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/ui/settings/widgets/personal_center_screen.dart';
import 'package:memex/ui/user_setup/widgets/user_setup_screen.dart';
import 'package:memex/routing/routes.dart';

/// Creates the app [GoRouter]. Root content is built by [rootBuilder].
GoRouter createAppRouter(
  GlobalKey<NavigatorState> navigatorKey,
  Widget Function() rootBuilder,
) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => rootBuilder(),
      ),
      GoRoute(
        path: AppRoutes.userSetup,
        builder: (context, state) => UserSetupScreen(
          onUserCreated: () {
            context.go(AppRoutes.home);
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, state) {
          final initialDate = state.extra as DateTime? ?? DateTime.now();
          final vm = CalendarViewModel(
            router: context.read<MemexRouter>(),
            initialDate: initialDate,
          );
          vm.fetchMonthData(DateTime(initialDate.year, initialDate.month));
          return CalendarScreen(initialDate: initialDate, viewModel: vm);
        },
      ),
      GoRoute(
        path: '${AppRoutes.timelineCardDetail}/:id',
        builder: (context, state) {
          final cardId = state.pathParameters['id'] ?? '';
          return TimelineCardDetailScreen(cardId: cardId);
        },
      ),
      GoRoute(
        path: AppRoutes.personalCenter,
        builder: (_, __) => const PersonalCenterScreen(),
      ),
    ],
  );
}

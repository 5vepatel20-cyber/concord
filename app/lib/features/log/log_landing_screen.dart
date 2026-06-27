// /log landing screen.
//
// The "Log" tab in the tab shell is special: it has no real content of
// its own. Tapping it (or being deep-linked to /log from a notification)
// should immediately open the quick-log bottom sheet. After the sheet is
// open, we navigate to /home so the sheet is layered over the home
// dashboard — when the patient dismisses the sheet, they land on Home
// rather than an empty placeholder tab.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../symptoms/quick_log_screen.dart';

class LogLandingScreen extends ConsumerStatefulWidget {
  const LogLandingScreen({super.key});

  @override
  ConsumerState<LogLandingScreen> createState() => _LogLandingScreenState();
}

class _LogLandingScreenState extends ConsumerState<LogLandingScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _opened) return;
      _opened = true;
      // Open the bottom sheet.
      QuickLogScreen.show(context);
      // Then jump to /home so the sheet is layered over Home, not over
      // this invisible placeholder. The sheet survives the route change
      // because modal sheets are owned by the root navigator, not the
      // current route.
      context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Invisible. The user never sees this; the bottom sheet covers it
    // and then we route to /home.
    return const Scaffold(body: SizedBox.shrink());
  }
}

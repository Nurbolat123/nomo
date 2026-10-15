import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

/// Shows onboarding until the profile is approved, then the work screen.
class RootScreen extends ConsumerStatefulWidget {
  const RootScreen({super.key});

  @override
  ConsumerState<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends ConsumerState<RootScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(driverProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(driverProvider.select((s) => s.profile));
    if (profile == null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const NomoMark(size: 64),
            const SizedBox(height: 24),
            TextButton(onPressed: () => ref.read(driverProvider.notifier).init(), child: Text(S.of(context).t('retry'))),
          ]),
        ),
      );
    }
    return profile.approved ? const DriverHomeScreen() : const OnboardingScreen();
  }
}

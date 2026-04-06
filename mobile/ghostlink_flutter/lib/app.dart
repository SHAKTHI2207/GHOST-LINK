import 'package:flutter/material.dart';

import 'core/state/ghostlink_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/onboarding_screen.dart';

class GhostLinkApp extends StatefulWidget {
  const GhostLinkApp({super.key});

  @override
  State<GhostLinkApp> createState() => _GhostLinkAppState();
}

class _GhostLinkAppState extends State<GhostLinkApp> {
  late final GhostLinkController controller;

  @override
  void initState() {
    super.initState();
    controller = GhostLinkController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GhostLink',
      theme: AppTheme.darkTheme,
      home: OnboardingScreen(controller: controller),
    );
  }
}

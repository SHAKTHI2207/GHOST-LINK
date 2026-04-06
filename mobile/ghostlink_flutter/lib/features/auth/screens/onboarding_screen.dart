import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../widgets/ghostlink_logo.dart';
import 'identity_screen.dart';

class OnboardingScreen extends StatelessWidget {
  final GhostLinkController controller;

  const OnboardingScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bg, AppColors.bgTop],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: GhostLinkLogo(size: 96),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Private messaging that feels effortless.',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.08,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'GhostLink handles identity, verification, and secure routing behind the scenes so the app feels closer to Signal than a crypto experiment.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _FeaturePanel(
                      title: 'What you get',
                      children: const [
                        _FeatureRow(
                          icon: Icons.verified_user_rounded,
                          title: 'QR trust verification',
                          subtitle:
                              'Confirm contact fingerprints in one clean flow.',
                        ),
                        _FeatureRow(
                          icon: Icons.cloud_done_rounded,
                          title: 'Relay-ready messaging',
                          subtitle:
                              'Internet-first transport without exposing content.',
                        ),
                        _FeatureRow(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Invisible security',
                          subtitle:
                              'Modern UX first, cryptography quietly underneath.',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: controller.busy || controller.restoring
                            ? null
                            : () async {
                                try {
                                  if (controller.identity == null) {
                                    await controller.createIdentity();
                                  }
                                } catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error.toString())),
                                  );
                                  return;
                                }

                                if (!context.mounted) {
                                  return;
                                }

                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        IdentityScreen(controller: controller),
                                  ),
                                );
                              },
                        child: controller.busy || controller.restoring
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                controller.identity == null
                                    ? 'Create Identity'
                                    : 'Continue',
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      controller.restoring
                          ? 'Restoring your secure state...'
                          : 'No phone. No email. Just your keys.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedStrong,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        controller.errorMessage!,
                        style: const TextStyle(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeaturePanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FeaturePanel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.surfaceStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.panelSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

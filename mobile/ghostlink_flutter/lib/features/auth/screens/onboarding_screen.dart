import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/state/ghostlink_controller.dart';
import '../widgets/ghostlink_logo.dart';
import 'identity_screen.dart';

class OnboardingScreen extends StatelessWidget {
  final GhostLinkController controller;

  const OnboardingScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GhostLinkLogo(),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'GhostLink',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Private. Secure. Yours.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: 40),
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
                                  builder: (_) => IdentityScreen(controller: controller),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: controller.busy || controller.restoring
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(controller.identity == null ? 'Create Identity' : 'Continue'),
                    ),
                  ),
                  if (controller.restoring) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Restoring secure identity...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No phone. No email.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      controller.errorMessage!,
                      style: const TextStyle(color: AppColors.danger),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

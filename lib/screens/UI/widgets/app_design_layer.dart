import 'package:flutter/material.dart';

class AppDesignLayer {
  static const double pagePadding = 24;
  static const double sectionGap = 28;
  static const double cardRadius = 16;
}

class AppSectionTitle extends StatelessWidget {
  final String text;
  const AppSectionTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class AppSectionCard extends StatelessWidget {
  final Widget child;
  const AppSectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class AppInfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const AppInfoBanner({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

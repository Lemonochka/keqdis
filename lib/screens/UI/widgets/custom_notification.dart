import 'dart:async';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

// A global key for the navigator, which allows showing notifications from anywhere.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class CustomNotification {
  static void show(BuildContext context, {
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 5),
    IconData? icon,
  }) {
    if (context == null) {
      // Cannot show notification if there is no context.
      return;
    }

    final themeManager = ThemeManager();
    Color backgroundColor;
    Color iconColor;
    IconData defaultIcon;

    switch (type) {
      case NotificationType.success:
        backgroundColor = const Color(0xFF10B981);
        iconColor = Colors.white;
        defaultIcon = Icons.check_circle;
        break;
      case NotificationType.error:
        backgroundColor = const Color(0xFFEF4444);
        iconColor = Colors.white;
        defaultIcon = Icons.error;
        break;
      case NotificationType.warning:
        backgroundColor = const Color(0xFFF59E0B);
        iconColor = Colors.white;
        defaultIcon = Icons.warning;
        break;
      case NotificationType.info:
      default:
        backgroundColor = themeManager.settings.primaryColor;
        iconColor = Colors.white;
        defaultIcon = Icons.info;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _CustomNotificationWidget(
        message: message,
        backgroundColor: backgroundColor,
        iconColor: iconColor,
        icon: icon ?? defaultIcon,
        onDismiss: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
        },
      ),
    );

    overlay.insert(overlayEntry);

    Timer(duration, () {
      if (overlayEntry.mounted) {
        // This triggers the dismiss animation in the widget.
        // The widget itself will call overlayEntry.remove() when done.
      }
    });
  }
}

enum NotificationType {
  success,
  error,
  warning,
  info,
}

class _CustomNotificationWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onDismiss;

  const _CustomNotificationWidget({
    required this.message,
    required this.backgroundColor,
    required this.iconColor,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_CustomNotificationWidget> createState() => _CustomNotificationWidgetState();
}

class _CustomNotificationWidgetState extends State<_CustomNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted || _controller.isAnimating) return;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: widget.backgroundColor.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _dismiss,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';

class ServerSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const ServerSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    return Container(
      decoration: BoxDecoration(
        color:        s.searchBarColor,
        borderRadius: BorderRadius.circular(20), // pill-форма
        // Без border
      ),
      child: TextField(
        controller: controller,
        onChanged:  onChanged,
        style: TextStyle(
          color:    s.textColor,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText:  'Поиск серверов...',
          hintStyle: TextStyle(
            color:    s.secondaryTextColor.withOpacity(0.5),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: s.primaryColor,
            size:  20,
          ),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.close, color: s.secondaryTextColor, size: 18),
            onPressed: onClear,
          )
              : null,
          border:          InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical:   12,
          ),
        ),
      ),
    );
  }
}

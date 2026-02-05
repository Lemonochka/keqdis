import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/utils/config_validator.dart';

class AddServerDialog extends StatelessWidget {
  final Function(List<String>) onServersAdded;

  const AddServerDialog({
    super.key,
    required this.onServersAdded,
  });

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController();
    final themeManager = ThemeManager();

    return AlertDialog(
      backgroundColor: themeManager.settings.accentColor,
      title: const Text('Добавить серверы'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: textController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Вставьте один или несколько конфигов\n(каждый с новой строки)',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Color(0xFF0A0E27),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) {
                  textController.text = data!.text!;
                }
              },
              icon: const Icon(Icons.content_paste),
              label: const Text('Вставить из буфера'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            final text = textController.text.trim();
            if (text.isEmpty) return;

            final lines = text.split('\n');
            final validConfigs = <String>[];

            for (var line in lines) {
              final cfg = line.trim();
              if (cfg.isNotEmpty && ConfigValidator.isValidConfig(cfg)) {
                validConfigs.add(cfg);
              }
            }

            if (validConfigs.isNotEmpty) {
              Navigator.pop(context);
              onServersAdded(validConfigs);
            }
          },
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

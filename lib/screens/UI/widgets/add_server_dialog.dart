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
    final s = ThemeManager().settings;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color:        s.cardColor,
          borderRadius: BorderRadius.circular(20),
          border:       Border.all(color: s.borderColor),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withOpacity(s.isDarkMode ? 0.5 : 0.15),
              blurRadius: 30,
              offset:     const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  padding:    const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:        s.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_link, color: s.primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'Добавить серверы',
                  style: TextStyle(
                    fontSize:   18,
                    fontWeight: FontWeight.w700,
                    color:      s.textColor,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, color: s.secondaryTextColor, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Текстовое поле
            Container(
              decoration: BoxDecoration(
                color:        s.searchBarColor,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: s.borderColor),
              ),
              child: TextField(
                controller: textController,
                maxLines:   8,
                style: TextStyle(color: s.textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Вставьте один или несколько конфигов\n(каждый с новой строки)',
                  hintStyle: TextStyle(
                    color:    s.secondaryTextColor.withOpacity(0.55),
                    fontSize: 13,
                  ),
                  border:          InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Кнопка "Вставить из буфера"
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    textController.text = data!.text!;
                  }
                },
                icon:  Icon(Icons.content_paste, size: 18),
                label: const Text('Вставить из буфера'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: s.primaryColor,
                  side:            BorderSide(color: s.primaryColor.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Кнопки диалога
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: s.secondaryTextColor,
                      side: BorderSide(color: s.borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final text = textController.text.trim();
                      if (text.isEmpty) return;

                      final lines        = text.split('\n');
                      final validConfigs = <String>[];

                      for (final line in lines) {
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: s.primaryColor,
                      foregroundColor: Colors.white,
                      elevation:       0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Добавить',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/services/improved_subscription_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/storages/unified_storage.dart';

class SubscriptionsView extends StatefulWidget {
  final VoidCallback onServersUpdated;

  const SubscriptionsView({
    super.key,
    required this.onServersUpdated,
  });

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  List<Subscription> _subscriptions = [];
  bool _isLoading      = true;
  bool _isUpdating     = false;
  Map<String, bool> _updatingSubscriptions = {};

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    setState(() => _isLoading = true);
    try {
      final subs = await SubscriptionService.loadSubscriptions();
      if (mounted) {
        setState(() {
          _subscriptions = subs;
          _isLoading     = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomNotification.show(context, message: 'Ошибка загрузки: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl  = TextEditingController();
    final urlCtrl   = TextEditingController();
    bool autoUpdate = true;
    final s         = ThemeManager().settings;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints:  const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              color:        s.cardColor,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: s.borderColor),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Добавить подписку',
                  style: TextStyle(
                    fontSize:   18,
                    fontWeight: FontWeight.w700,
                    color:      s.textColor,
                  ),
                ),
                const SizedBox(height: 20),
                _ThemedField(label: 'Название', hint: 'Например: Моя подписка', controller: nameCtrl, settings: s),
                const SizedBox(height: 14),
                _ThemedField(label: 'URL подписки', hint: 'https://example.com/sub', controller: urlCtrl, settings: s, maxLines: 2),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('Автообновление каждые 12ч',
                          style: TextStyle(fontSize: 13, color: s.textColor)),
                    ),
                    Switch(
                      value:       autoUpdate,
                      onChanged:   (v) => setDState(() => autoUpdate = v),
                      activeColor: s.primaryColor,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: s.secondaryTextColor,
                          side: BorderSide(color: s.borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: s.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true || !mounted) return;

    final name = nameCtrl.text.trim();
    final url  = urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) {
      CustomNotification.show(context, message: 'Заполните все поля', type: NotificationType.warning);
      return;
    }

    try {
      final sub = await SubscriptionService.addSubscription(name: name, url: url, autoUpdate: autoUpdate);
      CustomNotification.show(context, message: 'Подписка добавлена, загрузка...', type: NotificationType.success);
      _loadSubscriptions();

      final res = await SubscriptionService.updateSubscriptionServers(sub);
      if (res.success) {
        CustomNotification.show(context, message: 'Загружено ${res.serverCount} серверов', type: NotificationType.success);
        _loadSubscriptions();
        widget.onServersUpdated();
      } else {
        CustomNotification.show(context, message: 'Ошибка: ${res.error}', type: NotificationType.warning);
      }
    } catch (e) {
      CustomNotification.show(context, message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  Future<void> _updateSubscription(Subscription sub) async {
    setState(() => _updatingSubscriptions[sub.id] = true);
    try {
      final res = await SubscriptionService.updateSubscriptionServers(sub);
      if (mounted) {
        setState(() => _updatingSubscriptions[sub.id] = false);
        if (res.success) {
          CustomNotification.show(context, message: 'Обновлено: ${res.serverCount} серверов', type: NotificationType.success);
          _loadSubscriptions();
          widget.onServersUpdated();
        } else {
          CustomNotification.show(context, message: 'Ошибка: ${res.error}', type: NotificationType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingSubscriptions[sub.id] = false);
        CustomNotification.show(context, message: 'Ошибка: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _updateAllSubscriptions() async {
    setState(() => _isUpdating = true);
    try {
      final results = await SubscriptionService.updateAllSubscriptions();
      if (mounted) {
        setState(() => _isUpdating = false);
        final ok      = results.where((r) => r.success).length;
        final servers = results.fold<int>(0, (s, r) => s + r.serverCount);
        CustomNotification.show(context, message: 'Обновлено $ok подписок, $servers серверов', type: NotificationType.success);
        _loadSubscriptions();
        widget.onServersUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        CustomNotification.show(context, message: 'Ошибка: $e', type: NotificationType.error);
      }
    }
  }

  Future<void> _deleteSubscription(Subscription sub) async {
    final s       = ThemeManager().settings;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: s.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: s.borderColor),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Удалить подписку?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: s.textColor)),
              const SizedBox(height: 16),
              Text('${sub.name}   •   ${sub.serverCount} серв.',
                  style: TextStyle(color: s.secondaryTextColor, fontSize: 14)),
              const SizedBox(height: 8),
              Text('Серверы из этой подписки будут удалены.',
                  style: TextStyle(color: Colors.orange.shade400, fontSize: 12)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: s.secondaryTextColor,
                    side: BorderSide(color: s.borderColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Отмена'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Удалить'),
                )),
              ]),
            ],
          ),
        ),
      ),
    );

    if (confirm != true || !mounted) return;
    try {
      await SubscriptionService.removeSubscriptionServers(sub);
      await SubscriptionService.deleteSubscription(sub.id);
      CustomNotification.show(context, message: 'Подписка удалена', type: NotificationType.success);
      _loadSubscriptions();
      widget.onServersUpdated();
    } catch (e) {
      CustomNotification.show(context, message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  Future<void> _toggleAutoUpdate(Subscription sub, bool value) async {
    try {
      await SubscriptionService.updateSubscription(sub.copyWith(autoUpdate: value));
      _loadSubscriptions();
    } catch (e) {
      CustomNotification.show(context, message: 'Ошибка: $e', type: NotificationType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;

    if (_isLoading) return Center(child: CircularProgressIndicator(color: s.primaryColor));

    return Column(
      children: [
        // Заголовок
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Text(
                'Подписки',
                style: TextStyle(
                  fontSize:   22,
                  fontWeight: FontWeight.w700,
                  color:      s.textColor,
                ),
              ),
              const Spacer(),
              // Обновить все
              _IconBtn(
                icon:    _isUpdating
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: s.primaryColor))
                    : Icon(Icons.refresh_rounded, size: 20, color: s.primaryColor),
                tooltip: 'Обновить все',
                onTap:   _isUpdating ? null : _updateAllSubscriptions,
                settings: s,
              ),
              const SizedBox(width: 8),
              // Добавить
              _IconBtn(
                icon:     Icon(Icons.add_rounded, size: 20, color: s.primaryColor),
                tooltip:  'Добавить подписку',
                onTap:    _showAddDialog,
                settings: s,
              ),
            ],
          ),
        ),

        // Список
        if (_subscriptions.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rss_feed, size: 60, color: s.secondaryTextColor.withOpacity(0.25)),
                  const SizedBox(height: 16),
                  Text('Нет подписок', style: TextStyle(color: s.secondaryTextColor, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('Нажмите + чтобы добавить', style: TextStyle(color: s.secondaryTextColor.withOpacity(0.55), fontSize: 13)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding:   const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: _subscriptions.length,
              itemBuilder: (_, index) {
                final sub       = _subscriptions[index];
                final updating  = _updatingSubscriptions[sub.id] ?? false;
                return _SubscriptionCard(
                  sub:        sub,
                  isUpdating: updating,
                  onUpdate:   () => _updateSubscription(sub),
                  onDelete:   () => _deleteSubscription(sub),
                  onToggleAutoUpdate: (v) => _toggleAutoUpdate(sub, v),
                  settings:   s,
                );
              },
            ),
          ),
      ],
    );
  }
}

// ─── Карточка подписки ─────────────────────────────────────────────────────────
class _SubscriptionCard extends StatelessWidget {
  final Subscription sub;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final Function(bool) onToggleAutoUpdate;
  final ThemeSettings settings;

  const _SubscriptionCard({
    required this.sub,
    required this.isUpdating,
    required this.onUpdate,
    required this.onDelete,
    required this.onToggleAutoUpdate,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        s.cardColor,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: s.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок + кнопки
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: s.textColor)),
                    const SizedBox(height: 3),
                    Text('${sub.serverCount} серверов',
                        style: TextStyle(color: s.secondaryTextColor, fontSize: 12)),
                  ],
                ),
              ),
              _IconBtn(
                icon:     isUpdating
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: s.primaryColor))
                    : Icon(Icons.refresh_rounded, size: 18, color: s.primaryColor),
                tooltip:  'Обновить',
                onTap:    isUpdating ? null : onUpdate,
                settings: s,
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon:     Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                tooltip:  'Удалить',
                onTap:    onDelete,
                settings: s,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // URL
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:        s.searchBarColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sub.url,
              style: TextStyle(
                fontSize:   11,
                color:      s.secondaryTextColor,
                fontFamily: 'monospace',
              ),
              maxLines:  2,
              overflow:  TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          // Нижняя строка: дата + автообновление
          Row(
            children: [
              Icon(Icons.schedule, size: 13, color: s.secondaryTextColor.withOpacity(0.6)),
              const SizedBox(width: 4),
              Text(
                'Обновлено: ${_formatDate(sub.lastUpdated)}',
                style: TextStyle(fontSize: 11, color: s.secondaryTextColor.withOpacity(0.7)),
              ),
              const Spacer(),
              Text('Автообновление',
                  style: TextStyle(fontSize: 11, color: s.secondaryTextColor)),
              const SizedBox(width: 6),
              Switch(
                value:       sub.autoUpdate,
                onChanged:   onToggleAutoUpdate,
                activeColor: s.primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours  < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays   < 1) return '${diff.inHours} ч назад';
    if (diff.inDays  == 1) return 'вчера';
    if (diff.inDays   < 7) return '${diff.inDays} дн назад';
    return '${date.day}.${date.month}.${date.year}';
  }
}

// ─── Иконка-кнопка ────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback? onTap;
  final ThemeSettings settings;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width:  34,
          height: 34,
          decoration: BoxDecoration(
            color:        settings.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

// ─── Поле ввода с темой ────────────────────────────────────────────────────────
class _ThemedField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final ThemeSettings settings;
  final int maxLines;

  const _ThemedField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.settings,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: s.secondaryTextColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines:   maxLines,
          style:      TextStyle(color: s.textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText:  hint,
            hintStyle: TextStyle(color: s.secondaryTextColor.withOpacity(0.5), fontSize: 13),
            filled:    true,
            fillColor: s.searchBarColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:   BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }
}

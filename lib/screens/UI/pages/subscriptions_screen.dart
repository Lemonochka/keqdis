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
  bool _isLoading = true;
  bool _isUpdating = false;
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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomNotification.show(
          context,
          message: 'Ошибка загрузки: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    bool autoUpdate = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeManager().settings.accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Добавить подписку'),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    hintText: 'Например: Моя подписка',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL подписки',
                    hintText: 'https://example.com/subscription',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Автообновление'),
                  subtitle: const Text('Обновлять автоматически каждые 12 часов'),
                  value: autoUpdate,
                  activeColor: ThemeManager().settings.primaryColor,
                  onChanged: (value) => setDialogState(() => autoUpdate = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ThemeManager().settings.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();

      if (name.isEmpty || url.isEmpty) {
        CustomNotification.show(
          context,
          message: 'Заполните все поля',
          type: NotificationType.warning,
        );
        return;
      }

      try {
        // Добавляем подписку
        final subscription = await SubscriptionService.addSubscription(
          name: name,
          url: url,
          autoUpdate: autoUpdate,
        );

        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Подписка добавлена, загрузка серверов...',
            type: NotificationType.success,
          );
          _loadSubscriptions();

          // Сразу же загружаем серверы из подписки
          final updateResult = await SubscriptionService.updateSubscriptionServers(subscription);

          if (updateResult.success) {
            CustomNotification.show(
              context,
              message: 'Загружено ${updateResult.serverCount} серверов',
              type: NotificationType.success,
            );
            _loadSubscriptions();
            widget.onServersUpdated(); // Обновляем список серверов
          } else {
            CustomNotification.show(
              context,
              message: 'Ошибка загрузки серверов: ${updateResult.error}',
              type: NotificationType.warning,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Ошибка: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _updateSubscription(Subscription subscription) async {
    setState(() => _updatingSubscriptions[subscription.id] = true);

    try {
      final result = await SubscriptionService.updateSubscriptionServers(subscription);

      if (mounted) {
        setState(() => _updatingSubscriptions[subscription.id] = false);

        if (result.success) {
          CustomNotification.show(
            context,
            message: 'Обновлено: ${result.serverCount} серверов',
            type: NotificationType.success,
          );
          _loadSubscriptions();
          widget.onServersUpdated();
        } else {
          CustomNotification.show(
            context,
            message: 'Ошибка: ${result.error}',
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingSubscriptions[subscription.id] = false);
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _updateAllSubscriptions() async {
    setState(() => _isUpdating = true);

    try {
      final results = await SubscriptionService.updateAllSubscriptions();

      if (mounted) {
        setState(() => _isUpdating = false);

        final successCount = results.where((r) => r.success).length;
        final totalServers = results.fold<int>(0, (sum, r) => sum + r.serverCount);

        CustomNotification.show(
          context,
          message: 'Обновлено $successCount подписок, добавлено $totalServers серверов',
          type: NotificationType.success,
        );

        _loadSubscriptions();
        widget.onServersUpdated();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteSubscription(Subscription subscription) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeManager().settings.accentColor,
        title: const Text('Удалить подписку?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Название: ${subscription.name}'),
            const SizedBox(height: 8),
            Text('Серверов: ${subscription.serverCount}'),
            const SizedBox(height: 16),
            const Text(
              'Серверы из этой подписки также будут удалены.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await SubscriptionService.removeSubscriptionServers(subscription);
        await SubscriptionService.deleteSubscription(subscription.id);

        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Подписка удалена',
            type: NotificationType.success,
          );
          _loadSubscriptions();
          widget.onServersUpdated();
        }
      } catch (e) {
        if (mounted) {
          CustomNotification.show(
            context,
            message: 'Ошибка: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<void> _toggleAutoUpdate(Subscription subscription, bool value) async {
    try {
      final updated = subscription.copyWith(autoUpdate: value);
      await SubscriptionService.updateSubscription(updated);
      _loadSubscriptions();
    } catch (e) {
      if (mounted) {
        CustomNotification.show(
          context,
          message: 'Ошибка: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Заголовок с кнопками
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'Подписки',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: themeManager.settings.primaryColor,
                ),
              ),
              const Spacer(),
              // Кнопка обновить все
              IconButton(
                icon: _isUpdating
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.refresh),
                tooltip: 'Обновить все подписки',
                onPressed: _isUpdating ? null : _updateAllSubscriptions,
              ),
              // Кнопка добавить
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Добавить подписку',
                onPressed: _showAddDialog,
              ),
            ],
          ),
        ),

        // Список подписок
        if (_subscriptions.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.rss_feed,
                    size: 64,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет подписок',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Нажмите + чтобы добавить',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _subscriptions.length,
              itemBuilder: (context, index) {
                final subscription = _subscriptions[index];
                final isUpdating = _updatingSubscriptions[subscription.id] ?? false;

                return Card(
                  color: themeManager.settings.accentColor.withOpacity(0.3),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Заголовок с кнопками
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subscription.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Серверов: ${subscription.serverCount}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Кнопка обновить
                            IconButton(
                              icon: isUpdating
                                  ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                                  : const Icon(Icons.refresh, size: 20),
                              onPressed: isUpdating
                                  ? null
                                  : () => _updateSubscription(subscription),
                              tooltip: 'Обновить',
                            ),
                            // Кнопка удалить
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              onPressed: () => _deleteSubscription(subscription),
                              tooltip: 'Удалить',
                              color: Colors.red.withOpacity(0.7),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // URL
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            subscription.url,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Информация и переключатель автообновления
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Обновлено: ${_formatDate(subscription.lastUpdated)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Автообновление',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            Switch(
                              value: subscription.autoUpdate,
                              onChanged: (value) =>
                                  _toggleAutoUpdate(subscription, value),
                              activeColor: themeManager.settings.primaryColor,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    if (diff.inDays == 1) return 'вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';

    return '${date.day}.${date.month}.${date.year}';
  }
}
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/services/improved_subscription_service.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/storages/unified_storage.dart';
import 'package:keqdis/localization/app_localization.dart';

class SubscriptionsView extends StatefulWidget {
  final VoidCallback onServersUpdated;

  const SubscriptionsView({super.key, required this.onServersUpdated});

  @override
  State<SubscriptionsView> createState() => _SubscriptionsViewState();
}

class _SubscriptionsViewState extends State<SubscriptionsView> {
  List<Subscription> _subscriptions = [];
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isEditMode = false;
  final Map<String, bool> _collapsedSubscriptions = {};
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
          final ids = subs.map((e) => e.id).toSet();
          _collapsedSubscriptions.removeWhere(
            (key, value) => !ids.contains(key),
          );
          for (final sub in subs) {
            _collapsedSubscriptions.putIfAbsent(sub.id, () => false);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('subscriptions_load_error')
              .replaceFirst('{error}', '$e'),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _showAddDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool autoUpdate = true;
    final s = ThemeManager().settings;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
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
                Text(
                  context.tr('subscriptions_add'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: s.textColor,
                  ),
                ),
                const SizedBox(height: 20),
                _ThemedField(
                  label: context.tr('subscriptions_name'),
                  hint: context.tr('subscriptions_name_hint'),
                  controller: nameCtrl,
                  settings: s,
                ),
                const SizedBox(height: 14),
                _ThemedField(
                  label: context.tr('subscriptions_url'),
                  hint: context.tr('subscriptions_url_hint'),
                  controller: urlCtrl,
                  settings: s,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('subscriptions_auto_update_12h'),
                        style: TextStyle(fontSize: 13, color: s.textColor),
                      ),
                    ),
                    Switch(
                      value: autoUpdate,
                      onChanged: (v) => setDState(() => autoUpdate = v),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(context.tr('subscriptions_cancel')),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          context.tr('subscriptions_add_button'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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
    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      CustomNotification.show(
        context,
        message: AppLocalization().t('subscriptions_fill_all_fields'),
        type: NotificationType.warning,
      );
      return;
    }

    final effectiveName = name.isNotEmpty ? name : _defaultSubscriptionName(url);

    try {
      final sub = await SubscriptionService.addSubscription(
        name: effectiveName,
        url: url,
        autoUpdate: autoUpdate,
      );
      CustomNotification.show(
        context,
        message: AppLocalization().t('subscriptions_added_loading'),
        type: NotificationType.success,
      );
      _loadSubscriptions();

      final res = await SubscriptionService.updateSubscriptionServers(sub);
      if (res.success) {
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('subscriptions_loaded_servers')
              .replaceFirst('{count}', '${res.serverCount}'),
          type: NotificationType.success,
        );
        _loadSubscriptions();
        widget.onServersUpdated();
      } else {
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('subscriptions_error')
              .replaceFirst('{error}', '${res.error}'),
          type: NotificationType.warning,
        );
      }
    } catch (e) {
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('subscriptions_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
    }
  }

  String _defaultSubscriptionName(String url) {
    final uri = Uri.tryParse(url.trim());
    final host = (uri?.host ?? '').trim().toLowerCase();
    if (host.isNotEmpty) {
      return host.startsWith('www.') ? host.substring(4) : host;
    }
    return 'Subscription';
  }

  Future<void> _updateSubscription(Subscription sub) async {
    setState(() => _updatingSubscriptions[sub.id] = true);
    try {
      final res = await SubscriptionService.updateSubscriptionServers(sub);
      if (mounted) {
        setState(() => _updatingSubscriptions[sub.id] = false);
        if (res.success) {
          CustomNotification.show(
            context,
            message: AppLocalization()
                .t('subscriptions_loaded_servers')
                .replaceFirst('{count}', '${res.serverCount}'),
            type: NotificationType.success,
          );
          _loadSubscriptions();
          widget.onServersUpdated();
        } else {
          CustomNotification.show(
            context,
            message: AppLocalization()
                .t('subscriptions_error')
                .replaceFirst('{error}', '${res.error}'),
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updatingSubscriptions[sub.id] = false);
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('subscriptions_error')
              .replaceFirst('{error}', '$e'),
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
        final ok = results.where((r) => r.success).length;
        final servers = results.fold<int>(0, (s, r) => s + r.serverCount);
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('subscriptions_updated_summary')
              .replaceFirst('{ok}', '$ok')
              .replaceFirst('{servers}', '$servers'),
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
          message: AppLocalization()
              .t('subscriptions_error')
              .replaceFirst('{error}', '$e'),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _deleteSubscription(Subscription sub) async {
    final s = ThemeManager().settings;
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
              Text(
                context.tr('subscriptions_delete_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: s.textColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${sub.name}   •   ${sub.serverCount} серв.',
                style: TextStyle(color: s.secondaryTextColor, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalization().t('subscriptions_delete_warning'),
                style: TextStyle(color: Colors.orange.shade400, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: s.secondaryTextColor,
                        side: BorderSide(color: s.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(context.tr('subscriptions_cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(context.tr('subscriptions_delete')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true || !mounted) return;
    try {
      await SubscriptionService.removeSubscriptionServers(sub);
      await SubscriptionService.deleteSubscription(sub.id);
      CustomNotification.show(
        context,
        message: AppLocalization().t('subscriptions_deleted'),
        type: NotificationType.success,
      );
      _loadSubscriptions();
      widget.onServersUpdated();
    } catch (e) {
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('subscriptions_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _toggleAutoUpdate(Subscription sub, bool value) async {
    try {
      await SubscriptionService.updateSubscription(
        sub.copyWith(autoUpdate: value),
      );
      _loadSubscriptions();
    } catch (e) {
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('subscriptions_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _reorderSubscriptionsByIndex(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex) return;
    setState(() {
      final moved = _subscriptions.removeAt(fromIndex);
      _subscriptions.insert(toIndex, moved);
    });
    try {
      await SubscriptionService.reorderSubscriptions(
        _subscriptions.map((e) => e.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('subscriptions_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
      _loadSubscriptions();
    }
  }

  Future<void> _showEditDialog(Subscription sub) async {
    final s = ThemeManager().settings;
    final nameCtrl = TextEditingController(text: sub.name);
    final urlCtrl = TextEditingController(text: sub.url);
    bool autoUpdate = sub.autoUpdate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            decoration: BoxDecoration(
              color: s.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: s.borderColor),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('subscriptions_edit_title'),
                  style: TextStyle(
                    color: s.textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _ThemedField(
                  label: context.tr('subscriptions_name'),
                  hint: context.tr('subscriptions_name_hint'),
                  controller: nameCtrl,
                  settings: s,
                ),
                const SizedBox(height: 10),
                _ThemedField(
                  label: context.tr('subscriptions_url'),
                  hint: context.tr('subscriptions_url_hint'),
                  controller: urlCtrl,
                  settings: s,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('subscriptions_auto_update'),
                        style: TextStyle(
                          color: s.secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Switch(
                      value: autoUpdate,
                      onChanged: (v) => setDState(() => autoUpdate = v),
                      activeColor: s.primaryColor,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.tr('subscriptions_cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(context.tr('save')),
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

    if (ok != true) return;
    try {
      await SubscriptionService.updateSubscription(
        sub.copyWith(
          name: nameCtrl.text.trim(),
          url: urlCtrl.text.trim(),
          autoUpdate: autoUpdate,
        ),
      );
      await _loadSubscriptions();
    } catch (e) {
      if (!mounted) return;
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('subscriptions_error')
            .replaceFirst('{error}', '$e'),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ThemeManager().settings;
    final isDesktop = MediaQuery.of(context).size.width >= 1000;

    if (_isLoading)
      return Center(child: CircularProgressIndicator(color: s.primaryColor));

    return Column(
      children: [
        // Заголовок
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Text(
                context.tr('subscriptions_title'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: s.textColor,
                ),
              ),
              const Spacer(),
              // Обновить все
              _IconBtn(
                icon: _isUpdating
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: s.primaryColor,
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: s.primaryColor,
                      ),
                tooltip: context.tr('subscriptions_update_all'),
                onTap: _isUpdating ? null : _updateAllSubscriptions,
                settings: s,
              ),
              const SizedBox(width: 8),
              // Добавить
              _IconBtn(
                icon: Icon(Icons.add_rounded, size: 20, color: s.primaryColor),
                tooltip: context.tr('subscriptions_add'),
                onTap: _showAddDialog,
                settings: s,
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: Icon(
                  _isEditMode ? Icons.check_rounded : Icons.edit_rounded,
                  size: 20,
                  color: s.primaryColor,
                ),
                tooltip: _isEditMode
                    ? context.tr('done')
                    : context.tr('subscriptions_edit'),
                onTap: () => setState(() => _isEditMode = !_isEditMode),
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
                  Icon(
                    Icons.rss_feed,
                    size: 60,
                    color: s.secondaryTextColor.withOpacity(0.25),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('subscriptions_empty'),
                    style: TextStyle(color: s.secondaryTextColor, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('subscriptions_empty_hint'),
                    style: TextStyle(
                      color: s.secondaryTextColor.withOpacity(0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final columns = isDesktop ? 2 : 1;
                final cardWidth = columns == 1
                    ? constraints.maxWidth - 32
                    : (constraints.maxWidth - 32 - gap) / 2;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: List.generate(_subscriptions.length, (index) {
                      final sub = _subscriptions[index];
                      final updating = _updatingSubscriptions[sub.id] ?? false;
                      final card = _SubscriptionCard(
                        sub: sub,
                        isUpdating: updating,
                        onUpdate: () => _updateSubscription(sub),
                        onDelete: () => _deleteSubscription(sub),
                        onToggleAutoUpdate: (v) => _toggleAutoUpdate(sub, v),
                        onEdit: () => _showEditDialog(sub),
                        isCollapsed: _collapsedSubscriptions[sub.id] ?? false,
                        onToggleCollapse: () => setState(() {
                          _collapsedSubscriptions[sub.id] =
                              !(_collapsedSubscriptions[sub.id] ?? false);
                        }),
                        settings: s,
                        editMode: _isEditMode,
                      );

                      Widget content = card;
                      if (_isEditMode) {
                        content = DragTarget<int>(
                          onWillAcceptWithDetails: (details) =>
                              details.data != index,
                          onAcceptWithDetails: (details) =>
                              _reorderSubscriptionsByIndex(details.data, index),
                          builder: (context, candidateData, rejectedData) {
                            final highlighted = candidateData.isNotEmpty;
                            return Draggable<int>(
                              data: index,
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: cardWidth,
                                  child: Opacity(opacity: 0.88, child: card),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: card,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: highlighted
                                      ? Border.all(
                                          color: s.primaryColor,
                                          width: 1.6,
                                        )
                                      : null,
                                ),
                                child: card,
                              ),
                            );
                          },
                        );
                      }

                      return SizedBox(width: cardWidth, child: content);
                    }),
                  ),
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
  final VoidCallback onEdit;
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final ThemeSettings settings;
  final bool editMode;

  const _SubscriptionCard({
    required this.sub,
    required this.isUpdating,
    required this.onUpdate,
    required this.onDelete,
    required this.onToggleAutoUpdate,
    required this.onEdit,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.settings,
    this.editMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final canUseSpacer = constraints.maxHeight.isFinite;
        return Container(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: s.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: s.borderColor),
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
                        Text(
                          sub.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: s.textColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr('subscriptions_servers_count').replaceFirst(
                                '{count}',
                                '${sub.serverCount}',
                              ),
                          style: TextStyle(
                            color: s.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _IconBtn(
                    icon: Icon(
                      isCollapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: s.secondaryTextColor,
                    ),
                    tooltip: isCollapsed
                        ? context.tr('subscriptions_expand')
                        : context.tr('subscriptions_collapse'),
                    onTap: onToggleCollapse,
                    settings: s,
                  ),
                  const SizedBox(width: 6),
                  _IconBtn(
                    icon: Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: s.secondaryTextColor,
                    ),
                    tooltip: context.tr('subscriptions_edit'),
                    onTap: onEdit,
                    settings: s,
                  ),
                  const SizedBox(width: 6),
                  _IconBtn(
                    icon: isUpdating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: s.primaryColor,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            size: 18,
                            color: s.primaryColor,
                          ),
                    tooltip: context.tr('subscriptions_update'),
                    onTap: isUpdating ? null : onUpdate,
                    settings: s,
                  ),
                  const SizedBox(width: 6),
                  _IconBtn(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red.shade400,
                    ),
                    tooltip: context.tr('subscriptions_delete'),
                    onTap: onDelete,
                    settings: s,
                  ),
                  if (editMode) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: s.searchBarColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: s.borderColor),
                      ),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 18,
                        color: s.secondaryTextColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              if (!isCollapsed) ...[
                // URL
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: s.searchBarColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    sub.url,
                    style: TextStyle(
                      fontSize: 11,
                      color: s.secondaryTextColor,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canUseSpacer)
                  const Spacer()
                else
                  const SizedBox(height: 18),

                // Нижний блок: прижат к низу карточки
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 13,
                                color: s.secondaryTextColor.withOpacity(0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                context
                                    .tr('subscriptions_updated_at')
                                    .replaceFirst(
                                      '{date}',
                                      _formatDate(sub.lastUpdated),
                                    ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: s.secondaryTextColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.data_usage_rounded,
                                size: 14,
                                color: s.secondaryTextColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('subscriptions_traffic')
                                    .replaceFirst(
                                      '{used}',
                                      _formatBytes((sub.trafficUploadBytes ?? 0) +
                                          (sub.trafficDownloadBytes ?? 0)),
                                    )
                                    .replaceFirst(
                                      '{total}',
                                      sub.trafficTotalBytes != null &&
                                              sub.trafficTotalBytes! > 0
                                          ? _formatBytes(sub.trafficTotalBytes!)
                                          : '∞',
                                    ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: s.secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                          if (sub.expiresAt != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.hourglass_bottom_rounded,
                                  size: 14,
                                  color: sub.expiresAt!.isBefore(DateTime.now())
                                      ? Colors.redAccent
                                      : s.secondaryTextColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _formatExpiry(sub.expiresAt!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        sub.expiresAt!.isBefore(DateTime.now())
                                        ? Colors.redAccent
                                        : s.secondaryTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          context.tr('subscriptions_auto_update'),
                          style: TextStyle(
                            fontSize: 11,
                            color: s.secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Switch(
                          value: sub.autoUpdate,
                          onChanged: onToggleAutoUpdate,
                          activeColor: s.primaryColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return AppLocalization().t('just_now');
    if (diff.inHours < 1) {
      return AppLocalization()
          .t('minutes_ago')
          .replaceFirst('{minutes}', '${diff.inMinutes}');
    }
    if (diff.inDays < 1) {
      return AppLocalization()
          .t('hours_ago')
          .replaceFirst('{hours}', '${diff.inHours}');
    }
    if (diff.inDays == 1) return AppLocalization().t('yesterday');
    if (diff.inDays < 7) {
      return AppLocalization()
          .t('days_ago')
          .replaceFirst('{days}', '${diff.inDays}');
    }
    return '${date.day}.${date.month}.${date.year}';
  }

  String _formatExpiry(DateTime expiresAt) {
    final now = DateTime.now();
    if (expiresAt.isBefore(now)) {
      return AppLocalization().t('expiry_passed');
    }
    final diff = expiresAt.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) {
      return AppLocalization()
          .t('expiry_left_days_hours')
          .replaceFirst('{days}', '$days')
          .replaceFirst('{hours}', '$hours');
    }
    return AppLocalization()
        .t('expiry_left_hours_minutes')
        .replaceFirst('{hours}', '${diff.inHours}')
        .replaceFirst('{minutes}', '$mins');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final frac = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(frac)} ${units[unitIndex]}';
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: settings.primaryColor.withOpacity(0.1),
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
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: s.secondaryTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: s.textColor, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: s.secondaryTextColor.withOpacity(0.5),
              fontSize: 13,
            ),
            filled: true,
            fillColor: s.searchBarColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }
}

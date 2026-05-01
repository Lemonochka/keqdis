import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:keqdis/screens/improved_theme_manager.dart';
import 'package:keqdis/screens/UI/widgets/custom_notification.dart';
import 'package:keqdis/localization/app_localization.dart';
import 'package:keqdis/services/installed_apps_service.dart';
import 'package:keqdis/storages/app_routing_storage.dart';

class AppRoutingPage extends StatefulWidget {
  final bool isVpnConnected;

  final VoidCallback? onReconnectRequest;

  const AppRoutingPage({
    super.key,
    this.isVpnConnected = false,
    this.onReconnectRequest,
  });

  @override
  State<AppRoutingPage> createState() => _AppRoutingPageState();
}

class _AppRoutingPageState extends State<AppRoutingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<InstalledApp> _installedApps = [];
  List<InstalledApp> _runningApps = [];
  List<InstalledApp> _filtered = [];

  Set<String> _vpnApps = {};
  AppRoutingMode _routingMode = AppRoutingMode.allProxy;
  bool _pendingRestart = false;

  bool _isLoading = false;
  bool _loadError = false;
  String _searchQuery = '';

  Timer? _saveDebounce;
  final _searchCtrl = TextEditingController();
  final _manualExeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabSwitch);
    Timer(Duration.zero, () { if (mounted) _init(); });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabSwitch);
    _tabController.dispose();
    _saveDebounce?.cancel();
    _searchCtrl.dispose();
    _manualExeCtrl.dispose();
    super.dispose();
  }

  void _onTabSwitch() {
    if (_tabController.indexIsChanging) return;
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _filtered = _buildDisplayList(_currentList, '');
    });
  }

  List<InstalledApp> get _currentList =>
      _tabController.index == 0 ? _installedApps : _runningApps;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    Timer(Duration.zero, () { if (mounted) setState(fn); });
  }

  Future<void> _init() async {
    try {
      final data = await AppRoutingStorage.load();
      _safeSetState(() {
        _vpnApps = data.apps;
        _routingMode = data.mode;
      });
    } catch (_) {}
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    _safeSetState(() { _isLoading = true; _loadError = false; });
    try {
      if (_tabController.index == 0) {
        final apps = await InstalledAppsService.getInstalledApps();
        _safeSetState(() {
          _installedApps = apps;
          _filtered = _buildDisplayList(apps, _searchQuery);
        });
      } else {
        final apps = await InstalledAppsService.getRunningProcesses();
        _safeSetState(() {
          _runningApps = apps;
          _filtered = _buildDisplayList(apps, _searchQuery);
        });
      }
      _safeSetState(() => _isLoading = false);
    } catch (_) {
      _safeSetState(() { _isLoading = false; _loadError = true; });
    }
  }

  List<InstalledApp> _buildDisplayList(List<InstalledApp> apps, String q) {
    final presentExes = apps.map((a) => a.executableName).toSet();

    final ghosts = _vpnApps
        .where((exe) => !presentExes.contains(exe))
        .map((exe) => InstalledApp(
      name: exe,
      executableName: exe,
    ))
        .toList();

    final combined = [...ghosts, ...apps];

    final filtered = q.isEmpty
        ? combined
        : combined.where((a) {
      final lq = q.toLowerCase();
      return a.name.toLowerCase().contains(lq) ||
          a.executableName.toLowerCase().contains(lq) ||
          (a.publisher?.toLowerCase().contains(lq) ?? false);
    }).toList();

    filtered.sort((a, b) {
      final aSelected = _vpnApps.contains(a.executableName);
      final bSelected = _vpnApps.contains(b.executableName);
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return filtered;
  }

  void _onSearch(String q) => setState(() {
    _searchQuery = q;
    _filtered = _buildDisplayList(_currentList, q);
  });

  Future<void> _save() =>
      AppRoutingStorage.save(apps: _vpnApps, mode: _routingMode);

  String _normalizeManualExe(String input) {
    var value = input.trim();
    if (value.isEmpty) return '';
    value = value.replaceAll('/', '\\');
    if (value.contains('\\')) {
      final parts = value.split('\\').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) value = parts.last;
    }
    return value;
  }

  Future<void> _addManualExe() async {
    final normalized = _normalizeManualExe(_manualExeCtrl.text);
    if (normalized.isEmpty) {
      CustomNotification.show(
        context,
        message: 'Введите имя процесса, например chrome.exe',
        type: NotificationType.error,
      );
      return;
    }

    final isValid = RegExp(r'^[A-Za-z0-9._\- ]+(\.exe)?$').hasMatch(normalized);
    if (!isValid) {
      CustomNotification.show(
        context,
        message: 'Неверный формат процесса: $normalized',
        type: NotificationType.error,
      );
      return;
    }

    setState(() {
      _vpnApps.add(normalized);
      _manualExeCtrl.clear();
      if (widget.isVpnConnected) _pendingRestart = true;
      _filtered = _buildDisplayList(_currentList, _searchQuery);
    });

    await _save();
    if (mounted) {
      CustomNotification.show(
        context,
        message: 'Добавлен процесс: $normalized',
        type: NotificationType.success,
      );
    }
  }

  void _toggle(InstalledApp app) {
    final exe = app.executableName;
    setState(() {
      _vpnApps.contains(exe) ? _vpnApps.remove(exe) : _vpnApps.add(exe);
      if (widget.isVpnConnected) _pendingRestart = true;
      _filtered = _buildDisplayList(_currentList, _searchQuery);
    });
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      await _save();
      if (mounted) {
        CustomNotification.show(
          context,
          message: AppLocalization()
              .t('apps_saved_count')
              .replaceFirst('{count}', '${_vpnApps.length}'),
          type: NotificationType.success,
        );
      }
    });
  }

  Future<void> _setMode(AppRoutingMode mode) async {
    setState(() {
      _routingMode = mode;
      if (widget.isVpnConnected) _pendingRestart = true;
    });
    await _save();
    if (mounted) {
      CustomNotification.show(
        context,
        message: AppLocalization()
            .t('apps_routing_mode_changed')
            .replaceFirst('{mode}', _modeLabel(mode)),
        type: NotificationType.success,
      );
    }
  }

  String _modeLabel(AppRoutingMode mode) {
    switch (mode) {
      case AppRoutingMode.allProxy:
        return AppLocalization().t('apps_routing_mode_all_proxy');
      case AppRoutingMode.onlySelected:
        return AppLocalization().t('apps_routing_mode_only_selected');
      case AppRoutingMode.allExceptSelected:
        return AppLocalization().t('apps_routing_mode_all_except_selected');
    }
  }

  void _clearAll() {
    setState(() {
      _vpnApps.clear();
      if (widget.isVpnConnected) _pendingRestart = true;
    });
    _save();
    CustomNotification.show(
      context,
      message: AppLocalization().t('apps_list_cleared'),
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager();
    final s = theme.settings;
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final accent = scheme.surface;
    final text = s.textColor;
    final subtext = s.secondaryTextColor;

    return Container(
      decoration: BoxDecoration(
        color: theme.hasCustomBackground
            ? s.cardColor.withOpacity(0.20)
            : Colors.transparent,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _ModeSelector(
              current: _routingMode,
              onChanged: _setMode,
              primary: primary,
              accent: accent,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _pendingRestart && widget.isVpnConnected
                ? _ReconnectBanner(
                    key: const ValueKey('reconnect'),
                    onReconnect: widget.onReconnectRequest != null
                        ? () {
                            setState(() => _pendingRestart = false);
                            widget.onReconnectRequest!();
                          }
                        : null,
                    onDismiss: () => setState(() => _pendingRestart = false),
                  )
                : Container(
                    key: const ValueKey('tun-info'),
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.tertiary.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: scheme.tertiary, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            AppLocalization().t('apps_routing_tun_only_banner'),
                            style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (_routingMode == AppRoutingMode.allProxy) ...[
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 44, color: subtext.withOpacity(0.35)),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalization().t('apps_routing_all_proxy'),
                      style: TextStyle(fontSize: 15, color: text, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      AppLocalization().t('apps_routing_all_proxy_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: subtext),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: s.cardColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s.borderColor),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    final manualInput = Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: s.searchBarColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: s.borderColor),
                      ),
                      child: TextField(
                        controller: _manualExeCtrl,
                        style: TextStyle(fontSize: 12, color: text),
                        decoration: InputDecoration(
                          hintText: 'Добавить exe: myapp.exe или C:\\...\\myapp.exe',
                          hintStyle: TextStyle(color: subtext.withOpacity(0.7), fontSize: 12),
                          prefixIcon: Icon(Icons.add_circle_outline, size: 15, color: subtext.withOpacity(0.8)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                        onSubmitted: (_) => _addManualExe(),
                      ),
                    );
                    final searchInput = Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: s.searchBarColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: s.borderColor),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearch,
                        style: TextStyle(fontSize: 12, color: text),
                        decoration: InputDecoration(
                          hintText: AppLocalization().t('apps_search_hint'),
                          hintStyle: TextStyle(color: subtext.withOpacity(0.7), fontSize: 12),
                          prefixIcon: Icon(Icons.search, size: 15, color: subtext.withOpacity(0.7)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close, size: 13, color: subtext.withOpacity(0.8)),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _onSearch('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        ),
                      ),
                    );

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TabBar(
                                controller: _tabController,
                                onTap: (_) => _loadCurrent(),
                                indicatorColor: primary,
                                indicatorWeight: 2,
                                indicatorSize: TabBarIndicatorSize.tab,
                                labelColor: primary,
                                unselectedLabelColor: subtext,
                                dividerColor: Colors.transparent,
                                indicator: BoxDecoration(
                                  color: primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                tabs: [
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.apps, size: 13),
                                        const SizedBox(width: 4),
                                        Text(AppLocalization().t('apps_tab_installed'), style: const TextStyle(fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                  Tab(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.play_circle_outline, size: 13),
                                        const SizedBox(width: 4),
                                        Text(AppLocalization().t('apps_tab_running'), style: const TextStyle(fontSize: 11.5)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (_vpnApps.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primary.withOpacity(0.28)),
                                ),
                                child: Text(
                                  '${_vpnApps.length}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary),
                                ),
                              ),
                            const SizedBox(width: 4),
                            _iconBtn(Icons.refresh, AppLocalization().t('apps_refresh'), _isLoading ? null : _loadCurrent, subtext),
                            if (_vpnApps.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              _iconBtn(Icons.clear_all, AppLocalization().t('apps_clear_all'), _clearAll, Colors.redAccent.withOpacity(0.75)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 7),
                        if (compact) ...[
                          Row(
                            children: [
                              Expanded(child: manualInput),
                              const SizedBox(width: 6),
                              _iconBtn(Icons.playlist_add, 'Добавить процесс', _addManualExe, primary),
                            ],
                          ),
                          const SizedBox(height: 7),
                          searchInput,
                        ] else ...[
                          Row(
                            children: [
                              Expanded(flex: 5, child: manualInput),
                              const SizedBox(width: 6),
                              _iconBtn(Icons.playlist_add, 'Добавить процесс', _addManualExe, primary),
                              const SizedBox(width: 6),
                              Expanded(flex: 4, child: searchInput),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildContent(primary, accent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback? fn, Color color) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: fn,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 35, height: 35,
            decoration: BoxDecoration(
              color: ThemeManager().settings.cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ThemeManager().settings.borderColor),
            ),
            child: Icon(icon, size: 16,
                color: fn == null ? ThemeManager().settings.secondaryTextColor.withOpacity(0.4) : color),
          ),
        ),
      );

  Widget _buildContent(Color primary, Color accent) {
    final s = ThemeManager().settings;
    if (_isLoading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 26, height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: primary)),
        const SizedBox(height: 10),
        Text(
            _tabController.index == 1
                ? AppLocalization().t('apps_loading_running')
                : AppLocalization().t('apps_loading_installed'),
            style: TextStyle(
                color: s.secondaryTextColor.withOpacity(0.8), fontSize: 12)),
      ]));
    }

    if (_loadError) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 36,
            color: Colors.redAccent.withOpacity(0.5)),
        const SizedBox(height: 8),
        Text(AppLocalization().t('apps_load_failed'),
            style: TextStyle(
                color: s.secondaryTextColor.withOpacity(0.9), fontSize: 13)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loadCurrent,
          icon: const Icon(Icons.refresh, size: 14),
          label: Text(AppLocalization().t('apps_retry')),
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: primary.withOpacity(0.4)),
          ),
        ),
      ]));
    }

    if (_currentList.isEmpty) {
      return Center(child: Text(
          _tabController.index == 1
              ? AppLocalization().t('apps_no_running')
              : AppLocalization().t('apps_not_found'),
          style: TextStyle(
              color: s.secondaryTextColor.withOpacity(0.8), fontSize: 13)));
    }

    if (_filtered.isEmpty) {
      return Center(child: Text(
          AppLocalization()
              .t('apps_nothing_found')
              .replaceFirst('{query}', _searchQuery),
          style: TextStyle(
              color: s.secondaryTextColor.withOpacity(0.8), fontSize: 13)));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
      itemCount: _filtered.length,
      cacheExtent: 400,
      itemBuilder: (ctx, i) {
        final app = _filtered[i];
        final sel = _vpnApps.contains(app.executableName);
        return _AppTile(app: app, isSelected: sel,
            onTap: () => _toggle(app), primary: primary, accent: accent);
      },
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  final VoidCallback? onReconnect;
  final VoidCallback onDismiss;

  const _ReconnectBanner({
    super.key,
    required this.onReconnect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = ThemeManager().settings;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.tertiary.withOpacity(0.45)),
      ),
      child: Row(children: [
        Icon(Icons.sync_problem_rounded, color: scheme.tertiary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalization().t('apps_settings_changed'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onTertiaryContainer),
              ),
              const SizedBox(height: 1),
              Text(
                AppLocalization().t('apps_reconnect_required'),
                style: TextStyle(
                    fontSize: 10, color: scheme.onTertiaryContainer.withOpacity(0.8)),
              ),
            ],
          ),
        ),
        if (onReconnect != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onReconnect,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.tertiary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(7),
                border:
                Border.all(color: scheme.tertiary.withOpacity(0.55)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded,
                    size: 13, color: scheme.tertiary),
                const SizedBox(width: 4),
                Text(AppLocalization().t('apps_reconnect'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: scheme.tertiary)),
              ]),
            ),
          ),
        ],
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onDismiss,
          child: Icon(Icons.close, size: 15,
              color: s.secondaryTextColor.withOpacity(0.7)),
        ),
      ]),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final AppRoutingMode current;
  final ValueChanged<AppRoutingMode> onChanged;
  final Color primary;
  final Color accent;

  const _ModeSelector({required this.current, required this.onChanged,
    required this.primary, required this.accent});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppLocalization().t('apps_routing_mode_title'),
          style: TextStyle(fontSize: 11,
              color: ThemeManager().settings.secondaryTextColor.withOpacity(0.8),
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Row(children: AppRoutingMode.values.map((m) {
        final last = m == AppRoutingMode.values.last;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: last ? 0 : 6),
          child: _ModeBtn(mode: m, selected: current == m,
              onTap: () => onChanged(m), primary: primary, accent: accent),
        ));
      }).toList()),
    ],
  );
}

class _ModeBtn extends StatelessWidget {
  final AppRoutingMode mode;
  final bool selected;
  final VoidCallback onTap;
  final Color primary;
  final Color accent;

  const _ModeBtn({required this.mode, required this.selected,
    required this.onTap, required this.primary, required this.accent});

  IconData get _icon => switch (mode) {
    AppRoutingMode.allProxy          => Icons.public,
    AppRoutingMode.onlySelected      => Icons.tune,
    AppRoutingMode.allExceptSelected => Icons.block,
  };

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? primary.withOpacity(0.14) : ThemeManager().settings.cardColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? primary.withOpacity(0.55) : ThemeManager().settings.borderColor,
          width: selected ? 1.5 : 1.0,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, size: 17,
            color: selected ? primary : ThemeManager().settings.secondaryTextColor),
        const SizedBox(height: 3),
        Text(_label(context), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? ThemeManager().settings.textColor : ThemeManager().settings.secondaryTextColor)),
      ]),
    ),
  );

  String _label(BuildContext context) {
    switch (mode) {
      case AppRoutingMode.allProxy:
        return context.tr('apps_routing_mode_all_proxy');
      case AppRoutingMode.onlySelected:
        return context.tr('apps_routing_mode_only_selected');
      case AppRoutingMode.allExceptSelected:
        return context.tr('apps_routing_mode_all_except_selected');
    }
  }
}

class _AppTile extends StatelessWidget {
  final InstalledApp app;
  final bool isSelected;
  final VoidCallback onTap;
  final Color primary;
  final Color accent;

  const _AppTile({required this.app, required this.isSelected,
    required this.onTap, required this.primary, required this.accent});

  static const _palette = [
    Color(0xFF5C6BC0), Color(0xFF42A5F5), Color(0xFF26A69A),
    Color(0xFF66BB6A), Color(0xFFEF5350), Color(0xFFAB47BC),
    Color(0xFFFF7043), Color(0xFF26C6DA),
  ];

  Color get _fallbackColor {
    final code = app.name.isNotEmpty ? app.name.codeUnitAt(0) : 0;
    return _palette[code % _palette.length];
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withOpacity(0.11)
                : ThemeManager().settings.cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? primary.withOpacity(0.38)
                  : ThemeManager().settings.borderColor,
              width: isSelected ? 1.2 : 1.0,
            ),
          ),
          child: Row(children: [
            _AppIcon(app: app, size: 36, fallbackColor: _fallbackColor),
            const SizedBox(width: 10),

            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(app.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600 : FontWeight.w400,
                        color: ThemeManager().settings.textColor),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (app.installLocation == null &&
                    app.publisher == null &&
                    app.executablePath == null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.schedule, size: 10,
                        color: ThemeManager().settings.secondaryTextColor.withOpacity(0.7)),
                    const SizedBox(width: 3),
                    Text('Не найдено в текущем списке',
                        style: TextStyle(fontSize: 10,
                            color: ThemeManager().settings.secondaryTextColor.withOpacity(0.7))),
                  ]),
                ] else if (app.publisher?.isNotEmpty == true) ...[
                  const SizedBox(height: 1),
                  Text(app.publisher!,
                      style: TextStyle(fontSize: 11,
                          color: ThemeManager().settings.secondaryTextColor.withOpacity(0.8)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            )),

            const SizedBox(width: 8),
            // exe-бейдж
            Container(
              constraints: const BoxConstraints(maxWidth: 115),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: ThemeManager().settings.searchBarColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ThemeManager().settings.borderColor),
              ),
              child: Text(app.executableName,
                  style: TextStyle(fontSize: 10,
                      color: ThemeManager().settings.secondaryTextColor.withOpacity(0.8),
                      fontFamily: 'monospace'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),

            const SizedBox(width: 9),
            // Чекбокс
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 19, height: 19,
              decoration: BoxDecoration(
                color: isSelected ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? primary : ThemeManager().settings.borderColor,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ]),
        ),
      ),
    ),
  );
}

class _AppIcon extends StatelessWidget {
  final InstalledApp app;
  final double size;
  final Color fallbackColor;

  const _AppIcon({
    required this.app,
    required this.size,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(app.iconBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.memory(
            bytes,
            width: size, height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(),
          ),
        );
      } catch (_) {}
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: fallbackColor.withOpacity(0.7),
      borderRadius: BorderRadius.circular(7),
    ),
    alignment: Alignment.center,
    child: Text(
      app.name.isNotEmpty ? app.name[0].toUpperCase() : '?',
      style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.bold, color: Colors.white),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../model/view_settings.dart';
import '../platform/files.dart';
import '../settings/prefs.dart';
import '../viewer/source.dart';
import 'app_state.dart';
import 'dialogs/dialogs.dart';
import 'panel/controls_panel.dart';
import 'panel/quick_bar.dart';
import 'plot/overview_strip.dart';
import 'plot/alt_views.dart';
import 'plot/trace_painter.dart';
import 'stream_controller.dart';
import 'widgets/widgets.dart';

/// Narrower than this, the controls panel moves into a bottom sheet and the
/// menu bar into an app bar.
const _narrow = narrowWidth;

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS);

class MainWindow extends StatefulWidget {
  final AppState state;
  final List<String> initialFiles;

  const MainWindow({
    super.key,
    required this.state,
    this.initialFiles = const [],
  });

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> {
  bool _dropHover = false;

  AppState get app => widget.state;
  Preferences get prefs => app.prefs;
  ViewerConfig get config => app.config;

  @override
  void initState() {
    super.initState();
    for (final p in app.providers) {
      p.start();
    }
    if (touchPlatform) {
      _mice.addListener(_inputChanged);
      HardwareKeyboard.instance.addHandler(_sawKey);
    }
    final picked = [for (final p in widget.initialFiles) ?fileAtPath(p)];
    if (picked.isNotEmpty) app.openFiles(picked);
  }

  MouseTracker get _mice => RendererBinding.instance.mouseTracker;
  bool _keyboard = false;

  /// Whether keyboard and mouse help is useful: always on desktop, and on
  /// phones and tablets once a mouse is connected or a hardware key was
  /// pressed (there is no way to ask whether a keyboard is attached).
  bool get _keysOrMouse =>
      !touchPlatform || _keyboard || _mice.mouseIsConnected;

  void _inputChanged() {
    if (mounted) setState(() {});
  }

  bool _sawKey(KeyEvent event) {
    if (!_keyboard) {
      _keyboard = true;
      HardwareKeyboard.instance.removeHandler(_sawKey);
      // Not during the key's dispatch.
      WidgetsBinding.instance.addPostFrameCallback((_) => _inputChanged());
      WidgetsBinding.instance.scheduleFrame();
    }
    return false;
  }

  @override
  void dispose() {
    _mice.removeListener(_inputChanged);
    HardwareKeyboard.instance.removeHandler(_sawKey);
    super.dispose();
  }

  bool get _opensFiles => app.fileExtensions.isNotEmpty;

  String get _fileTypes =>
      [for (final e in app.fileExtensions) '.$e'].join(', ');

  Future<void> _open() async {
    final blocked = app.blocksFiles;
    if (blocked != null) {
      app.setStatus(blocked);
      return;
    }
    final files = await pickFiles(
      app.fileExtensions,
      initialDirectory: prefs.lastDir,
    );
    if (files.isNotEmpty) await app.openFiles(files);
  }

  void _onDrop(List<PickedFile> files) {
    final blocked = app.blocksFiles;
    if (blocked != null) {
      app.setStatus(blocked);
      return;
    }
    app.openFiles(files);
  }

  Future<void> _sourceSetup() async {
    final streams = app.openStreams;
    if (streams.isEmpty) return;
    final result = await showSourceSetup(
      context,
      streams,
      prefs.sources,
      title: config.setupName,
      groupable: app.groupable,
    );
    if (result != null) app.setSourceAssignments(result);
  }

  Future<void> _renameChannel(TabEntry tab, int ch) async {
    final info = tab.controller.info;
    final stream = tab.group.memberOf(ch);
    final name = await askValue<String>(
      context,
      title: 'Name ${info.deviceLabel(ch)}',
      initial: info.renamed(ch) ? info.labels[ch] : '',
      parse: (t) => t.trim(),
      hint:
          'E.g. its cap position (Cz). Used for ${stream.name} of every '
          'source; empty for the original label. All names: '
          '${config.setupName}.',
      keyboardType: TextInputType.text,
    );
    if (name != null) app.renameChannel(tab, ch, name);
  }

  Future<void> _decoderSettings(StreamController c) async {
    final result = await showDecoderSettings(context, prefs.manchester);
    if (result == null) return;
    prefs.manchester = result;
    await prefs.save();
    for (final t in app.tabs) {
      t.controller.manchester = result;
    }
  }

  /// Choose tabs to show below the current one, on its time axis.
  Future<void> _showBelow() async {
    final tab = app.currentTab;
    if (tab == null) return;
    final chosen = await showTabPicker(context, [
      for (final t in app.tabs)
        if (t != tab) t,
    ], tab.below);
    if (chosen != null) app.showBelow(tab, chosen);
  }

  void _togglePanel() {
    prefs.panelVisible = !prefs.panelVisible;
    prefs.save();
  }

  /// The providers' menu entries and the source setup, by menu, in the
  /// order the menus first appear.
  Map<String, List<ViewerAction>> _actions(BuildContext context) {
    SingleActivator ctrl(LogicalKeyboardKey k) => _isApple
        ? SingleActivator(k, meta: true)
        : SingleActivator(k, control: true);
    final all = [
      for (final p in app.providers) ...p.actions(context),
      ViewerAction(
        config.setupMenu,
        '${config.setupName}…',
        onPressed: app.tabs.isEmpty ? null : _sourceSetup,
        order: 5,
      ),
      // The View menu, after the providers' menus.
      ViewerAction(
        'View',
        'Show controls panel',
        shortcut: ctrl(LogicalKeyboardKey.keyB),
        onPressed: _togglePanel,
        checked: prefs.panelVisible,
        order: 100,
        wideOnly: true,
      ),
      ViewerAction(
        'View',
        'Show tabs below…',
        onPressed: app.tabs.length < 2 ? null : _showBelow,
        order: 101,
        wideOnly: true,
      ),
      ViewerAction(
        'View',
        'Next tab',
        shortcut: const SingleActivator(
          LogicalKeyboardKey.pageDown,
          control: true,
        ),
        onPressed: app.tabs.length < 2
            ? null
            : () => app.current = app.current + 1,
        order: 102,
        wideOnly: true,
      ),
      ViewerAction(
        'View',
        'Previous tab',
        shortcut: const SingleActivator(
          LogicalKeyboardKey.pageUp,
          control: true,
        ),
        onPressed: app.tabs.length < 2
            ? null
            : () => app.current = app.current - 1,
        order: 103,
        wideOnly: true,
      ),
    ];
    final menus = <String, List<(int, ViewerAction)>>{};
    for (final (i, a) in all.indexed) {
      (menus[a.menu] ??= []).add((i, a));
    }
    return {
      for (final e in menus.entries)
        e.key: [
          for (final (_, a)
              in e.value..sort(
                (x, y) => x.$2.order != y.$2.order
                    ? x.$2.order - y.$2.order
                    : x.$1 - y.$1,
              ))
            a,
        ],
    };
  }

  // -- keyboard -------------------------------------------------------------

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final c = app.currentTab?.controller;
    SingleActivator ctrl(LogicalKeyboardKey k) => _isApple
        ? SingleActivator(k, meta: true)
        : SingleActivator(k, control: true);
    return {
      ctrl(LogicalKeyboardKey.keyO): _open,
      for (final p in app.providers) ...p.shortcuts,
      ctrl(LogicalKeyboardKey.keyB): _togglePanel,
      ctrl(LogicalKeyboardKey.keyW): () => app.closeTab(app.current),
      const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () =>
          app.current = app.current + 1,
      const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
          app.current = app.current - 1,
      if (c != null) ...{
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            c.scrollBy(0.1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            c.scrollBy(-0.1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => c.scrollBy(1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => c.scrollBy(-1),
        const SingleActivator(LogicalKeyboardKey.home): () =>
            c.scrollTo(c.source.start),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            c.scrollTo(c.source.end),
        const SingleActivator(LogicalKeyboardKey.equal): () => c.stepWindow(-1),
        const SingleActivator(LogicalKeyboardKey.add): () => c.stepWindow(-1),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
            c.stepWindow(-1),
        const SingleActivator(LogicalKeyboardKey.minus): () => c.stepWindow(1),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            c.stepWindow(1),
      },
    };
  }

  /// Whether the focused widget is a text field, which needs plain keys
  /// (arrows, Home/End, `-`, `+`) for itself.
  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Runs the matching shortcut, like [CallbackShortcuts], except that keys
  /// without a modifier go to a focused text field instead.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final typing = _typing;
    final keys = HardwareKeyboard.instance;
    for (final MapEntry(key: activator, value: callback)
        in _shortcuts().entries) {
      if (typing &&
          activator is SingleActivator &&
          !activator.control &&
          !activator.meta &&
          !activator.alt) {
        continue;
      }
      if (activator.accepts(event, keys)) {
        callback();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // -- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([app, prefs]),
      builder: (context, _) {
        final narrow = MediaQuery.sizeOf(context).width < _narrow;
        final body = Column(
          children: [
            if (!narrow) _menuBar(),
            if (!narrow) _toolbar(),
            Expanded(child: _tabsArea(narrow)),
            _statusBar(),
          ],
        );
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Focus(
            autofocus: true,
            child: fileDropTarget(
              onDrop: _onDrop,
              onHover: (h, _) => setState(() => _dropHover = h),
              child: Scaffold(
                appBar: narrow ? _appBar() : null,
                body: Stack(
                  children: [
                    body,
                    if (_dropHover)
                      Positioned.fill(
                        child: DropOverlay(
                          message:
                              app.blocksFiles ??
                              'Drop $_fileTypes recordings to open them',
                          ok: app.blocksFiles == null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _menuItems(List<ViewerAction> actions) => [
    for (final (i, a) in actions.indexed) ...[
      if (a.divider && i > 0) const Divider(),
      MenuItemButton(
        shortcut: a.shortcut,
        onPressed: a.onPressed,
        leadingIcon: a.checked != null
            ? Icon(
                a.checked! ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
              )
            : (a.icon == null ? null : Icon(a.icon, size: 18)),
        child: Text(a.label),
      ),
    ],
  ];

  Widget _menuBar() {
    SingleActivator ctrl(LogicalKeyboardKey k) => _isApple
        ? SingleActivator(k, meta: true)
        : SingleActivator(k, control: true);
    return Row(
      children: [
        Expanded(
          child: MenuBar(
            style: const MenuStyle(
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  if (_opensFiles)
                    MenuItemButton(
                      shortcut: ctrl(LogicalKeyboardKey.keyO),
                      onPressed: _open,
                      child: const Text('Open recording…'),
                    ),
                  if (_opensFiles && supportsPaths)
                    SubmenuButton(
                      menuChildren: [
                        for (final path in prefs.recentFiles)
                          if (fileAtPath(path) != null)
                            MenuItemButton(
                              onPressed: () =>
                                  app.openFiles([fileAtPath(path)!]),
                              child: Text(path),
                            ),
                      ],
                      child: const Text('Open recent'),
                    ),
                  const Divider(),
                  MenuItemButton(
                    onPressed: () => showPreferences(context, prefs),
                    child: const Text('Preferences…'),
                  ),
                  if (!kIsWeb)
                    MenuItemButton(
                      shortcut: ctrl(LogicalKeyboardKey.keyQ),
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('Quit'),
                    ),
                ],
                child: const Text('File'),
              ),
              for (final MapEntry(key: menu, value: actions) in _actions(
                context,
              ).entries)
                SubmenuButton(
                  menuChildren: _menuItems(actions),
                  child: Text(menu),
                ),
              SubmenuButton(
                menuChildren: [
                  if (_keysOrMouse)
                    MenuItemButton(
                      onPressed: () => showHelp(context),
                      child: const Text('Keyboard and mouse'),
                    ),
                  MenuItemButton(
                    onPressed: () => showAbout(context, config),
                    child: const Text('About'),
                  ),
                ],
                child: const Text('Help'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          for (final p in app.providers) ...p.toolbarLeading(context),
          if (_opensFiles)
            OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          for (final p in app.providers) ...p.toolbar(context),
          const Spacer(),
          IconButton(
            tooltip: 'Preferences',
            onPressed: () => showPreferences(context, prefs),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final actions = [
      for (final m in _actions(context).values)
        for (final a in m)
          if (!a.wideOnly && a.onPressed != null) a,
    ];
    return AppBar(
      title: Text(config.title),
      actions: [
        if (_opensFiles)
          IconButton(
            tooltip: 'Open recording',
            onPressed: _open,
            icon: const Icon(Icons.folder_open),
          ),
        for (final p in app.providers) ...p.appBarActions(context),
        PopupMenuButton<VoidCallback>(
          onSelected: (f) => f(),
          itemBuilder: (_) => [
            for (final a in actions)
              if (a.checked != null)
                CheckedPopupMenuItem(
                  value: a.onPressed,
                  checked: a.checked!,
                  child: Text(a.narrowLabel ?? a.label),
                )
              else
                PopupMenuItem(
                  value: a.onPressed,
                  child: Text(a.narrowLabel ?? a.label),
                ),
            PopupMenuItem(
              value: () => showPreferences(context, prefs),
              child: const Text('Preferences…'),
            ),
            if (_keysOrMouse)
              PopupMenuItem(
                value: () => showHelp(context),
                child: const Text('Keyboard and mouse'),
              ),
            PopupMenuItem(
              value: () => showAbout(context, config),
              child: const Text('About'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tabsArea(bool narrow) {
    if (app.tabs.isEmpty) return _welcome();
    final tab = app.currentTab!;
    return Column(
      children: [
        _tabStrip(),
        Expanded(child: _tabView(tab, narrow)),
      ],
    );
  }

  Widget _tabStrip() {
    final theme = Theme.of(context);
    return Container(
      height: touchPlatform ? 44 : 36,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: app.tabs.length,
        itemBuilder: (context, i) {
          final t = app.tabs[i];
          final selected = i == app.current;
          return Tooltip(
            message: t.tooltip,
            waitDuration: const Duration(milliseconds: 600),
            child: GestureDetector(
              // Middle click closes the tab.
              onTertiaryTapUp: (_) => app.closeTab(i),
              child: InkWell(
                onTap: () => app.current = i,
                child: Container(
                  padding: const EdgeInsets.only(left: 12, right: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.surfaceContainerHighest
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        color: selected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.w600 : null,
                          fontSize: 13,
                        ),
                      ),
                      IconButton(
                        iconSize: touchPlatform ? 18 : 14,
                        visualDensity: touchPlatform
                            ? VisualDensity.standard
                            : VisualDensity.compact,
                        tooltip: 'Close',
                        onPressed: () => app.closeTab(i),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  PlotStyle _style(BuildContext context) => PlotStyle(
    dark: Theme.of(context).brightness == Brightness.dark,
    fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
    lineWidth: prefs.lineWidth,
    antialias: prefs.antialias,
  );

  Widget _tabView(TabEntry tab, bool narrow) {
    final c = tab.controller;
    final style = _style(context);
    final showPanel = !narrow && prefs.panelVisible;
    final plot = Column(
      children: [
        QuickBar(
          key: ObjectKey(c),
          controller: c,
          trailing: IconButton(
            tooltip: showPanel ? 'Hide controls' : 'All controls',
            onPressed: narrow ? () => _showPanelSheet(tab) : _togglePanel,
            icon: Icon(showPanel ? Icons.chevron_right : Icons.tune),
          ),
        ),
        Expanded(
          flex: 2,
          child: TabPlot(
            key: ObjectKey(c),
            controller: c,
            style: style,
            onRename: (ch) => _renameChannel(tab, ch),
          ),
        ),
        for (final b in tab.below) ...[
          _belowHeader(tab, b),
          Expanded(
            child: TabPlot(
              key: ObjectKey(b.controller),
              controller: b.controller,
              style: style,
              onRename: (ch) => _renameChannel(b, ch),
            ),
          ),
        ],
        if (!c.live) OverviewStrip(controller: c, style: style),
        if (!c.live) _scrollRow(c),
      ],
    );
    if (!showPanel) return plot;
    return Row(
      children: [
        Expanded(child: plot),
        const VerticalDivider(width: 1),
        SizedBox(width: 320, child: _panel(tab)),
      ],
    );
  }

  /// The title of tab [b] shown below [tab], with a button to remove it.
  Widget _belowHeader(TabEntry tab, TabEntry b) {
    final theme = Theme.of(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              b.title,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            tooltip: 'Show it only in its own tab',
            onPressed: () => app.showBelow(tab, [
              for (final x in tab.below)
                if (x != b) x,
            ]),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _panel(TabEntry tab) {
    final session = tab.session;
    final info = tab.group.info;
    var setup = '${config.setupName}…';
    if (session.groupable) {
      final noun = session.memberNoun;
      final indices = info.streamIndices..sort();
      setup =
          '${noun[0].toUpperCase()}${noun.substring(1)} '
          '${indices.join(', ')} · $setup';
    }
    return ControlsPanel(
      key: ObjectKey(tab.controller),
      controller: tab.controller,
      dark: Theme.of(context).brightness == Brightness.dark,
      onSourceSetup: _sourceSetup,
      sourceSetupLabel: setup,
      // Text markers need no decoding.
      onDecoderSettings: session.decodable(info)
          ? () {
              _decoderSettings(tab.controller);
              app.rememberDecoded(tab.controller);
            }
          : null,
      onSaveDefaults: () => _saveDefaults(tab),
    );
  }

  /// Make a tab's settings what new tabs of its kind start with.
  Future<void> _saveDefaults(TabEntry tab) async {
    final c = tab.controller;
    prefs.defaults = {
      ...prefs.defaults,
      c.info.kind: KindDefaults.of(c.settings, c.info.labels),
    };
    await prefs.save();
  }

  void _showPanelSheet(TabEntry tab) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: _panel(tab),
    ),
  );

  Widget _scrollRow(StreamController c) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final start = c.source.start;
        final end = c.source.end;
        final span = end - start - c.windowS;
        return Padding(
          padding: const EdgeInsets.only(left: 76, right: 8),
          child: Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: span <= 0 ? 0 : ((c.t0 - start) / span).clamp(0, 1),
                    onChanged: span <= 0
                        ? null
                        : (f) => c.scrollTo(start + f * span),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${c.t0.toStringAsFixed(1)} / ${end.toStringAsFixed(1)} s',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    final buttons = [
      if (_opensFiles)
        FilledButton.icon(
          onPressed: _open,
          icon: const Icon(Icons.folder_open),
          label: const Text('Open recording…'),
        ),
      for (final p in app.providers) ...p.welcome(context),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.show_chart,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(config.heading, style: theme.textTheme.headlineSmall),
              for (final (i, b) in buttons.indexed) ...[
                SizedBox(height: i == 0 ? 24 : 12),
                b,
              ],
              if (app.opening.isNotEmpty) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text('Opening ${app.opening.join(', ')}…'),
              ],
              if (_opensFiles) ...[
                const SizedBox(height: 24),
                Text(
                  'Or drop $_fileTypes files anywhere in this window.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar() {
    final theme = Theme.of(context);
    final progress = app.currentTab?.session.progress;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              app.status,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (progress != null) ...[
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(width: 8),
          ],
          for (final p in app.providers) ...p.status(context),
        ],
      ),
    );
  }
}

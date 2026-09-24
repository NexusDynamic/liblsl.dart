import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lsl.dart';
import 'lsl_provider.dart';
import 'package:signal_viewer/signal_viewer.dart';

/// Streams on the network, to open in tabs. Looks for streams while open.
Future<void> showLslStreams(BuildContext context, LslProvider app) async {
  app.startDiscovery();
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => _LslStreamsDialog(app),
    );
  } finally {
    app.stopDiscovery();
  }
}

IconData _icon(LslStreamDescription s) {
  if (s.format.isString) return Icons.label_outline;
  return switch (kindFromType(s.type)) {
    Kind.eeg || Kind.emg => Icons.show_chart,
    Kind.imu => Icons.threed_rotation,
    Kind.event => Icons.flag_outlined,
    Kind.other => Icons.stream,
  };
}

class _LslStreamsDialog extends StatelessWidget {
  final LslProvider app;
  const _LslStreamsDialog(this.app);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final streams = app.streams;
        final body = streams.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 12),
                    const Text('Looking for LSL streams…'),
                    const SizedBox(height: 8),
                    Text(
                      'Streams on other computers are found by multicast. '
                      'If your network blocks it, add their addresses as '
                      'known peers in LSL settings.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in streams)
                    ListTile(
                      leading: Icon(_icon(s)),
                      title: Text(s.name),
                      subtitle: Text(s.summary),
                      trailing: app.isOpen(s.key)
                          ? const Chip(label: Text('Open'))
                          : app.connecting.contains(s.key)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton.tonal(
                              onPressed: () => app.connect(s),
                              child: const Text('View'),
                            ),
                    ),
                ],
              );
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('LSL streams')),
              Text('liblsl ${lsl.version}', style: theme.textTheme.bodySmall),
            ],
          ),
          content: SizedBox(width: 560, child: body),
          actions: [
            TextButton(
              onPressed: () => showLslSettings(context, app),
              child: const Text('Settings…'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

/// Advanced LSL settings, with defaults that suit most uses.
Future<void> showLslSettings(BuildContext context, LslProvider app) =>
    showDialog<void>(context: context, builder: (_) => _LslSettingsDialog(app));

class _LslSettingsDialog extends StatefulWidget {
  final LslProvider app;
  const _LslSettingsDialog(this.app);

  @override
  State<_LslSettingsDialog> createState() => _LslSettingsDialogState();
}

class _LslSettingsDialogState extends State<_LslSettingsDialog> {
  late LslOptions _o = widget.app.app.prefs.lsl;

  /// Text fields are rebuilt with new values after "Restore defaults".
  int _generation = 0;

  void _restore() => setState(() {
    _o = const LslOptions();
    _generation++;
  });

  Future<void> _ok() async {
    final navigator = Navigator.of(context);
    final restart = _o.network != widget.app.app.prefs.lsl.network;
    await widget.app.setOptions(_o);
    if (restart) {
      widget.app.app.setStatus('LSL network settings apply after a restart');
    }
    navigator.pop();
  }

  Widget _number(
    String label,
    int value,
    String suffix,
    String help,
    ValueChanged<int> onChanged, {
    int min = 0,
    int max = 100000,
  }) => SizedBox(
    width: 200,
    child: TextFormField(
      key: ValueKey('$label$_generation'),
      initialValue: '$value',
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: help,
        helperMaxLines: 3,
        isDense: true,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (t) {
        final v = int.tryParse(t ?? '');
        return v == null || v < min || v > max ? '$min to $max' : null;
      },
      onChanged: (t) {
        final v = int.tryParse(t);
        if (v != null && v >= min && v <= max) onChanged(v);
      },
    ),
  );

  Widget _switch(
    String label,
    String help,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(help),
    value: value,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = _o.inlet, out = _o.outlet, net = _o.network;
    void inlet(LslInletOptions v) => setState(() => _o = _o.copyWith(inlet: v));
    void outlet(LslOutletOptions v) =>
        setState(() => _o = _o.copyWith(outlet: v));
    void network(LslNetworkOptions v) =>
        setState(() => _o = _o.copyWith(network: v));
    Widget heading(String s, [String? help]) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s, style: theme.textTheme.titleSmall),
          if (help != null) Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The defaults suit most uses. Larger intervals and chunks use '
          'less CPU at the cost of latency.',
          style: theme.textTheme.bodySmall,
        ),
        heading('Receiving', 'Applies to streams opened afterwards.'),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _number(
              'Collect every',
              i.pullIntervalMs,
              'ms',
              'How often new samples are picked up.',
              (v) => inlet(i.copyWith(pullIntervalMs: v)),
              min: 1,
              max: 1000,
            ),
            _number(
              'Chunk size',
              i.chunkSize,
              'samples',
              'Per network packet asked of the sender; 0 lets it decide.',
              (v) => inlet(i.copyWith(chunkSize: v)),
            ),
            _number(
              'Buffer',
              i.bufferS,
              's',
              'Kept by LSL if the app falls behind.',
              (v) => inlet(i.copyWith(bufferS: v)),
              min: 1,
              max: 3600,
            ),
          ],
        ),
        _switch(
          'Synchronize clocks',
          'Put time stamps on this computer\'s clock.',
          i.clockSync,
          (v) => inlet(i.copyWith(clockSync: v)),
        ),
        _switch(
          'Remove jitter',
          'Smooth the time stamps of regular streams.',
          i.dejitter,
          (v) => inlet(i.copyWith(dejitter: v)),
        ),
        _switch(
          'Monotonic time stamps',
          'Never let time stamps go backwards (with jitter removal).',
          i.monotonize,
          i.dejitter ? (v) => inlet(i.copyWith(monotonize: v)) : null,
        ),
        _switch(
          'Reconnect',
          'Carry on when a stream that went away comes back.',
          i.recover,
          (v) => inlet(i.copyWith(recover: v)),
        ),
        heading(
          'Publishing',
          'The device over LSL and recording replays; applies when '
              'started.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _number(
              'Push every',
              out.pushIntervalMs,
              'ms',
              'Samples are collected and sent together.',
              (v) => outlet(out.copyWith(pushIntervalMs: v)),
              min: 1,
              max: 1000,
            ),
            _number(
              'Chunk size',
              out.chunkSize,
              'samples',
              'Per network packet; 0 sends each push as it comes.',
              (v) => outlet(out.copyWith(chunkSize: v)),
            ),
            _number(
              'Buffer',
              out.bufferS,
              's',
              'Kept for a consumer that falls behind.',
              (v) => outlet(out.copyWith(bufferS: v)),
              min: 1,
              max: 3600,
            ),
          ],
        ),
        _switch(
          'Blocking zero-copy sends',
          'Less CPU for many channels, but a slow consumer holds up '
              'sending. Not used for marker streams.',
          out.syncBlocking,
          (v) => outlet(out.copyWith(syncBlocking: v)),
        ),
        _switch(
          'Loop replays',
          'Start a recording over when its replay reaches the end.',
          _o.replayLoop,
          (v) => setState(() => _o = _o.copyWith(replayLoop: v)),
        ),
        heading('Network', 'Applies after restarting hyprview.'),
        TextFormField(
          key: ValueKey('peers$_generation'),
          initialValue: net.knownPeers.join(', '),
          decoration: const InputDecoration(
            labelText: 'Known peers',
            helperText:
                'Addresses or host names to find streams on without '
                'multicast, separated by commas. Needed on every computer.',
            helperMaxLines: 2,
            isDense: true,
          ),
          onChanged: (t) => network(
            LslNetworkOptions(
              knownPeers: [
                for (final p in t.split(RegExp(r'[,\s]+')))
                  if (p.isNotEmpty) p,
              ],
              sessionId: net.sessionId,
              scope: net.scope,
              ipv6: net.ipv6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: TextFormField(
                key: ValueKey('session$_generation'),
                initialValue: net.sessionId,
                decoration: const InputDecoration(
                  labelText: 'Session id',
                  helperText: 'Only the same id sees each other.',
                  isDense: true,
                ),
                onChanged: (t) => network(
                  LslNetworkOptions(
                    knownPeers: net.knownPeers,
                    sessionId: t.trim().isEmpty ? 'default' : t.trim(),
                    scope: net.scope,
                    ipv6: net.ipv6,
                  ),
                ),
              ),
            ),
            DropdownMenu<LslScope>(
              label: const Text('Discovery reaches'),
              initialSelection: net.scope,
              key: ValueKey('scope$_generation'),
              dropdownMenuEntries: const [
                DropdownMenuEntry(
                  value: LslScope.machine,
                  label: 'This computer',
                ),
                DropdownMenuEntry(value: LslScope.link, label: 'Subnet'),
                DropdownMenuEntry(value: LslScope.site, label: 'Site'),
                DropdownMenuEntry(
                  value: LslScope.organization,
                  label: 'Organization',
                ),
                DropdownMenuEntry(value: LslScope.global, label: 'Global'),
              ],
              onSelected: (v) => network(
                LslNetworkOptions(
                  knownPeers: net.knownPeers,
                  sessionId: net.sessionId,
                  scope: v ?? net.scope,
                  ipv6: net.ipv6,
                ),
              ),
            ),
            FilterChip(
              label: const Text('IPv6'),
              selected: net.ipv6,
              onSelected: (v) => network(
                LslNetworkOptions(
                  knownPeers: net.knownPeers,
                  sessionId: net.sessionId,
                  scope: net.scope,
                  ipv6: v,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    final narrow = MediaQuery.sizeOf(context).width < narrowWidth;
    final actions = [
      TextButton(onPressed: _restore, child: const Text('Restore defaults')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _ok, child: const Text('OK')),
    ];
    if (narrow) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('LSL settings'),
            leading: const CloseButton(),
            actions: [TextButton(onPressed: _ok, child: const Text('Save'))],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: body,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('LSL settings'),
      content: SizedBox(width: 680, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}

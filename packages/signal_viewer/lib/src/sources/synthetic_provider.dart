import 'package:flutter/material.dart';

import '../ui/dialogs/synth_form.dart';
import '../viewer/source.dart';
import 'synthetic.dart';

/// Opens [SyntheticSession]s: test signals made in the app, from the Test
/// menu and the welcome screen.
class SyntheticProvider extends SourceProvider {
  /// The options last used, offered again.
  SynthOptions last = const SynthOptions();
  int _count = 0;

  /// Start a synthetic stream and open its tabs.
  void open(SynthOptions options, {String? name}) {
    last = options;
    final s = SyntheticSession(name ?? 'Synthetic ${++_count}', options);
    app.addSession(s);
    app.setStatus('Showing ${s.name}: ${options.spec}');
  }

  @override
  List<ViewerAction> actions(BuildContext context) => [
    ViewerAction(
      'Test',
      'Synthetic stream…',
      narrowLabel: 'Synthetic test stream…',
      onPressed: () => showSyntheticDialog(context, this),
    ),
  ];

  @override
  List<Widget> welcome(BuildContext context) => [
    OutlinedButton.icon(
      onPressed: () => showSyntheticDialog(context, this),
      icon: const Icon(Icons.graphic_eq),
      label: const Text('Show a synthetic signal…'),
    ),
  ];
}

/// Choose a synthetic signal and show it.
Future<void> showSyntheticDialog(
  BuildContext context,
  SyntheticProvider provider,
) => showDialog<void>(
  context: context,
  builder: (_) => _SyntheticDialog(provider),
);

class _SyntheticDialog extends StatefulWidget {
  final SyntheticProvider provider;
  const _SyntheticDialog(this.provider);

  @override
  State<_SyntheticDialog> createState() => _SyntheticDialogState();
}

class _SyntheticDialogState extends State<_SyntheticDialog> {
  late SynthOptions? _options = widget.provider.last;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Synthetic stream'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A test signal made in the app and shown as a live stream, '
              'without LSL. The same seed gives the same signal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SynthForm(
              initial: widget.provider.last,
              onChanged: (o) => setState(() => _options = o),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _options == null
            ? null
            : () {
                Navigator.pop(context);
                widget.provider.open(_options!);
              },
        child: const Text('Show'),
      ),
    ],
  );
}

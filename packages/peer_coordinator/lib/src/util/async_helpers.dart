import 'dart:async';

/// Waits for the first event on [stream] that satisfies [test].
///
/// The subscription is always cancelled — on match, timeout, stream error,
/// or the stream closing — so callers can never leak a listener, even when
/// [timeout] is null. If the stream closes before a match, this completes
/// with a [StateError]; on timeout, with a [TimeoutException].
Future<T> waitForEvent<T>(
  Stream<T> stream,
  bool Function(T event) test, {
  Duration? timeout,
  String? description,
}) {
  final completer = Completer<T>();
  late final StreamSubscription<T> subscription;
  Timer? timer;

  void finish(void Function() complete) {
    timer?.cancel();
    subscription.cancel();
    if (!completer.isCompleted) complete();
  }

  subscription = stream.listen(
    (event) {
      if (test(event)) {
        finish(() => completer.complete(event));
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      finish(() => completer.completeError(error, stackTrace));
    },
    onDone: () {
      finish(
        () => completer.completeError(
          StateError(
            'Stream closed while waiting for ${description ?? 'event'}',
          ),
        ),
      );
    },
  );

  if (timeout != null) {
    timer = Timer(timeout, () {
      finish(
        () => completer.completeError(
          TimeoutException(
            'Timeout waiting for ${description ?? 'event'}',
            timeout,
          ),
        ),
      );
    });
  }

  return completer.future;
}

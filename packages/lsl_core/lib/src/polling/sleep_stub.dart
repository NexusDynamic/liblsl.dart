/// Busy-waits for [d]: a browser cannot block.
void sleep(Duration d) {
  final sw = Stopwatch()..start();
  while (sw.elapsed < d) {}
}

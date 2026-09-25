/// Unit tests for the transport-neutral parts of the stream layer.
///
/// [DataStreamConfig.validateSample] used to live as a private method on the
/// LSL data stream, so every new transport would have had to reinvent it (or
/// silently skip validation). It is pure and shared now, which means every
/// backend rejects the same inputs with the same message.
library;

import 'package:peer_coordinator/framework.dart';
import 'package:test/test.dart';

DataStreamConfig config({
  int channels = 3,
  StreamDataType dataType = StreamDataType.double64,
}) => DataStreamConfig(
  name: 'TestData',
  channels: channels,
  sampleRate: 10.0,
  dataType: dataType,
);

void main() {
  group('DataStreamConfig.validateSample', () {
    test('accepts a correctly shaped and typed sample', () {
      expect(() => config().validateSample([1.0, 2.0, 3.0]), returnsNormally);
    });

    test('rejects the wrong channel count, naming the stream', () {
      expect(
        () => config().validateSample([1.0, 2.0]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('does not match channels 3'), contains('TestData')),
          ),
        ),
      );
      expect(
        () => config().validateSample([1.0, 2.0, 3.0, 4.0]),
        throwsArgumentError,
      );
    });

    test('float and double accept any num, including ints', () {
      // int is a num, and LSL widens it on the way out, so rejecting it would
      // break callers that pass whole numbers.
      for (final type in [StreamDataType.float32, StreamDataType.double64]) {
        expect(
          () => config(dataType: type).validateSample([1, 2.5, 3]),
          returnsNormally,
          reason: '$type should accept mixed num',
        );
        expect(
          () => config(dataType: type).validateSample([1.0, 'x', 3.0]),
          throwsArgumentError,
          reason: '$type should reject a String',
        );
      }
    });

    test('integer types reject doubles', () {
      // Not merely pedantic: the value is handed to a typed native buffer, so
      // a double here is a truncation the caller never asked for.
      for (final type in [
        StreamDataType.int8,
        StreamDataType.int16,
        StreamDataType.int32,
        StreamDataType.int64,
      ]) {
        expect(
          () => config(dataType: type).validateSample([1, 2, 3]),
          returnsNormally,
        );
        expect(
          () => config(dataType: type).validateSample([1, 2.5, 3]),
          throwsArgumentError,
          reason: '$type should reject a double',
        );
      }
    });

    test('string type rejects anything that is not a String', () {
      final stringConfig = config(dataType: StreamDataType.string);
      expect(
        () => stringConfig.validateSample(['a', 'b', 'c']),
        returnsNormally,
      );
      expect(
        () => stringConfig.validateSample(['a', 1, 'c']),
        throwsArgumentError,
      );
    });

    test('an empty sample is rejected unless the stream has no channels', () {
      expect(() => config().validateSample([]), throwsArgumentError);
    });
  });

  group('NetworkStreamConfig validation', () {
    test('rejects a non-positive channel count', () {
      expect(
        () => DataStreamConfig(
          name: 'x',
          channels: 0,
          sampleRate: 10.0,
          dataType: StreamDataType.double64,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive sample rate', () {
      // Worth pinning: it means a stream that is purely event-driven still has
      // to declare a nominal rate. CoordinationStreamConfig defaults to 50.
      expect(
        () => DataStreamConfig(
          name: 'x',
          channels: 1,
          sampleRate: 0,
          dataType: StreamDataType.double64,
        ),
        throwsArgumentError,
      );
    });

    test('a coordination stream is always one string channel', () {
      final coordination = CoordinationStreamConfig(name: 'coordination');
      expect(coordination.channels, 1);
      expect(coordination.dataType, StreamDataType.string);
      expect(coordination.sampleRate, 50.0);
    });
  });
}

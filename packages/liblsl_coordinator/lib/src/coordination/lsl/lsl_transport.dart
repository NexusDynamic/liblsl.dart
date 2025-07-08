import 'dart:async';
import 'dart:convert';
import 'package:liblsl/lsl.dart';
import '../core/network_transport.dart';
import '../core/coordination_message.dart';

/// Exception thrown by LSL transport operations
class LSLTransportException implements Exception {
  final String message;
  final dynamic cause;

  const LSLTransportException(this.message, [this.cause]);

  @override
  String toString() =>
      'LSLTransportException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

/// LSL-based transport implementation
class LSLNetworkTransport implements NetworkTransport {
  final String streamName;
  final String nodeId;
  final LSLChannelFormat channelFormat;
  final double sampleRate;
  final LSLApiConfig lslApiConfig;

  LSLOutlet? _outlet;
  final List<LSLInlet> _inlets = [];
  final StreamController<CoordinationMessage> _messageController =
      StreamController<CoordinationMessage>.broadcast();

  Timer? _pollTimer;
  bool _isInitialized = false;

  LSLNetworkTransport({
    required this.streamName,
    required this.nodeId,
    this.channelFormat = LSLChannelFormat.string,
    this.sampleRate = LSL_IRREGULAR_RATE,
    LSLApiConfig? lslApiConfig,
  }) : lslApiConfig = lslApiConfig ?? LSLApiConfig() {
    // Set LSL configuration if needed
    LSL.setConfigContent(this.lslApiConfig);
  }

  @override
  Stream<CoordinationMessage> get messageStream => _messageController.stream;

  @override
  bool get isConnected => _isInitialized && _outlet != null;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create outlet for sending messages
      final streamInfo = await LSL.createStreamInfo(
        streamName: streamName,
        streamType: LSLContentType.markers,
        channelCount: 1,
        sampleRate: sampleRate,
        channelFormat: channelFormat,
        sourceId: 'coord_$nodeId',
      );

      _outlet = await LSL.createOutlet(
        streamInfo: streamInfo,
        chunkSize: 1,
        maxBuffer: 10,
      );

      // Start polling for incoming messages
      _startMessagePolling();

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      _outlet = null;
      throw LSLTransportException('Failed to initialize LSL transport: $e');
    }
  }

  @override
  Future<void> sendMessage(CoordinationMessage message) async {
    if (_outlet == null) {
      throw LSLTransportException('Transport not initialized');
    }

    try {
      final serialized = jsonEncode(message.toMap());
      await _outlet!.pushSample([serialized]);
    } catch (e) {
      throw LSLTransportException(
        'Failed to send message: ${message.messageType}',
        e,
      );
    }
  }

  @override
  Future<void> subscribeToSource(String sourceId) async {
    try {
      // Find streams from this source
      final streams = await LSL.resolveStreams(waitTime: 2.0, maxStreams: 50);

      final matchingStreams = streams.where(
        (s) =>
            s.streamName == streamName &&
            s.sourceId == 'coord_$sourceId' &&
            s.sourceId != 'coord_$nodeId', // Don't subscribe to self
      );

      for (final stream in matchingStreams) {
        // Check if we already have an inlet for this stream
        if (_inlets.any(
          (inlet) => inlet.streamInfo.sourceId == stream.sourceId,
        )) {
          continue;
        }

        try {
          final inlet = await LSL.createInlet<String>(
            streamInfo: stream,
            maxBuffer: 10,
            chunkSize: 1,
            recover: true,
          );

          _inlets.add(inlet);
        } catch (e) {
          // Log error but continue with other streams
          print('Failed to create inlet for ${stream.sourceId}: $e');
        }
      }
    } catch (e) {
      throw LSLTransportException(
        'Failed to subscribe to source: $sourceId',
        e,
      );
    }
  }

  @override
  Future<void> unsubscribeFromSource(String sourceId) async {
    try {
      _inlets.removeWhere((inlet) {
        if (inlet.streamInfo.sourceId == 'coord_$sourceId') {
          try {
            inlet.destroy();
          } catch (e) {
            print(
              'Error destroying inlet for ${inlet.streamInfo.sourceId}: $e',
            );
          }
          return true;
        }
        return false;
      });
    } catch (e) {
      throw LSLTransportException(
        'Failed to unsubscribe from source: $sourceId',
        e,
      );
    }
  }

  void _startMessagePolling() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      await _pollMessages();
    });
  }

  Future<void> _pollMessages() async {
    for (final inlet in List.from(_inlets)) {
      try {
        final sample = await inlet.pullSample(timeout: 0.0);
        if (sample.isNotEmpty) {
          final messageData = sample[0] as String;
          try {
            final messageMap = jsonDecode(messageData) as Map<String, dynamic>;
            final message = CoordinationMessage.fromMap(messageMap);
            _messageController.add(message);
          } catch (e) {
            // Ignore malformed messages
            print('Failed to parse message: $e');
          }
        }
      } catch (e) {
        // Handle inlet errors
        print('Error reading from inlet ${inlet.streamInfo.sourceId}: $e');
      }
    }

    // Periodically discover new streams
    if (DateTime.now().second % 5 == 0) {
      await _discoverNewStreams();
    }
  }

  Future<void> _discoverNewStreams() async {
    try {
      final streams = await LSL.resolveStreams(waitTime: 1.0, maxStreams: 50);

      final coordinationStreams = streams.where(
        (s) =>
            s.streamName == streamName &&
            s.sourceId.startsWith('coord_') &&
            s.sourceId != 'coord_$nodeId',
      );

      for (final stream in coordinationStreams) {
        // Check if we already have an inlet for this stream
        if (_inlets.any(
          (inlet) => inlet.streamInfo.sourceId == stream.sourceId,
        )) {
          continue;
        }

        try {
          final inlet = await LSL.createInlet<String>(
            streamInfo: stream,
            maxBuffer: 10,
            chunkSize: 1,
            recover: true,
          );

          _inlets.add(inlet);
        } catch (e) {
          // Log error but continue
          print('Failed to create inlet for new stream ${stream.sourceId}: $e');
        }
      }
    } catch (e) {
      // Discovery errors are non-fatal
      print('Error during stream discovery: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _pollTimer?.cancel();
      _pollTimer = null;

      // Clean up inlets
      for (final inlet in _inlets) {
        try {
          await inlet.destroy();
        } catch (e) {
          print('Error destroying inlet ${inlet.streamInfo.sourceId}: $e');
        }
      }
      _inlets.clear();

      // Clean up outlet
      if (_outlet != null) {
        try {
          await _outlet!.destroy();
        } catch (e) {
          print('Error destroying outlet: $e');
        }
        _outlet = null;
      }

      // Close message controller
      try {
        await _messageController.close();
      } catch (e) {
        print('Error closing message controller: $e');
      }

      _isInitialized = false;
    } catch (e) {
      throw LSLTransportException('Failed to dispose transport', e);
    }
  }
}

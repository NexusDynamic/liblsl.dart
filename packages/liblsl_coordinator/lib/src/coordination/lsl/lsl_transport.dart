import 'dart:async';
import 'dart:convert';
import 'package:liblsl/lsl.dart';
import 'package:meta/meta.dart';
import '../core/network_transport.dart';
import '../core/coordination_message.dart';
import '../utils/logging.dart';

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
  final bool receivesOwnMessages;

  LSLStreamResolverContinuous? _continuousResolver;
  LSLStreamResolverContinuous? get continuousResolver => _continuousResolver;

  @protected
  set continuousResolver(LSLStreamResolverContinuous? value) {
    _continuousResolver = value;
  }

  LSLOutlet? _outlet;
  final List<LSLInlet> _inlets = [];
  final StreamController<CoordinationMessage> _messageController =
      StreamController<CoordinationMessage>.broadcast();

  Timer? _pollTimer;
  Timer? _discoveryTimer;
  bool _isInitialized = false;

  bool get initialized => _isInitialized;

  @protected
  set initialized(bool value) {
    _isInitialized = value;
  }

  LSLNetworkTransport({
    required this.streamName,
    required this.nodeId,
    this.channelFormat = LSLChannelFormat.string,
    this.sampleRate = LSL_IRREGULAR_RATE,
    LSLApiConfig? lslApiConfig,
    this.receivesOwnMessages = true,
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
    logger.finest(
      'Initializing LSL transport for node $nodeId, stream $streamName',
    );
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
        useIsolates: true,
      );

      logger.finest(
        'Preparing continuous resolver for node $nodeId, stream $streamName',
      );
      _continuousResolver = LSLStreamResolverContinuousByPredicate(
        predicate: "name='$streamName' and starts-with(source_id, 'coord_')",
        maxStreams: 50,
        forgetAfter: 5.0,
      );

      _continuousResolver!.create();

      // Add a brief delay to ensure outlet is fully initialized
      await Future.delayed(Duration(milliseconds: 100));

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
    if (!receivesOwnMessages && sourceId == nodeId) {
      return; // Don't subscribe to self
    }
    try {
      logger.finest(
        'Subscribing to source $sourceId for node $nodeId, stream $streamName',
      );
      //@TODO: replace with continuous resolver
      // Find streams from this source
      final streams = await LSL.resolveStreamsByPredicate(
        predicate: "name='$streamName' and source_id='coord_$sourceId'",
        waitTime: 2.0,
        maxStreams: 50,
      );

      for (final stream in streams) {
        // Check if we already have an inlet for this stream
        if (_inlets.any(
          (inlet) => inlet.streamInfo.sourceId == stream.sourceId,
        )) {
          stream.destroy();
          continue;
        }

        try {
          final inlet = await LSL.createInlet<String>(
            streamInfo: stream,
            maxBuffer: 10,
            chunkSize: 1,
            recover: true,
            useIsolates: false,
          );

          // Add brief delay to ensure inlet is ready, following your pattern
          await Future.delayed(Duration(milliseconds: 10));

          _inlets.add(inlet);
        } catch (e) {
          // Log error but continue with other streams
          logger.severe('Failed to create inlet for ${stream.sourceId}: $e');
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
      // Remove inlets for this source
      for (final inlet in _inlets) {
        if (inlet.streamInfo.sourceId == 'coord_$sourceId') {
          try {
            await inlet.destroy();
            //inlet.streamInfo.destroy();
          } catch (e) {
            logger.warning(
              'Error destroying inlet for ${inlet.streamInfo.sourceId}: $e',
            );
          }
        }
      }
      // cleanup list of inlets
      _inlets.removeWhere((inlet) {
        return inlet.destroyed;
      });
    } catch (e) {
      throw LSLTransportException(
        'Failed to unsubscribe from source: $sourceId',
        e,
      );
    }
  }

  void _startMessagePolling() {
    logger.finest(
      'Starting message polling for node $nodeId, stream $streamName',
    );
    if (_pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
    if (_discoveryTimer != null) {
      _discoveryTimer!.cancel();
      _discoveryTimer = null;
    }

    logger.finest(
      'Starting polling timer (100ms interval) for node $nodeId, stream $streamName',
    );
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      await _pollMessages();
    });
    logger.finest(
      'Starting discovery timer (5s interval) for node $nodeId, stream $streamName',
    );
    _discoveryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _discoverNewStreams();
    });
  }

  Future<void> _pollMessages() async {
    for (final LSLInlet<dynamic> inlet in List.from(_inlets)) {
      try {
        final sample = await inlet.pullSample(timeout: 0.0);
        if (sample.isNotEmpty) {
          logger.finest(
            'Received message from inlet ${inlet.streamInfo.sourceId}: $sample',
          );
          final messageData = sample[0] as String;
          try {
            final messageMap = jsonDecode(messageData) as Map<String, dynamic>;
            final message = CoordinationMessage.fromMap(messageMap);
            _messageController.add(message);
          } catch (e) {
            // Ignore malformed messages
            logger.severe('Failed to parse message: $e');
          }
        }
      } catch (e) {
        // Handle inlet errors
        logger.warning(
          'Error reading from inlet ${inlet.streamInfo.sourceId}: $e',
        );
      }
    }
  }

  Future<void> _discoverNewStreams() async {
    try {
      logger.finest(
        "Stream discovery started for node $nodeId, stream $streamName",
      );
      final streams = await _continuousResolver!.resolve();

      for (final stream in streams) {
        // Check if we already have an inlet for this stream
        if (_inlets.any(
          (inlet) => inlet.streamInfo.sourceId == stream.sourceId,
        )) {
          stream.destroy();
          continue;
        }

        try {
          logger.finest('Creating inlet for new stream ${stream.sourceId}');
          final inlet = await LSL.createInlet<String>(
            streamInfo: stream,
            maxBuffer: 10,
            chunkSize: 1,
            recover: true,
            useIsolates: true,
          );

          // Add brief delay to ensure inlet is ready
          await Future.delayed(Duration(milliseconds: 10));

          _inlets.add(inlet);
          logger.finest('Inlet created for new stream ${stream.sourceId}');
        } catch (e) {
          // Log error but continue
          logger.severe(
            'Failed to create inlet for new stream ${stream.sourceId}: $e',
          );
        }
      }
    } catch (e) {
      // Discovery errors are non-fatal
      logger.warning('Error during stream discovery: $e');
    }
  }

  @override
  Future<void> dispose() async {
    logger.finest(
      'Disposing LSL transport for node $nodeId, stream $streamName',
    );
    try {
      _pollTimer?.cancel();
      _pollTimer = null;

      _discoveryTimer?.cancel();
      _discoveryTimer = null;

      _continuousResolver?.destroy();
      _continuousResolver = null;

      // Clean up inlets
      for (final inlet in _inlets) {
        try {
          await inlet.destroy();
          // inlet.streamInfo.destroy();
        } catch (e) {
          logger.warning(
            'Error destroying inlet ${inlet.streamInfo.sourceId}: $e',
          );
        }
      }
      _inlets.clear();

      // Clean up outlet
      if (_outlet != null) {
        try {
          await _outlet!.destroy();
          // _outlet!.streamInfo.destroy();
        } catch (e) {
          logger.warning('Error destroying outlet: $e');
        }
        _outlet = null;
      }

      // Close message controller
      try {
        await _messageController.close();
      } catch (e) {
        logger.warning('Error closing message controller: $e');
      }

      _isInitialized = false;
    } catch (e) {
      throw LSLTransportException('Failed to dispose transport', e);
    }
  }
}

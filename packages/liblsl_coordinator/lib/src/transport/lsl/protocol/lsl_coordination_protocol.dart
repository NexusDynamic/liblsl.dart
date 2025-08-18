import 'dart:async';
import 'dart:convert';
import 'package:liblsl/lsl.dart';
import '../../../protocol/coordination_protocol.dart';
import '../../../utils/logging.dart';
import '../core/lsl_api_manager.dart';
import '../config/lsl_stream_config.dart';
import '../isolate/lsl_isolate_controller.dart';
import '../isolate/lsl_polling_isolates.dart';

/// LSL-based implementation of CoordinationProtocol
///
/// Uses LSL streams for sending and receiving coordination messages between nodes
class LSLCoordinationProtocol extends CoordinationProtocol {
  final String nodeId;
  final String sessionId;
  final String coordinationPrefix;

  final StreamController<IncomingCoordinationMessage> _messageController =
      StreamController<IncomingCoordinationMessage>.broadcast();

  bool _isInitialized = false;
  late final ConfiguredLSL _lsl;

  // LSL streams for coordination
  LSLOutlet? _messageOutlet;
  LSLStreamResolverContinuous? _messageResolver;
  Timer? _heartbeatTimer;
  Timer? _discoveryTimer;

  // Isolate-based coordination message handling
  LSLIsolateController? _coordinationInletController;
  StreamSubscription<IsolateMessage>? _coordinationMessageSubscription;

  LSLCoordinationProtocol({
    required this.nodeId,
    required this.sessionId,
    required this.coordinationPrefix,
  });

  @override
  String get name => 'LSLCoordinationProtocol';

  @override
  String get version => '1.0.0';

  @override
  Stream<IncomingCoordinationMessage> get messages => _messageController.stream;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    logger.info('Initializing LSL coordination protocol for node $nodeId');

    try {
      _lsl = LSLApiManager.lsl;

      // Create outlet for sending coordination messages
      await _createMessageOutlet();

      // Start discovering and listening to coordination messages from other nodes
      await _startMessageDiscovery();

      _isInitialized = true;
      logger.info('LSL coordination protocol initialized successfully');
    } catch (e) {
      logger.severe('Failed to initialize LSL coordination protocol: $e');
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (!_isInitialized) return;

    logger.info('Disposing LSL coordination protocol');

    // Stop timers
    _heartbeatTimer?.cancel();
    _discoveryTimer?.cancel();

    // Cancel stream subscription
    await _coordinationMessageSubscription?.cancel();

    // Stop isolate controller
    await _coordinationInletController?.stop();

    // Cleanup LSL resources
    try {
      await _messageOutlet?.destroy();
      _messageResolver?.destroy();
    } catch (e) {
      logger.warning(
        'Error cleaning up LSL coordination protocol resources: $e',
      );
    }

    await _messageController.close();
    _isInitialized = false;
    logger.info('LSL coordination protocol disposed');
  }

  @override
  Future<void> sendMessage(
    CoordinationMessage message, {
    List<String>? targetNodes,
  }) async {
    if (!_isInitialized || _messageOutlet == null) {
      throw StateError('Coordination protocol not initialized');
    }

    try {
      // Encode message as JSON string
      final messageData = {
        'messageId': message.messageId,
        'type': message.type.toString().split('.').last,
        'payload': message.payload,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'sessionId': sessionId,
        'targetNodes': targetNodes,
        'replyToMessageId': message.replyToMessageId,
      };

      final messageJson = jsonEncode(messageData);

      // Send via LSL outlet
      await _messageOutlet!.pushSample([messageJson]);

      logger.fine(
        'Sent coordination message: ${message.type} (${message.messageId})',
      );
    } catch (e) {
      logger.severe('Failed to send coordination message: $e');
      rethrow;
    }
  }

  @override
  Future<void> handleMessage(
    CoordinationMessage message,
    String fromNodeId,
  ) async {
    // Handle incoming message - could process different message types
    logger.fine(
      'Handling coordination message ${message.type} from $fromNodeId',
    );

    // In a more complex implementation, this would route messages based on type
    // For now, just log that we're handling it
  }

  @override
  Future<void> sendHeartbeat() async {
    if (!_isInitialized) {
      throw StateError('Coordination protocol not initialized');
    }

    final heartbeatMessage = CoordinationMessage.heartbeat(nodeId);

    await sendMessage(heartbeatMessage);
    logger.finest('Sent heartbeat from $nodeId');
  }

  /// Create LSL outlet for sending coordination messages
  Future<void> _createMessageOutlet() async {
    try {
      // Create stream info for coordination messages
      final streamInfo = await _lsl.createStreamInfo(
        streamName: '${sessionId}_coordination',
        streamType: LSLContentType.eeg, // Use existing content type
        channelCount: 1,
        sampleRate: 10.0, // Low frequency for coordination messages
        channelFormat: LSLChannelFormat.string,
        sourceId: '${coordinationPrefix}_${nodeId}_messages',
      );

      // Add metadata for discovery
      final description = streamInfo.description;
      final descElement = description.value;

      descElement.addChildValue('session_id', sessionId);
      descElement.addChildValue('node_id', nodeId);
      descElement.addChildValue('stream_purpose', 'coordination_messages');
      descElement.addChildValue('protocol_version', version);
      descElement.addChildValue('coordination_prefix', coordinationPrefix);

      // Create outlet
      _messageOutlet = await _lsl.createOutlet(
        streamInfo: streamInfo,
        chunkSize: 1,
        maxBuffer: 100, // Buffer for coordination messages
        useIsolates: false,
      );

      logger.fine(
        'Created coordination message outlet: ${streamInfo.sourceId}',
      );
    } catch (e) {
      logger.severe('Failed to create coordination message outlet: $e');
      rethrow;
    }
  }

  /// Start discovering and listening to coordination messages from other nodes
  /// Uses efficient isolate-based polling instead of blocking main thread
  Future<void> _startMessageDiscovery() async {
    try {
      // Build predicate for coordination message streams in our session
      final predicate =
          "name='${sessionId}_coordination' and starts-with(source_id, '$coordinationPrefix')";
      // Create resolver for coordination message streams
      _messageResolver = LSLStreamResolverContinuousByPredicate(
        predicate: predicate,
        forgetAfter: 10.0,
        maxStreams: 50,
      );
      _messageResolver!.create();

      // Create isolate controller for coordination message polling
      _coordinationInletController = LSLIsolateController(
        controllerId: 'coordination_$nodeId',
        pollingConfig: LSLPollingConfig.standard(), // 100Hz, non-blocking
      );

      // Listen for coordination messages from isolate
      _coordinationMessageSubscription = _coordinationInletController!.messages
          .listen(_handleCoordinationIsolateMessage);

      // Start inlet isolate
      final params = LSLInletIsolateParams(
        nodeId: nodeId,
        config: LSLPollingConfig.standard(),
        sendPort: null, // Will be set by controller
        receiveOwnMessages:
            false, // Don't receive our own coordination messages
      );

      await _coordinationInletController!.start(
        lslInletConsumerIsolate,
        params,
      );
      await _coordinationInletController!.ready;

      // Start periodic discovery to find new coordination streams
      _discoveryTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _discoverCoordinationStreams();
      });

      logger.fine('Started isolate-based coordination message discovery');
    } catch (e) {
      logger.severe('Failed to start coordination message discovery: $e');
      rethrow;
    }
  }

  /// Discover coordination streams and add them to isolate for efficient polling
  Future<void> _discoverCoordinationStreams() async {
    try {
      final streams = await _messageResolver!.resolve();
      final coordinationStreams = <int>[];

      // Filter for coordination streams from other nodes
      for (final streamInfo in streams) {
        try {
          // Skip our own stream
          if (streamInfo.sourceId.contains('_${nodeId}_')) {
            continue;
          }

          // Check if it matches our coordination predicate
          if (streamInfo.streamName == '${sessionId}_coordination' &&
              streamInfo.sourceId.startsWith(coordinationPrefix)) {
            coordinationStreams.add(streamInfo.streamInfo.address);
            logger.finest(
              'Found coordination stream from ${streamInfo.sourceId}',
            );
          }
        } catch (e) {
          logger.fine('Error processing stream info: $e');
        }
      }

      // Add discovered streams to the isolate for efficient polling
      if (coordinationStreams.isNotEmpty &&
          _coordinationInletController != null) {
        await _coordinationInletController!.sendCommand(
          IsolateCommand.addInlets,
          {'streamAddresses': coordinationStreams},
        );
        logger.finest(
          'Added ${coordinationStreams.length} coordination streams to isolate',
        );
      }
    } catch (e) {
      logger.fine('Coordination stream discovery error: $e');
    }
  }

  /// Handle messages from the coordination isolate
  void _handleCoordinationIsolateMessage(IsolateMessage message) {
    switch (message.type) {
      case IsolateMessageType.data:
        // Received coordination message from another node
        final sample = message.data['sample'] as LSLSample;
        final sourceId = message.data['sourceId'] as String;

        if (sample.data.isNotEmpty && sample.data.first is String) {
          _processIncomingMessage(sample.data.first as String, sourceId);
        }
        break;

      case IsolateMessageType.error:
        logger.warning('Coordination isolate error: ${message.data['error']}');
        break;

      default:
        // Ignore other message types
        break;
    }
  }

  /// Process incoming coordination message
  Future<void> _processIncomingMessage(
    String messageJson,
    String sourceId,
  ) async {
    try {
      final messageData = jsonDecode(messageJson) as Map<String, dynamic>;

      // Verify it's for our session
      if (messageData['sessionId'] != sessionId) {
        return;
      }

      // Parse message components
      final messageId = messageData['messageId'] as String;
      final typeString = messageData['type'] as String;
      final payload = messageData['payload'] as Map<String, dynamic>? ?? {};
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        messageData['timestamp'] as int,
      );
      final replyToMessageId = messageData['replyToMessageId'] as String?;

      // Skip our own messages by checking if nodeId is in the payload
      if (payload['nodeId'] == nodeId) {
        return;
      }

      // Parse message type
      CoordinationMessageType messageType;
      try {
        messageType = CoordinationMessageType.values.firstWhere(
          (t) => t.toString().split('.').last == typeString,
        );
      } catch (e) {
        logger.warning('Unknown coordination message type: $typeString');
        return;
      }

      // Create coordination message
      final coordinationMessage = CoordinationMessage(
        messageId: messageId,
        type: messageType,
        payload: payload,
        timestamp: timestamp,
        replyToMessageId: replyToMessageId,
      );

      // Extract sender from payload
      final fromNodeId = payload['nodeId'] as String? ?? 'unknown';

      // Create incoming message wrapper
      final incomingMessage = IncomingCoordinationMessage(
        message: coordinationMessage,
        fromNodeId: fromNodeId,
        receivedAt: DateTime.now(),
      );

      // Emit to listeners
      _messageController.add(incomingMessage);

      logger.fine(
        'Received coordination message: $messageType from $fromNodeId',
      );
    } catch (e) {
      logger.warning('Failed to process incoming coordination message: $e');
    }
  }
}

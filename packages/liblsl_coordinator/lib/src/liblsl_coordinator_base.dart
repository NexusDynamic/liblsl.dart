// lib/coordination/core/coordination_node.dart

// lib/coordination/core/coordination_message.dart

// lib/coordination/core/network_transport.dart

// lib/coordination/core/leader_election.dart

// lib/coordination/lsl/lsl_transport.dart

// lib/coordination/lsl/lsl_coordination_node.dart

// lib/coordination/utils/coordination_extensions.dart

// lib/coordination/examples/simple_usage.dart

/*

*/

// lib/coordination/examples/test_coordination.dart

/*
/// Example showing how to coordinate timing tests
class TestCoordinator {
  final LSLCoordinationNode _node;
  final List<String> _readyNodes = [];
  
  TestCoordinator(this._node) {
    _node.eventStream.listen(_handleEvent);
  }
  
  void _handleEvent(CoordinationEvent event) {
    switch (event) {
      case ApplicationEvent():
        _handleApplicationEvent(event);
        break;
      default:
        break;
    }
  }
  
  void _handleApplicationEvent(ApplicationEvent event) {
    switch (event.type) {
      case 'node_ready':
        final nodeId = event.data['nodeId'] as String;
        if (!_readyNodes.contains(nodeId)) {
          _readyNodes.add(nodeId);
          print('Node ready: $nodeId (${_readyNodes.length} total)');
        }
        break;
        
      case 'test_start':
        _handleTestStart(event.data);
        break;
        
      case 'test_stop':
        _handleTestStop(event.data);
        break;
    }
  }
  
  Future<void> signalReady() async {
    await _node.sendApplicationMessage('node_ready', {
      'nodeId': _node.nodeId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  Future<void> startTest(String testType) async {
    if (_node.role != NodeRole.coordinator) {
      throw StateError('Only coordinator can start tests');
    }
    
    final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now().millisecondsSinceEpoch + 3000; // 3 second delay
    
    await _node.sendApplicationMessage('test_start', {
      'test_id': testId,
      'test_type': testType,
      'start_time': startTime,
      'participants': _readyNodes,
    });
  }
  
  void _handleTestStart(Map<String, dynamic> data) {
    final testId = data['test_id'] as String;
    final testType = data['test_type'] as String;
    final startTime = data['start_time'] as int;
    
    final delay = startTime - DateTime.now().millisecondsSinceEpoch;
    
    print('Test starting in ${delay}ms: $testType (ID: $testId)');
    
    if (delay > 0) {
      Timer(Duration(milliseconds: delay), () {
        _startActualTest(testType, testId);
      });
    } else {
      _startActualTest(testType, testId);
    }
  }
  
  void _startActualTest(String testType, String testId) {
    print('Starting test: $testType');
    // Start your actual test here
  }
  
  void _handleTestStop(Map<String, dynamic> data) {
    final testId = data['test_id'] as String;
    print('Stopping test: $testId');
    // Stop your test here
  }
}
*/

// lib/coordination/examples/integration_example.dart

/*
/// Example showing integration with existing timing test app
class FlutterCoordinationAdapter {
  final LSLCoordinationNode _node;
  final StreamController<String> _messageController = StreamController.broadcast();
  
  // Flutter-compatible streams
  Stream<String> get messageStream => _messageController.stream;
  
  bool get isCoordinator => _node.role == NodeRole.coordinator;
  String? get coordinatorId => _node is LSLCoordinationNode ? (_node as LSLCoordinationNode).coordinatorId : null;
  List<String> get connectedDevices => _node is LSLCoordinationNode 
      ? (_node as LSLCoordinationNode).knownNodes.map((n) => n.nodeId).toList() 
      : [];
  
  FlutterCoordinationAdapter(this._node) {
    _node.eventStream.listen(_handleEvent);
  }
  
  void _handleEvent(CoordinationEvent event) {
    switch (event) {
      case RoleChangedEvent():
        if (event.newRole == NodeRole.coordinator) {
          _messageController.add('You are the test coordinator');
        } else if (event.newRole == NodeRole.participant) {
          _messageController.add('Joined test coordination network');
        }
        break;
        
      case NodeJoinedEvent():
        _messageController.add('Device ${event.nodeName} (${event.nodeId}) joined');
        break;
        
      case NodeLeftEvent():
        _messageController.add('Device ${event.nodeId} left');
        break;
        
      case ApplicationEvent():
        _handleApplicationMessage(event);
        break;
        
      default:
        break;
    }
  }
  
  void _handleApplicationMessage(ApplicationEvent event) {
    switch (event.type) {
      case 'test_start':
        final testType = event.data['test_type'] as String;
        _messageController.add('Starting $testType test');
        break;
        
      case 'node_ready':
        final nodeId = event.data['nodeId'] as String;
        _messageController.add('Device $nodeId is ready');
        break;
    }
  }
  
  Future<void> initialize() async {
    await _node.initialize();
    await _node.join();
  }
  
  Future<void> signalReady() async {
    await _node.sendApplicationMessage('node_ready', {
      'nodeId': _node.nodeId,
      'nodeName': _node.nodeName,
    });
  }
  
  Future<void> startTest(String testType) async {
    await _node.sendApplicationMessage('test_start', {
      'test_type': testType,
      'start_time': DateTime.now().millisecondsSinceEpoch + 3000,
    });
  }
  
  void dispose() {
    _messageController.close();
    _node.dispose();
  }
}
*/

// USAGE SUMMARY AND BENEFITS:

/*


```dart
// Old way
final coordinator = DeviceCoordinator(config, timingManager);
await coordinator.initialize();

// New way  
final node = LSLCoordinationNode(
  nodeId: config.deviceId,
  nodeName: config.deviceName,
  streamName: 'coordination_test',
);

final adapter = FlutterCoordinationAdapter(node);
await adapter.initialize();

// Use adapter.messageStream instead of coordinator.messageStream
// Use adapter.isCoordinator instead of coordinator.isCoordinator
// etc.
```

EXTENSIBILITY EXAMPLES:

1. Add custom message types by extending CoordinationMessage
2. Implement different transports (UDP, WebSocket) by implementing NetworkTransport
3. Use different leader election strategies for specific use cases
4. Add custom event types by extending CoordinationEvent
5. Create specialized nodes for different device types

The architecture provides a solid foundation that can grow with your needs
while maintaining clean separation of concerns and platform independence.
*/

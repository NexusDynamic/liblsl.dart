import 'dart:async';
import 'package:liblsl_coordinator/src/management/network_event_bus.dart';

import 'protocol.dart';
import '../session/coordination_session.dart';

/// Protocol for network-level operations (discovery, joining, leaving)
abstract class NetworkProtocol extends Protocol {
  /// Discover available networks
  Future<List<NetworkInfo>> discoverNetworks();

  /// Join a specific network
  Future<void> joinNetwork(NetworkInfo networkInfo);

  /// Create a new network
  Future<NetworkInfo> createNetwork(
    String networkName,
    Map<String, dynamic> metadata,
  );

  /// Leave the current network
  Future<void> leaveNetwork();

  /// Announce this node's presence to the network
  Future<void> announcePresence(NetworkNode nodeInfo);

  /// Stream of network discovery events
  Stream<NetworkDiscoveryEvent> get discoveryEvents;
}

/// Information about an available network
class NetworkInfo {
  final String networkId;
  final String networkName;
  final NetworkTopology topology;
  final int nodeCount;
  final Map<String, dynamic> metadata;
  final DateTime lastSeen;

  const NetworkInfo({
    required this.networkId,
    required this.networkName,
    required this.topology,
    required this.nodeCount,
    this.metadata = const {},
    required this.lastSeen,
  });
}

/// Network discovery events
sealed class NetworkDiscoveryEvent extends NetworkEvent {
  NetworkDiscoveryEvent(DateTime timestamp, {super.metadata})
    : super(eventId: 'network_discovery_event', timestamp: timestamp);
}

class NetworkFound extends NetworkDiscoveryEvent {
  final NetworkInfo networkInfo;

  NetworkFound(this.networkInfo) : super(DateTime.now());
}

class NetworkLost extends NetworkDiscoveryEvent {
  final NetworkInfo networkInfo;

  NetworkLost(this.networkInfo) : super(DateTime.now());
}

class NetworkUpdated extends NetworkDiscoveryEvent {
  final NetworkInfo networkInfo;

  NetworkUpdated(this.networkInfo) : super(DateTime.now());
}

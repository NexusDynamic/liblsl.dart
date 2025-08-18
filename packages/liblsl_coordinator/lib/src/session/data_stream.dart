import 'dart:async';
import 'stream_config.dart';

/// Represents a single data stream within a coordination session
abstract class DataStream {
  /// Unique identifier for this stream
  String get streamId;
  
  /// Configuration for this stream
  StreamConfig get config;
  
  /// Whether this stream is currently active
  bool get isActive;
  
  /// Start the stream
  Future<void> start();
  
  /// Stop the stream
  Future<void> stop();
  
  /// Producer side: sink for sending data
  StreamSink<T>? dataSink<T>();
  
  /// Consumer side: stream for receiving data
  Stream<T>? dataStream<T>();
  
  /// Stream of events for this data stream (started, stopped, error, etc.)
  Stream<DataStreamEvent> get events;
}

/// Events that can occur on a data stream
sealed class DataStreamEvent {
  final String streamId;
  final DateTime timestamp;
  
  const DataStreamEvent(this.streamId, this.timestamp);
}

class DataStreamStarted extends DataStreamEvent {
  DataStreamStarted(String streamId) : super(streamId, DateTime.now());
}

class DataStreamStopped extends DataStreamEvent {
  DataStreamStopped(String streamId) : super(streamId, DateTime.now());
}

class DataStreamError extends DataStreamEvent {
  final String error;
  final Object? cause;
  
  DataStreamError(String streamId, this.error, [this.cause]) : super(streamId, DateTime.now());
}

class DataStreamDataReceived extends DataStreamEvent {
  final dynamic data;
  
  DataStreamDataReceived(String streamId, this.data) : super(streamId, DateTime.now());
}
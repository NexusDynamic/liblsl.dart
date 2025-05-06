//import 'dart:ffi';

import 'package:liblsl/lsl.dart';
//import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/isolate_manager.dart';
//import 'package:liblsl/src/lsl/isolated_inlet.dart';

extension LSLChunkSerializer on LSLSerializer {
  static Map<String, dynamic> serializeChunk<T>(List<LSLSample<T>> chunk) {
    return {
      'chunk': chunk
          .map((sample) => LSLSerializer.serializeSample(sample))
          .toList(),
    };
  }

  static List<LSLSample<T>> deserializeChunk<T>(Map<String, dynamic> data) {
    final List<dynamic> chunkData = data['chunk'] as List<dynamic>;
    return chunkData
        .map(
          (sample) => LSLSerializer.deserializeSample<T>(
            sample as Map<String, dynamic>,
          ),
        )
        .toList();
  }
}

/// Implementation of LSLIsolatedInlet extension for chunked data handling
extension LSLIsolatedInletPullChunk<T> on LSLIsolatedInlet<T> {
  Future<List<LSLSample<T>>> pullChunk({
    int maxSamples = 1024,
    double timeout = 0.0,
  }) async {
    if (!initialized) {
      throw LSLException('Inlet not created');
    }

    // Send message to pull chunk from the isolate
    final response = await isolateManager.sendMessage(
      LSLMessage(LSLMessageType.pullChunk, {
        'maxSamples': maxSamples,
        'timeout': timeout,
      }),
    );

    if (!response.success) {
      throw LSLException('Error pulling chunk: ${response.error}');
    }

    // Deserialize the chunk data
    final List<dynamic> chunkData = response.result as List<dynamic>;
    return LSLChunkSerializer.deserializeChunk<T>(
      chunkData as Map<String, dynamic>,
    );
  }
}

// extension LSLInletIsolatePullChunk<T> on LSLInletIsolate {
//   Future<List<LSLSample<T>>> pullChunk(Map<String, dynamic> data) async {
//     final timeout = data['timeout'] as double;
//     final samplePtr = Pointer.fromAddress(data['pointerAddr'] as int);
//     final ecPtr = Pointer<Int32>.fromAddress(data['ecPointerAddr'] as int);

//     // Return the serialized chunk of samples
//     return
//   }
// }

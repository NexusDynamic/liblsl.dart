---
title: 'Liblsl.dart: A Dart native API for Lab Streaming Layer (LSL)'
tags:
  - Lab Streaming Layer
  - Dart
  - Data streaming
  - Cross-platform
  - Networking
authors:
  - name:
      given-names: Luke Daniel
      surname: Ring
    orcid: 0009-0000-0930-4172
    affiliation: 1
  - name:
      given-names: Anna
      surname: Zamm
    orcid: 0000-0002-3774-3516
    affiliation: 1
  - name:
      given-names: Chris
      surname: Mathys
    orcid: 0000-0003-4079-5453
    affiliation: 3
  - name:
      given-names: Simon Lind
      surname: Kappel
    orcid: 0000-0003-0583-2255
    affiliation: 2
affiliations:
- name: School of Communication and Culture, Department of Linguistics, Cognitive Science and Semiotics, Aarhus University, Denmark
  index: 1
  ror: 01aj84f44
- name:  Department of Electrical and Computer Engineering - Biomedical Engineering, Aarhus University, Denmark
  index: 2
  ror: 01aj84f44
- name: School of Culture and Society - Interacting Minds Centre, Aarhus University, Denmark
  index: 3
  ror: 01aj84f44

date: 1 October 2025
bibliography: paper.bib
---

# Summary

The `liblsl` Dart package is the first implementation of Lab Streaming Layer (LSL) in the Dart and Flutter ecosystem, enabling easy deployment and integration of LSL's multimodal data streaming capabilities into different hardware and software platforms from using the same source code. LSL is a widely-adopted tool for real-time multimodal data acqusition and synchronization in research, and while LSL has been [implemented in many languages](https://labstreaminglayer.readthedocs.io/info/language_wrappers.html), none of these programming languages currently offer Dart and Flutter's 'write-once, deploy everywhere' capacity to target mobile (iOS, Android) and desktop (Linux, macOS, Windows) platforms [@LiblslLanguageWrappers].This package combines native LSL performance, with Dart-specific language features including type-safe inlets and outlets, automated memory management and utilities for high-performance inlet polling and LSL API configuration. 

# Statement of need

Neuroscience and behavioral research increasingly make use of consumer hardware due to its lower cost and sufficient performance for running experiments. However, integration of consumer devices into labaratory data acquisition pipelines can be challenging, requiring platform-specific development which decreases flexibility and hinders reproducibility. The `liblsl` Dart package addresses this gap by enabling researchers to deploy LSL-enabled applications across all major platforms from a single Dart/Flutter codebase. Potential use cases include mobile brain-computer interfaces using an electroencephalography (EEG) headset and a smartphone, hyperscanning studies that simultaneously collect [@zammPracticalGuideEEG2024b] neuroimaging data and behavioural data streamed over LSL from multiple participants using tablets, and distributed experiments where multiple labs using a variety of devices collect methodologically consistent data in a standardized format for analysis. 

# Performance

![Figure 1. Dart liblsl API latency plots. Panel A shows latency for an iPad and a Pixel 7a, each producing and consuming their own 1000 Hz data stream with 16 channels of float data. iPad Latency: n = 180000, Mean = 65µs, SD = 47µs | Pixel Latency: n = 180000, Mean = 281µs, SD = 425µs; Panel B shows latency for two iPads producing and consuming each other's 1000 Hz data stream with 16 channels of float data over a local wired 1Gbps network. iPad (between-device) Latency: n = 180000, Mean = 148µs, SD = 129µs. Note: Dashed lines represent the 1st and 3rd quartiles, solid line represents the median. Outliers > 500 ms not shown, but are included in the summary statistics calcultation.](./figures/plot_latency.png)

By wrapping the native LSL library [@stennerSccnLiblslV11622023] using Dart's native build system and Foreign Function Interface (FFI), this package achieves microsecond-level latencies comparable to native implementations (Figure 1), and provides both low-level access to the full LSL API as well as higher-level abstractions for integration into applications. The results in Figure 1 indicate that while there are device-level difference in latency, ...

# Example

The following code demonstrates how a complete data streaming application can be built in under 30 lines of code:

```dart
import 'package:liblsl/lsl.dart';
import 'dart:async';

void main() async {
  // Describe the stream
  final info = await LSL.createStreamInfo(
    streamName: 'Counter',
    streamType: LSLContentType.markers,
    channelCount: 1,
    sampleRate: LSL_IRREGULAR_RATE,
    channelFormat: LSLChannelFormat.int8,
    sourceId: 'uniqueStreamId123',
  );
  // Create the outlet
  final outlet = await LSL.createOutlet(streamInfo: info);

  // Send data
  for (var i = 0; i < 10; i++) {
    final sample = [i];
    outlet.pushSample(sample);
    await Future.delayed(const Duration(milliseconds: 500));
  }
  // Clean up
  outlet.destroy();
  info.destroy();
}
```

# Impact

LSL lowers the complexity of multimodal time-synchronized data acquisition from multiple devices [@dolmans2020data; @iwamaTwoCommonIssues2024; @kotheLabStreamingLayer2025], and Dart/Flutter simplify cross-platform application development. Together, they provide a powerful toolset for researchers and developers to create flexible, reproducible, and accessible applications for data collection and analysis.


# Acknowledgements

This library builds on [liblsl](https://github.com/sccn/liblsl) by Christian A. Kothe using the [Dart programming language](https://dart.dev/) by the Dart project authors, Google. Thanks to [Chadwick Boulay](https://orcid.org/0000-0003-1747-3931) and members of the [dart_community Discord](https://discord.gg/Qt6DgfAWWx) for help with debugging.

# References

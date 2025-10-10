---
title: 'Liblsl.dart: A Dart native API for Lab Streaming Layer (LSL)'
tags:
  - Lab Streaming Layer
  - Dart
  - Data streaming
  - Cross-platform
  - Multimodal
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
    affiliation: 2
  - name:
      given-names: Simon Lind
      surname: Kappel
    orcid: 0000-0003-0583-2255
    affiliation: 3
affiliations:
- name: School of Communication and Culture, Department of Linguistics, Cognitive Science and Semiotics, Aarhus University, Denmark
  index: 1
  ror: 01aj84f44
- name: School of Culture and Society - Interacting Minds Centre, Aarhus University, Denmark
  index: 2
  ror: 01aj84f44
- name:  Department of Electrical and Computer Engineering - Biomedical Engineering, Aarhus University, Denmark
  index: 3
  ror: 01aj84f44

date: 1 October 2025
bibliography: paper.bib
---

# Summary

The `liblsl` Dart package is the first implementation of [Lab Streaming Layer (LSL)](https://labstreaminglayer.org/) in the [Dart](https://dart.dev/) and [Flutter](https://flutter.dev/) ecosystem, enabling researchers to deploy multi-modal LSL-enabled data acquisition applications across mobile (iOS, Android) and desktop (Linux, macOS, Windows) platforms from shared source code. Unlike [existing LSL implementations](https://labstreaminglayer.readthedocs.io/info/language_wrappers.html) that are platform-specific or restricted to desktop devices [@LiblslLanguageWrappers], this package leverages Dart/Flutter's cross-platform capabilities while maintaining the microsecond-level latency requirements of neurophysiological research through direct Foreign Function Interface (FFI) bindings to the native LSL C library [@stennerSccnLiblslV11622023].



# Statement of need

Neuroscience and behavioral research increasingly make use of consumer hardware due to its lower cost and sufficient performance for running experiments [@roqueRealTimeMobileEEG2025], however, the integration of consumer devices into laboratory data acquisition pipelines often requires platform-specific development and adds complexity to the data alignment and collection process, both of which can hinder flexibility and reproducibility [@iwamaTwoCommonIssues2024]. The LSL system partially adresses some of the complexity via a software based unified method of time-synchronized data acquisition across heterogeneous hardware and software systems [@kotheLabStreamingLayer2025]. LSL handles clock synchronization, network communication, and data buffering, making it particularly valuable for applications requiring precise temporal alignment of multiple data sources. The `liblsl` Dart package further reduces the complexity by enabling researchers to deploy LSL-enabled applications across all major platforms from a single Dart/Flutter codebase. Potential use cases include general multimodal experiments [@wangScopingReviewUse2023; @dolmans2020data], mobile brain-computer interfaces using an EEG headset and a smartphone [@stopczynskiSmartphoneBrainScanner2014; @debenerUnobtrusiveAmbulatoryEEG2015; @blumEEGRecordingOnline2017a], hyperscanning studies [@zammPracticalGuideEEG2024b] that simultaneously collect neuroimaging data from multiple participants [@luftSocialSynchronizationBrain2022; @boggioSocialAffectiveNeuroscience2023; roqueRealTimeMobileEEG2025], and distributed experiments where multiple labs using a variety of devices collect methodologically consistent data in a standardized format for analysis [@demazureDistributedRemoteEEG2021; @schultzLinkingLabsInterconnecting2021]. 



# Performance

## Methods

Performance was characterized under controlled conditions to isolate different sources of latency. Local device tests measured the computational overhead of the package's Dart API by having a single device both produce and consume 1000 Hz data streams (16 channels, float32 format), representing typical EEG recording parameters. Network tests used two iPad Pro M4s connected via 1Gbps USB-C Ethernet adaptors to a consumer-grade gigabit router. All tests were run for 3 minutes (approximately 180,000 samples) to ensure statistical reliability. Measurements represent end-to-end latency from sample production to consumption, including API call overhead, serialization, network transmission, and deserialization.

## Results and Discussion

![Latency characterization of the liblsl Dart package. **(A)** Local performance on iPad Pro M4 (left) and Pixel 7a (right), each producing and consuming its own 1000 Hz data stream. **(B)** Network performance between two iPads over 1Gbps Ethernet. Violin plots show median (solid line) with first and third quartiles (dashed lines). See Methods for experimental details and Table 1 for complete statistics. *Note: Outliers >500µs were excluded from visualization but are included in statistics*.](./figures/plot_latency.png)

| Condition | Device      |      n | Min (µs) | Max (µs) | Mean (µs) | SD (µs) |
|:----------|:------------|-------:|---------:|---------:|----------:|--------:|
| Local     | iPad Pro M4 | 180000 |       21 |     4264 |        65 |      47 |
| Local     | Pixel 7a    | 179900 |       42 |    18809 |       274 |     434 |
| Network   | iPad Pro M4 | 180000 |       60 |     4261 |       148 |     129 |

Table: Summary of latency measurements.

Table 1 summarizes latency statistics across conditions and devices. Figure 1 illustrates the distribution of the relevant performance characteristics: (A) single-device performance showing the API's computational overhead when producing and consuming data locally (iPad: µ=65µs, σ=47µs; Pixel 7a: µ=274µs, σ=434µs), where standard deviations reflect timing jitter inherent to the operating system's thread scheduling and (B) network performance between two iPads over a 1Gbps wired connection (µ=148µs, σ=129µs). These results confirm that the Dart wrapper introduces minimal overhead beyond the base LSL C library performance, with observed differences primarily attributable to device hardware capabilities and network infrastructure rather than the API implementation itself.

The observed latencies are consistent with previous benchmarking of native LSL implementations [@kotheLabStreamingLayer2025] and demonstrate that this package preserves the real-time performance characteristics required for neurophysiological applications [@iwamaTwoCommonIssues2024]. The local processing latencies (65-274µs) are well below typical neurophysiological event timing requirements (<1ms), confirming suitability for EEG, electromyography (EMG), and other biosignal applications[^1]. The mean inter-device network latency (148µs) demonstrates that network overhead remains minimal on well-configured local networks[^2], though researchers should note that wireless networks and other factors including network traffic congestion may introduce additional jitter. The device-dependent variation (iPad: 65µs vs Pixel 7a: 274µs) reflects differences in CPU architecture, device network hardware and operating system scheduling rather than API limitations, indicating that platform selection should be validated through careful testing based on the requirements of the specific application.

[^1]: Raw data and source code used for generating the figures and statistics are available at: [https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/liblsl/paper/analysis](https://github.com/NexusDynamic/liblsl.dart/tree/main/packages/liblsl/paper/analysis)

[^2]: In a lab context, this typically may be achieved by using a closed, wired network, with a high throughput hardware switch or router, and by disabling firewalls, traffic shaping and other features that may introduce latency such as deep packet inspection.

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

  // Send data at 2 Hz (configurable for your application)
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

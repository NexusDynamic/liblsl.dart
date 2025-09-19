---
title: 'Liblsl.dart: A Dart native API for Lab Streaming Layer (LSL)'
tags:
  - Lab Streaming Layer
  - Dart
  - Data streaming
  - Cross-platform
  - Networking
authors:
  - name: Luke D. Ring
    orcid: 0009-0000-0930-4172
    equal-contrib: true
    affiliation: 1
affiliations:
 - name: School of Communication and Culture, Department of Linguistics, Cognitive Science and Semiotics, Aarhus University, Denmark
   index: 1
   ror: 01aj84f44
date: 19 September 2025
bibliography: paper.bib
---

# Summary

The `liblsl` Dart package provides an API for Lab Streaming Layer (LSL) in Dart and Flutter applications. It enables real-time data streaming and synchronization across multiple platforms, including mobile (iOS, Android) and desktop (Windows, macOS, Linux). The package wraps the native LSL library [@stennerSccnLiblslV11622023:2023] using Dart's native build system, which affords high performance and low latency data streaming. Streamed data can be processed in real-time, or recorded for subsequent analysis.

# Statement of need

In academic research and industry settings, there is often a need to acquire, synchronize, and process data from multiple sources in real-time . For example, multimodal experiments, group research and electroencephalography (EEG) hyperscanning [@zammPracticalGuideEEG2024b:2024] studies will often simultaneously record neural (EEG), behavioural (e.g. interaction with a device) and biometric (e.g. heart rate, skin conductance) data from multiple participants. In such experiments, ensuring recorded data is precisely time-synchronized across all devices can present a significant challenge [@dolmans2020data:2020], yet it is critical for valid analysis and interpretation. LSL is designed, and widely for multimodal data acquisition and synchronization as a software-based alternative to bespoke or costly hardware solutions [@kotheLabStreamingLayer2025; @iwamaTwoCommonIssues2024:2024].

...


# Acknowledgements

- [Christian A. Kothe: liblsl](https://github.com/sccn/liblsl) for the LSL library
- The [Dart programming language](https://dart.dev/) by Google

# References

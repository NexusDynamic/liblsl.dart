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
      given-names: Simon Lind
      surname: Kappel
    orcid: 0000-0003-0583-2255
    affiliation: 2
  - name:
      given-names: Chris
      surname: Mathys
    orcid: 0000-0003-4079-5453
    affiliation: 3
  - name:
      given-names: Anna
      surname: Zamm
    orcid: 0000-0002-3774-3516
    affiliation: 1
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


date: 22 September 2025
bibliography: paper.bib
---

# Summary

The `liblsl` Dart package provides an API for Lab Streaming Layer (LSL) in Dart and Flutter applications. It enables real-time data streaming and synchronization across multiple platforms, including mobile (iOS, Android) and desktop (Windows, macOS, Linux). The package wraps the native LSL library [@stennerSccnLiblslV11622023] using Dart's native build system, which affords high performance and low latency data streaming. Streamed data can be processed in real-time or recorded for subsequent analysis.

# Statement of need

In academic research and industry settings, there is often a need to acquire, synchronize, and process data from multiple sources in real-time . For example, multimodal experiments, group research and electroencephalography (EEG) hyperscanning [@zammPracticalGuideEEG2024b] studies will often simultaneously record neural, behavioural (e.g. input and reaction times) and biometric (e.g. heart rate, skin conductance) data from multiple participants. In such experiments, ensuring recorded data is precisely time-synchronized across all devices can present a significant challenge [@dolmans2020data], yet it is critical for valid analysis and interpretation. LSL is designed, and widely used for multimodal data acquisition and synchronization as a software-based alternative to bespoke or costly hardware solutions [@kotheLabStreamingLayer2025; @iwamaTwoCommonIssues2024].

A Dart API for LSL allows developers and researchers to integrate LSL data stream production and consumption into Dart and Flutter applications, making it easier to build software that runs on a wide range of devices and platforms, lowering the barrier for entry and cost of replicating studies across labs and contexts.


# Acknowledgements

- [liblsl](https://github.com/sccn/liblsl) by Christian A. Kothe
- [Dart programming language](https://dart.dev/) by the Dart project authors, Google

# References

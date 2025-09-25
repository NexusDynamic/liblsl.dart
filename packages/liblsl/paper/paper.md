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
affiliations:
- name: School of Communication and Culture, Department of Linguistics, Cognitive Science and Semiotics, Aarhus University, Denmark
  index: 1
  ror: 01aj84f44

date: 23 September 2025
bibliography: paper.bib
---

# Summary

The `liblsl` Dart package provides an API for Lab Streaming Layer (LSL) in Dart and Flutter applications. `liblsl` language wrappers exist for many programming languages, these languages, including the current `liblsl.dart` package are listed in the official [`liblsl` documentation](https://labstreaminglayer.readthedocs.io/info/language_wrappers.html) [@LiblslLanguageWrappers]. The Dart API for LSL allows developers and researchers to integrate LSL data stream production and consumption into Dart and Flutter applications, making it easier to build software that runs on a wide range of devices and platforms, lowering the barrier for entry and cost of replicating studies across labs and contexts. It enables real-time data streaming and synchronization across multiple platforms, including mobile (iOS, Android) and desktop (Windows, macOS, Linux). The package wraps the native LSL library [@stennerSccnLiblslV11622023] using Dart's native build system, which affords high performance and low latency data streaming. Streamed data can be processed in real-time or recorded for subsequent analysis. This package is designed to provide both a low-level interface to the native LSL library and a higher-level utility API to remove the need for direct memory management and provide additional functionality, while keeping performance as close to the native library as possible (Figure 1).

![Figure 1. Distribution plots showing latency (Panel A) and inter-sample interval (ISI, Panel B) for two iPads, both producing one, and consuming two (one stream from itself, one stream from the other device) data streams with 16 channels each at a frequency of 1000Hz over a 1Gbps wired ethernet connection. iPad 1 Latency: n = 180000, Mean = 42µs, SD = 45µs | iPad 2 Latency: n = 179962, Mean = 49µs, SD = 48µs; iPad 1 ISI: n = 179999, Mean = 1000µs, SD = 115µs | iPad 2 ISI: n = 179999, Mean = 1000µs, SD = 131µs.](./figures/plot_latency_isi.png)

# Statement of need

In academic research and industry settings, there is often a need to acquire, synchronize, and process data from multiple sources in real-time . For example, multimodal experiments, group research and electroencephalography (EEG) hyperscanning [@zammPracticalGuideEEG2024b] studies will often simultaneously record neural, behavioural (e.g. input and reaction times) and biometric (e.g. heart rate, skin conductance) data from multiple participants. In such experiments, ensuring recorded data is precisely time-synchronized across all devices can present a significant challenge [@dolmans2020data], yet it is critical for valid analysis and interpretation. LSL is designed, and widely used for multimodal data acquisition and synchronization as a software-based alternative to bespoke or costly hardware solutions [@kotheLabStreamingLayer2025; @iwamaTwoCommonIssues2024]. This current package provides a novel way to integrate LSL into applications that run on lab computers as well as consumer devices including smartphones and tablets. For researchers and other users of this package, real-time and offline data acquisition can be built from a single codebase, and source code with platform-specific compiled applications may be shared to provide an acessible means for running distributed experiments and replicating studies.

# Acknowledgements

## PhD Supervision

- [Anna Zamm](https://pure.au.dk/portal/en/persons/azamm%40cc.au.dk), School of Communication and Culture, Department of Linguistics, Cognitive Science and Semiotics, Aarhus University, Denmark.
- [Simon Lind Kappel](https://pure.au.dk/portal/en/persons/slk%40ece.au.dk), Department of Electrical and Computer Engineering - Biomedical Engineering, Aarhus University, Denmark.
- [Chris Mathys](https://pure.au.dk/portal/en/persons/chmathys%40cas.au.dk), School of Culture and Society - Interacting Minds Centre, Aarhus University, Denmark.

## Software

- [liblsl](https://github.com/sccn/liblsl) by Christian A. Kothe
- [Dart programming language](https://dart.dev/) by the Dart project authors, Google

# References

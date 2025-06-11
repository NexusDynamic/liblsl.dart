# Enhanced LSL Timing Analysis

This package provides comprehensive timing analysis for LSL (Lab Streaming Layer) timing tests, with particular focus on accurate cross-device latency measurements using time correction interpolation.

## Key Features

### 1. Time Correction Interpolation

The enhanced timing analysis service addresses the fundamental challenge of synchronizing timing measurements across devices with different clocks. LSL provides time correction values that represent the offset between different device clocks, but these corrections can change over time and are not available for every sample.

#### How Time Correction Works

- **LSL Time Correction**: Each inlet (receiving device) can report a time correction value that represents the offset between its local clock and the sender's clock
- **Dynamic Nature**: Time corrections change over time due to clock drift and network conditions
- **Interpolation**: Our algorithm interpolates time corrections between known values for more accurate timing

#### Interpolation Algorithm

1. **Collection**: Extract all time correction samples for each device-source pair
2. **Temporal Sorting**: Sort corrections by timestamp to create a timeline
3. **Linear Interpolation**: For any given timestamp:
   - If before all corrections: Use the earliest correction
   - If after all corrections: Use the latest correction
   - If between corrections: Linear interpolation between neighboring values
4. **Bilateral Correction**: Apply corrections to both sender and receiver timestamps

### 2. Enhanced Latency Calculation

```dart
// Traditional approach (inaccurate for cross-device measurements)
latency = received_time - sent_time

// Enhanced approach with time correction
corrected_received_time = received_time + receiver_time_correction
corrected_sent_time = sent_time + sender_time_correction
accurate_latency = corrected_received_time - corrected_sent_time
```

### 3. Comprehensive Analysis Results

The enhanced service provides:

- **Inter-sample intervals**: Production timing consistency for each device
- **Cross-device latencies**: Accurate latency measurements between all device pairs
- **Raw vs Corrected**: Side-by-side comparison showing the impact of time correction
- **Statistical measures**: Mean, median, standard deviation, min/max for all metrics
- **Outlier removal**: 2% trimming from both ends to reduce noise impact

## Services Overview

### TimingAnalysisService (Basic)
- Simple time correction application
- Limited to receiver-side corrections only
- No interpolation

### EfficientTimingAnalysisService (Performance)
- Optimized for large datasets using DartFrame operations
- No time correction support
- Fast but less accurate for cross-device measurements

### EnhancedTimingAnalysisService (Recommended)
- Full time correction interpolation
- Bilateral correction (sender + receiver)
- Most accurate cross-device latency measurements
- Maintains both raw and corrected results

## Usage

```dart
final analysisService = EnhancedTimingAnalysisService();

// Calculate inter-sample intervals
final intervalResults = analysisService.calculateInterSampleIntervals(csvData);

// Calculate cross-device latencies with time correction
final latencyResults = analysisService.calculateLatencies(csvData);

// Check if time correction was applied
for (final result in latencyResults) {
  if (result.timeCorrectionApplied) {
    print('Corrected latency: ${result.mean}ms');
    print('Raw latency: ${result.rawLatencies.mean}ms');
  }
}
```

## Data Requirements

The analysis expects TSV files with the following columns:
- `event_type`: "EventType.sampleSent" or "EventType.sampleReceived"
- `reportingDeviceId`: ID of the device reporting the event
- `sourceId`: ID of the stream source
- `lsl_clock`: LSL timestamp
- `counter`: Sample counter for matching sent/received pairs
- `lslTimeCorrection`: Time correction value (when available)

## Time Correction Best Practices

1. **Frequent Corrections**: Configure LSL to provide time corrections frequently (every sample if possible)
2. **Initial Timeout**: Allow sufficient time for initial time correction establishment
3. **Network Stability**: Stable network conditions improve time correction accuracy
4. **Clock Synchronization**: While not required, synchronized system clocks improve baseline accuracy

## Visualization

The enhanced stats widget provides:
- **Histogram comparisons**: Raw vs time-corrected latency distributions
- **Color coding**: Green for time-corrected results, grey for raw data
- **Status indicators**: Clear indication of whether time correction was applied
- **Statistical summaries**: Comprehensive metrics for both datasets

## Known Limitations

1. **Initial Samples**: Time correction may not be available for the first few samples
2. **Network Jitter**: Highly variable network conditions can affect correction accuracy
3. **Clock Drift**: Extreme clock drift may require more sophisticated algorithms
4. **Single-Device Tests**: Time correction has no effect on single-device measurements

## Performance Considerations

- **Memory Usage**: Enhanced analysis stores additional correction samples
- **Processing Time**: Interpolation adds computational overhead
- **Data Size**: Large datasets may require more memory for correction tracking

The enhanced timing analysis provides the most accurate cross-device latency measurements available, essential for precise timing validation in distributed LSL environments.
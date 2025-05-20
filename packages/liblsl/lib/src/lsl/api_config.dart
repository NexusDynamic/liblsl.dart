import 'dart:io';

/// LSL API Configuration class for Dart FFI wrapper of liblsl
/// Represents the configuration options available in liblsl's configuration
/// file.
/// For more details, refer to the official LSL documentation:
/// https://labstreaminglayer.readthedocs.io/info/lslapicfg.html
/// Specifically, if you would like to use LSL over wireless networks, the
/// documentation recommends using the following configuration:
/// https://labstreaminglayer.readthedocs.io/info/lslapicfg.html#tuning
/// [timeProbeMaxRTT] = 0.100
/// [timeProbeInterval] = 0.010
/// [timeProbeCount] = 10
/// [timeUpdateInterval] = 0.25
/// [multicastMinRTT] = 0.100
/// [multicastMaxRTT] = 30
class LSLApiConfig {
  // PORTS SECTION
  /// The multicast port used for discovery and data streaming
  /// Default: 16571
  int multicastPort;

  /// The starting port for the range of ports used for outlets.
  /// The ports used are [basePort] to [basePort] + [portRange] - 1, where
  /// TCP and UDP ports alternate (e.g. if starting port is even, all TCP ports
  /// are even and all UDP ports are odd, and vice versa).
  /// The default value is 16572.
  int basePort;

  /// The number of ports to use for outlets, the effective number of outlets
  /// is [portRange] / 2.
  /// The default value is 32.
  /// While it may be necessary to create a large range, this can potentially
  /// slow down the discovery process, due to each port having to be scanned.
  int portRange;

  /// The IPv6 mode to use. Possible values are:
  /// - [IPv6Mode.disable]: Only use IPv4
  /// - [IPv6Mode.allow]: Use both IPv4 and IPv6
  /// - [IPv6Mode.force]: Only use IPv6
  IPv6Mode ipv6;

  // MULTICAST SECTION
  /// The scope of multicast addresses to use for discovery.
  /// Possible values are:
  /// - [ResolveScope.machine]: Local to the machine
  /// - [ResolveScope.link]: Local to the subnet
  /// - [ResolveScope.site]: Local to the site as defined by local policy
  ResolveScope resolveScope;

  /// The address to listen on for incoming multicast packets.
  String? listenAddress;

  /// The IPv6 multicast group to use for discovery.
  String? ipv6MulticastGroup;

  /// The list MAC addresses to use for discovery.
  List<String> machineAddresses;

  /// The list of multicast addresses to use for discovery (link level).
  List<String> linkAddresses;

  /// The list of multicast addresses to use for discovery (site level).
  List<String> siteAddresses;

  /// The list of multicast addresses to use for discovery (organization level).
  List<String> organizationAddresses;

  /// The list of multicast addresses to use for discovery (global level).
  List<String> globalAddresses;

  /// The list of multicast addresses to use for discovery (override).
  List<String> addressesOverride;

  /// The TTL (Time to Live) value for multicast packets.
  /// The default value is -1, which should be used, unless you have e.g. inter-
  /// site multicast routing enabled.
  int ttlOverride;

  // LAB SECTION
  /// The list of known peers for the lab. This is a fallback in case the
  /// multicast discovery fails.
  /// This is a list of IP addresses or hostnames.
  List<String> knownPeers;

  /// The session ID for the lab. This is used to identify the lab in the
  /// multicast discovery process.
  String sessionId;

  // TUNING SECTION
  /// The interval in seconds to check for dead peers.
  double watchdogCheckInterval;

  /// The time threshold in seconds to consider a peer dead.
  double watchdogTimeThreshold;

  /// The minimum round-trip time (RTT) in seconds for multicast packets.
  double multicastMinRTT;

  /// The maximum round-trip time (RTT) in seconds for multicast packets.
  double multicastMaxRTT;

  /// The minimum round-trip time (RTT) in seconds for unicast packets.
  double unicastMinRTT;

  /// The maximum round-trip time (RTT) in seconds for unicast packets.
  double unicastMaxRTT;

  /// The interval in seconds to resolve multicast addresses.
  double continuousResolveInterval;

  /// The timer resolution in seconds. This is used to determine the
  double timerResolution;

  /// maximum time to wait for a response from a peer.
  int maxCachedQueries;

  /// The interval in seconds to update the time.
  double timeUpdateInterval;

  /// The minimum number of probes to use for time updates.
  int timeUpdateMinProbes;

  /// The number of probes to use for time updates.
  int timeProbeCount;

  /// The interval in seconds to wait between probes.
  double timeProbeInterval;

  /// The maximum round-trip time (RTT) in seconds for time probes.
  double timeProbeMaxRTT;

  /// The amount of time in milliseconds to reserve for the outlet buffer.
  int outletBufferReserveMs;

  /// The number of samples to reserve for the outlet buffer.
  int outletBufferReserveSamples;

  /// The size of the socket buffer to use for sending data.
  int sendSocketBufferSize;

  /// The amount of time in milliseconds to reserve for the inlet buffer.
  int inletBufferReserveMs;

  /// The number of samples to reserve for the inlet buffer.
  int inletBufferReserveSamples;

  /// The size of the socket buffer to use for receiving data.
  int receiveSocketBufferSize;

  /// The smoothing half-time in seconds for the time post-processor.
  double smoothingHalftime;

  /// Whether to force the use of default timestamps for all streams.
  bool forceDefaultTimestamps;

  // LOG SECTION
  /// The log level to use. Possible values are:
  /// - -2: error
  /// - -1: warning
  /// - 0: info
  /// - 1-9: increasing level of detail
  int logLevel;

  /// The file to use for logging. If null, file logging is disabled.
  String? logFile;

  /// Constructor with default values matching the default LSL configuration
  LSLApiConfig({
    // Ports section
    this.multicastPort = 16571,
    this.basePort = 16572,
    this.portRange = 32,
    this.ipv6 = IPv6Mode.allow,

    // Multicast section
    this.resolveScope = ResolveScope.site,
    this.listenAddress,
    this.ipv6MulticastGroup,
    this.machineAddresses = const ['{FF31:113D:6FDD:2C17:A643:FFE2:1BD1:3CD2}'],
    this.linkAddresses = const [
      '{255.255.255.255, 224.0.0.183, FF02:113D:6FDD:2C17:A643:FFE2:1BD1:3CD2}',
    ],
    this.siteAddresses = const [
      '{239.255.172.215, FF05:113D:6FDD:2C17:A643:FFE2:1BD1:3CD2}',
    ],
    this.organizationAddresses = const [],
    this.globalAddresses = const [],
    this.addressesOverride = const [],
    this.ttlOverride = -1,

    // Lab section
    this.knownPeers = const [],
    this.sessionId = 'default',

    // Tuning section
    this.watchdogCheckInterval = 15.0,
    this.watchdogTimeThreshold = 15.0,
    this.multicastMinRTT = 0.5,
    this.multicastMaxRTT = 3.0,
    this.unicastMinRTT = 0.75,
    this.unicastMaxRTT = 5.0,
    this.continuousResolveInterval = 0.5,
    this.timerResolution = 1.0,
    this.maxCachedQueries = 100,
    this.timeUpdateInterval = 2.0,
    this.timeUpdateMinProbes = 6,
    this.timeProbeCount = 8,
    this.timeProbeInterval = 0.064,
    this.timeProbeMaxRTT = 0.128,
    this.outletBufferReserveMs = 5000,
    this.outletBufferReserveSamples = 128,
    this.sendSocketBufferSize = 0,
    this.inletBufferReserveMs = 5000,
    this.inletBufferReserveSamples = 128,
    this.receiveSocketBufferSize = 0,
    this.smoothingHalftime = 90.0,
    this.forceDefaultTimestamps = false,

    // Log section
    this.logLevel = -2,
    this.logFile,
  });

  /// Creates a copy of this configuration with the given changes
  LSLApiConfig copyWith({
    int? multicastPort,
    int? basePort,
    int? portRange,
    IPv6Mode? ipv6,
    ResolveScope? resolveScope,
    String? listenAddress,
    String? ipv6MulticastGroup,
    List<String>? machineAddresses,
    List<String>? linkAddresses,
    List<String>? siteAddresses,
    List<String>? organizationAddresses,
    List<String>? globalAddresses,
    List<String>? addressesOverride,
    int? ttlOverride,
    List<String>? knownPeers,
    String? sessionId,
    double? watchdogCheckInterval,
    double? watchdogTimeThreshold,
    double? multicastMinRTT,
    double? multicastMaxRTT,
    double? unicastMinRTT,
    double? unicastMaxRTT,
    double? continuousResolveInterval,
    double? timerResolution,
    int? maxCachedQueries,
    double? timeUpdateInterval,
    int? timeUpdateMinProbes,
    int? timeProbeCount,
    double? timeProbeInterval,
    double? timeProbeMaxRTT,
    int? outletBufferReserveMs,
    int? outletBufferReserveSamples,
    int? sendSocketBufferSize,
    int? inletBufferReserveMs,
    int? inletBufferReserveSamples,
    int? receiveSocketBufferSize,
    double? smoothingHalftime,
    bool? forceDefaultTimestamps,
    int? logLevel,
    String? logFile,
  }) {
    return LSLApiConfig(
      multicastPort: multicastPort ?? this.multicastPort,
      basePort: basePort ?? this.basePort,
      portRange: portRange ?? this.portRange,
      ipv6: ipv6 ?? this.ipv6,
      resolveScope: resolveScope ?? this.resolveScope,
      listenAddress: listenAddress ?? this.listenAddress,
      ipv6MulticastGroup: ipv6MulticastGroup ?? this.ipv6MulticastGroup,
      machineAddresses: machineAddresses ?? List.from(this.machineAddresses),
      linkAddresses: linkAddresses ?? List.from(this.linkAddresses),
      siteAddresses: siteAddresses ?? List.from(this.siteAddresses),
      organizationAddresses:
          organizationAddresses ?? List.from(this.organizationAddresses),
      globalAddresses: globalAddresses ?? List.from(this.globalAddresses),
      addressesOverride: addressesOverride ?? List.from(this.addressesOverride),
      ttlOverride: ttlOverride ?? this.ttlOverride,
      knownPeers: knownPeers ?? List.from(this.knownPeers),
      sessionId: sessionId ?? this.sessionId,
      watchdogCheckInterval:
          watchdogCheckInterval ?? this.watchdogCheckInterval,
      watchdogTimeThreshold:
          watchdogTimeThreshold ?? this.watchdogTimeThreshold,
      multicastMinRTT: multicastMinRTT ?? this.multicastMinRTT,
      multicastMaxRTT: multicastMaxRTT ?? this.multicastMaxRTT,
      unicastMinRTT: unicastMinRTT ?? this.unicastMinRTT,
      unicastMaxRTT: unicastMaxRTT ?? this.unicastMaxRTT,
      continuousResolveInterval:
          continuousResolveInterval ?? this.continuousResolveInterval,
      timerResolution: timerResolution ?? this.timerResolution,
      maxCachedQueries: maxCachedQueries ?? this.maxCachedQueries,
      timeUpdateInterval: timeUpdateInterval ?? this.timeUpdateInterval,
      timeUpdateMinProbes: timeUpdateMinProbes ?? this.timeUpdateMinProbes,
      timeProbeCount: timeProbeCount ?? this.timeProbeCount,
      timeProbeInterval: timeProbeInterval ?? this.timeProbeInterval,
      timeProbeMaxRTT: timeProbeMaxRTT ?? this.timeProbeMaxRTT,
      outletBufferReserveMs:
          outletBufferReserveMs ?? this.outletBufferReserveMs,
      outletBufferReserveSamples:
          outletBufferReserveSamples ?? this.outletBufferReserveSamples,
      sendSocketBufferSize: sendSocketBufferSize ?? this.sendSocketBufferSize,
      inletBufferReserveMs: inletBufferReserveMs ?? this.inletBufferReserveMs,
      inletBufferReserveSamples:
          inletBufferReserveSamples ?? this.inletBufferReserveSamples,
      receiveSocketBufferSize:
          receiveSocketBufferSize ?? this.receiveSocketBufferSize,
      smoothingHalftime: smoothingHalftime ?? this.smoothingHalftime,
      forceDefaultTimestamps:
          forceDefaultTimestamps ?? this.forceDefaultTimestamps,
      logLevel: logLevel ?? this.logLevel,
      logFile: logFile ?? this.logFile,
    );
  }

  /// Parse a configuration string in INI format
  factory LSLApiConfig.fromString(String iniContent) {
    final config = LSLApiConfig();

    // Parse the INI content and populate the configuration
    final lines = iniContent.split('\n');
    ConfigSection? currentSection;

    for (var line in lines) {
      line = line.trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith(';')) continue;

      // Check for section header
      if (line.startsWith('[') && line.endsWith(']')) {
        final sectionName = line.substring(1, line.length - 1).toLowerCase();
        currentSection = ConfigSection.values.firstWhereOrNull(
          (s) => s.name.toLowerCase() == sectionName,
        );
        continue;
      }

      // Skip if no valid section found
      if (currentSection == null) continue;

      // Parse key-value pairs
      final parts = line.split('=');
      if (parts.length < 2) continue;

      final key = parts[0].trim();
      final value = parts.sublist(1).join('=').trim();

      config._setValue(currentSection, key, value);
    }

    return config;
  }

  /// Create a configuration from a file
  static Future<LSLApiConfig> fromFile(String filePath) async {
    try {
      final file = File(filePath);
      final content = await file.readAsString();
      return LSLApiConfig.fromString(content);
    } catch (e) {
      throw Exception('Failed to load LSL configuration from file: $e');
    }
  }

  /// Write the configuration to a file
  Future<void> writeToFile(String filePath) async {
    try {
      final file = File(filePath);
      await file.writeAsString(toIniString());
    } catch (e) {
      throw Exception('Failed to write LSL configuration to file: $e');
    }
  }

  /// Set a configuration value based on section and key
  void _setValue(ConfigSection section, String key, String value) {
    final keyLower = key.toLowerCase();

    switch (section) {
      case ConfigSection.ports:
        if (keyLower == 'multicastport') {
          multicastPort = int.tryParse(value) ?? multicastPort;
        } else if (keyLower == 'baseport') {
          basePort = int.tryParse(value) ?? basePort;
        } else if (keyLower == 'portrange') {
          portRange = int.tryParse(value) ?? portRange;
        } else if (keyLower == 'ipv6') {
          ipv6 = _parseIPv6Mode(value);
        }
        break;

      case ConfigSection.multicast:
        if (keyLower == 'resolvescope') {
          resolveScope = _parseResolveScope(value);
        } else if (keyLower == 'listenaddress') {
          listenAddress = value.isEmpty ? null : value;
        } else if (keyLower == 'ipv6multicastgroup') {
          ipv6MulticastGroup = value.isEmpty ? null : value;
        } else if (keyLower == 'machineaddresses') {
          machineAddresses = _parseAddressList(value);
        } else if (keyLower == 'linkaddresses') {
          linkAddresses = _parseAddressList(value);
        } else if (keyLower == 'siteaddresses') {
          siteAddresses = _parseAddressList(value);
        } else if (keyLower == 'organizationaddresses') {
          organizationAddresses = _parseAddressList(value);
        } else if (keyLower == 'globaladdresses') {
          globalAddresses = _parseAddressList(value);
        } else if (keyLower == 'addressesoverride') {
          addressesOverride = _parseAddressList(value);
        } else if (keyLower == 'ttloverride') {
          ttlOverride = int.tryParse(value) ?? ttlOverride;
        }
        break;

      case ConfigSection.lab:
        if (keyLower == 'knownpeers') {
          knownPeers = _parseAddressList(value);
        } else if (keyLower == 'sessionid') {
          sessionId = value;
        }
        break;

      case ConfigSection.tuning:
        _setTuningValue(keyLower, value);
        break;

      case ConfigSection.log:
        if (keyLower == 'level') {
          logLevel = int.tryParse(value) ?? logLevel;
        } else if (keyLower == 'file') {
          logFile = value.isEmpty ? null : value;
        }
        break;
    }
  }

  /// Set tuning values (handled separately due to the large number)
  void _setTuningValue(String key, String value) {
    switch (key) {
      case 'watchdogcheckinterval':
        watchdogCheckInterval = double.tryParse(value) ?? watchdogCheckInterval;
        break;
      case 'watchdogtimethreshold':
        watchdogTimeThreshold = double.tryParse(value) ?? watchdogTimeThreshold;
        break;
      case 'multicastminrtt':
        multicastMinRTT = double.tryParse(value) ?? multicastMinRTT;
        break;
      case 'multicastmaxrtt':
        multicastMaxRTT = double.tryParse(value) ?? multicastMaxRTT;
        break;
      case 'unicastminrtt':
        unicastMinRTT = double.tryParse(value) ?? unicastMinRTT;
        break;
      case 'unicastmaxrtt':
        unicastMaxRTT = double.tryParse(value) ?? unicastMaxRTT;
        break;
      case 'continuousresolveinterval':
        continuousResolveInterval =
            double.tryParse(value) ?? continuousResolveInterval;
        break;
      case 'timerresolution':
        timerResolution = double.tryParse(value) ?? timerResolution;
        break;
      case 'maxcachedqueries':
        maxCachedQueries = int.tryParse(value) ?? maxCachedQueries;
        break;
      case 'timeupdateinterval':
        timeUpdateInterval = double.tryParse(value) ?? timeUpdateInterval;
        break;
      case 'timeupdateminprobes':
        timeUpdateMinProbes = int.tryParse(value) ?? timeUpdateMinProbes;
        break;
      case 'timeprobecount':
        timeProbeCount = int.tryParse(value) ?? timeProbeCount;
        break;
      case 'timeprobeinterval':
        timeProbeInterval = double.tryParse(value) ?? timeProbeInterval;
        break;
      case 'timeprobemaxrtt':
        timeProbeMaxRTT = double.tryParse(value) ?? timeProbeMaxRTT;
        break;
      case 'outletbufferreservems':
        outletBufferReserveMs = int.tryParse(value) ?? outletBufferReserveMs;
        break;
      case 'outletbufferreservesamples':
        outletBufferReserveSamples =
            int.tryParse(value) ?? outletBufferReserveSamples;
        break;
      case 'sendsocketbuffersize':
        sendSocketBufferSize = int.tryParse(value) ?? sendSocketBufferSize;
        break;
      case 'inletbufferreservems':
        inletBufferReserveMs = int.tryParse(value) ?? inletBufferReserveMs;
        break;
      case 'inletbufferreservesamples':
        inletBufferReserveSamples =
            int.tryParse(value) ?? inletBufferReserveSamples;
        break;
      case 'receivesocketbuffersize':
        receiveSocketBufferSize =
            int.tryParse(value) ?? receiveSocketBufferSize;
        break;
      case 'smoothinghalftime':
        smoothingHalftime = double.tryParse(value) ?? smoothingHalftime;
        break;
      case 'forcedefaulttimestamps':
        forceDefaultTimestamps = value.toLowerCase() == 'true';
        break;
    }
  }

  /// Parse IPv6 mode from string
  IPv6Mode _parseIPv6Mode(String value) {
    switch (value.toLowerCase()) {
      case 'disable':
        return IPv6Mode.disable;
      case 'force':
        return IPv6Mode.force;
      default:
        return IPv6Mode.allow;
    }
  }

  /// Parse resolve scope from string
  ResolveScope _parseResolveScope(String value) {
    switch (value.toLowerCase()) {
      case 'machine':
        return ResolveScope.machine;
      case 'link':
        return ResolveScope.link;
      case 'organization':
        return ResolveScope.organization;
      case 'global':
        return ResolveScope.global;
      default:
        return ResolveScope.site;
    }
  }

  /// Parse a list of addresses from string
  List<String> _parseAddressList(String value) {
    if (value.isEmpty || value == '{}') return [];

    // Remove curly braces and split by comma
    final trimmed = value.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      final content = trimmed.substring(1, trimmed.length - 1).trim();
      if (content.isEmpty) return [];
      return content.split(',').map((e) => e.trim()).toList();
    }

    return [trimmed];
  }

  /// Convert the configuration to an INI format string
  String toIniString() {
    final buffer = StringBuffer();

    // Ports section
    buffer.writeln('[${ConfigSection.ports.name}]');
    buffer.writeln('MulticastPort = $multicastPort');
    buffer.writeln('BasePort = $basePort');
    buffer.writeln('PortRange = $portRange');
    buffer.writeln('IPv6 = ${ipv6.name}');
    buffer.writeln();

    // Multicast section
    buffer.writeln('[${ConfigSection.multicast.name}]');
    buffer.writeln('ResolveScope = ${resolveScope.name}');

    if (listenAddress != null) {
      buffer.writeln('ListenAddress = $listenAddress');
    } else {
      buffer.writeln('; ListenAddress = ""');
    }

    if (ipv6MulticastGroup != null) {
      buffer.writeln('IPv6MulticastGroup = $ipv6MulticastGroup');
    } else {
      buffer.writeln('; IPv6MulticastGroup = ""');
    }

    buffer.writeln(
      'MachineAddresses = ${_formatAddressList(machineAddresses)}',
    );
    buffer.writeln('LinkAddresses = ${_formatAddressList(linkAddresses)}');
    buffer.writeln('SiteAddresses = ${_formatAddressList(siteAddresses)}');
    buffer.writeln(
      'OrganizationAddresses = ${_formatAddressList(organizationAddresses)}',
    );
    buffer.writeln('GlobalAddresses = ${_formatAddressList(globalAddresses)}');
    buffer.writeln(
      'AddressesOverride = ${_formatAddressList(addressesOverride)}',
    );
    buffer.writeln('TTLOverride = $ttlOverride');
    buffer.writeln();

    // Lab section
    buffer.writeln('[${ConfigSection.lab.name}]');
    buffer.writeln('KnownPeers = ${_formatAddressList(knownPeers)}');
    buffer.writeln('SessionID = $sessionId');
    buffer.writeln();

    // Tuning section
    buffer.writeln('[${ConfigSection.tuning.name}]');
    buffer.writeln('WatchdogCheckInterval = $watchdogCheckInterval');
    buffer.writeln('WatchdogTimeThreshold = $watchdogTimeThreshold');
    buffer.writeln('MulticastMinRTT = $multicastMinRTT');
    buffer.writeln('MulticastMaxRTT = $multicastMaxRTT');
    buffer.writeln('UnicastMinRTT = $unicastMinRTT');
    buffer.writeln('UnicastMaxRTT = $unicastMaxRTT');
    buffer.writeln('ContinuousResolveInterval = $continuousResolveInterval');
    buffer.writeln('TimerResolution = $timerResolution');
    buffer.writeln('MaxCachedQueries = $maxCachedQueries');
    buffer.writeln('TimeUpdateInterval = $timeUpdateInterval');
    buffer.writeln('TimeUpdateMinProbes = $timeUpdateMinProbes');
    buffer.writeln('TimeProbeCount = $timeProbeCount');
    buffer.writeln('TimeProbeInterval = $timeProbeInterval');
    buffer.writeln('TimeProbeMaxRTT = $timeProbeMaxRTT');
    buffer.writeln('OutletBufferReserveMs = $outletBufferReserveMs');
    buffer.writeln('OutletBufferReserveSamples = $outletBufferReserveSamples');
    buffer.writeln('SendSocketBufferSize = $sendSocketBufferSize');
    buffer.writeln('InletBufferReserveMs = $inletBufferReserveMs');
    buffer.writeln('InletBufferReserveSamples = $inletBufferReserveSamples');
    buffer.writeln('ReceiveSocketBufferSize = $receiveSocketBufferSize');
    buffer.writeln('SmoothingHalftime = $smoothingHalftime');
    buffer.writeln(
      'ForceDefaultTimestamps = ${forceDefaultTimestamps.toString().toLowerCase()}',
    );
    buffer.writeln();

    // Log section
    buffer.writeln('[${ConfigSection.log.name}]');
    buffer.writeln('level = $logLevel');

    if (logFile != null) {
      buffer.writeln('file = $logFile');
    } else {
      buffer.writeln('; file = ');
    }

    return buffer.toString();
  }

  /// Format a list of addresses for INI output
  String _formatAddressList(List<String> addresses) {
    if (addresses.isEmpty) return '{}';
    if (addresses.length == 1 && !addresses[0].contains(',')) {
      // Check if it's already wrapped in curly braces
      final addr = addresses[0];
      if (addr.startsWith('{') && addr.endsWith('}')) {
        return addr;
      }
      return '{$addr}';
    }
    return '{${addresses.join(', ')}}';
  }
}

/// Helper extension to add firstWhereOrNull functionality
extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// Enum for config sections
enum ConfigSection { ports, multicast, lab, tuning, log }

/// IPv6 mode options
enum IPv6Mode {
  /// Only use IPv4
  disable,

  /// Use both IPv4 and IPv6
  allow,

  /// Only use IPv6
  force,
}

/// Multicast resolve scope options
enum ResolveScope {
  /// Local to the machine
  machine,

  /// Local to the subnet
  link,

  /// Local to the site as defined by local policy
  site,

  /// Local to the organization (e.g., campus)
  organization,

  /// Global scope
  global,
}

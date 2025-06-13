import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:android_multicast_lock/android_multicast_lock.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLockHeld = false;
  String _status = 'Ready';
  final _androidMulticastLockPlugin = AndroidMulticastLock();
  final _lockNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
  }

  Future<void> _checkLockStatus() async {
    try {
      final isHeld = await _androidMulticastLockPlugin.isMulticastLockHeld();
      setState(() {
        _isLockHeld = isHeld;
        _status = 'Lock status checked';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Failed to check lock status: ${e.message}';
      });
    }
  }

  Future<void> _acquireLock() async {
    try {
      final lockName = _lockNameController.text.trim().isEmpty 
          ? null 
          : _lockNameController.text.trim();
      await _androidMulticastLockPlugin.acquireMulticastLock(lockName: lockName);
      await _checkLockStatus();
      setState(() {
        _status = lockName != null 
            ? 'Lock acquired successfully with name: $lockName'
            : 'Lock acquired successfully with default name';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Failed to acquire lock: ${e.message}';
      });
    }
  }

  Future<void> _releaseLock() async {
    try {
      await _androidMulticastLockPlugin.releaseMulticastLock();
      await _checkLockStatus();
      setState(() {
        _status = 'Lock released successfully';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = 'Failed to release lock: ${e.message}';
      });
    }
  }

  @override
  void dispose() {
    _lockNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Android Multicast Lock Example'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Multicast Lock Status: ${_isLockHeld ? "HELD" : "NOT HELD"}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _isLockHeld ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Status: $_status',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: TextField(
                  controller: _lockNameController,
                  decoration: const InputDecoration(
                    labelText: 'Lock Name (optional)',
                    hintText: 'Leave empty for default name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _acquireLock,
                child: const Text('Acquire Multicast Lock'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _releaseLock,
                child: const Text('Release Multicast Lock'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _checkLockStatus,
                child: const Text('Check Lock Status'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

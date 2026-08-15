import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SleepDetectionService extends ChangeNotifier {
  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;

  // Configuration
  final Duration _inactivityThreshold = const Duration(minutes: 15);
  final double _movementThreshold = 0.5; // Sensitivity

  // State
  DateTime _lastMovementTime = DateTime.now();

  bool get isMonitoring => _isMonitoring;

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }

  Future<void> startMonitoring({required VoidCallback onSleepDetected}) async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _lastMovementTime = DateTime.now();
    notifyListeners();

    _startSensorMonitoring(onSleepDetected);
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    notifyListeners();
  }

  void _startSensorMonitoring(VoidCallback onSleepDetected) {
    // Listen to accelerometer events. Ignore errors: without a sensor the
    // detection simply never triggers.
    _accelerometerSubscription = userAccelerometerEventStream().listen(
      (event) {
        // Calculate magnitude of acceleration (ignoring gravity)
        double magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        if (magnitude > _movementThreshold) {
          _lastMovementTime = DateTime.now();
        }
      },
      onError: (Object _) {
        // Sensor unavailable: detection stays silent.
      },
    );

    // Check for inactivity periodically
    _monitoringTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final difference = now.difference(_lastMovementTime);

      if (difference >= _inactivityThreshold) {
        // User has been inactive for the threshold duration. Stop
        // monitoring even if the callback throws.
        try {
          onSleepDetected();
        } finally {
          stopMonitoring();
        }
      }
    });
  }
}

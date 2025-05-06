import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  FirebaseRemoteConfig? _remoteConfig;
  Timer? _keyRotationTimer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize Remote Config
      _remoteConfig = FirebaseRemoteConfig.instance;
      await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: Duration(
          seconds: int.parse(dotenv.env['REMOTE_CONFIG_FETCH_TIMEOUT'] ?? '60'),
        ),
        minimumFetchInterval: Duration(
          seconds: int.parse(
            dotenv.env['REMOTE_CONFIG_MINIMUM_FETCH_INTERVAL'] ?? '3600',
          ),
        ),
      ));

      // Set default values
      await _remoteConfig!.setDefaults({
        'imgbb_api_key': dotenv.env['IMGBB_API_KEY'] ?? '',
      });

      // Fetch and activate Remote Config
      await _remoteConfig!.fetchAndActivate();

      // Start key rotation timer
      _startKeyRotationTimer();

      _initialized = true;
      debugPrint('ConfigService initialized successfully');
    } catch (e) {
      debugPrint('Error initializing ConfigService: $e');
      // Continue with default values if there's an error
    }
  }

  void _startKeyRotationTimer() {
    final interval = Duration(
      seconds: int.parse(dotenv.env['KEY_ROTATION_INTERVAL'] ?? '86400'),
    );
    _keyRotationTimer = Timer.periodic(interval, (_) => _rotateKeys());
  }

  Future<void> _rotateKeys() async {
    try {
      // Fetch latest Remote Config
      await _remoteConfig!.fetchAndActivate();

      // Update environment variables with new values
      await dotenv.load(fileName: ".env", mergeWith: {
        'IMGBB_API_KEY': _remoteConfig!.getString('imgbb_api_key'),
      });

      debugPrint('Keys rotated successfully');
    } catch (e) {
      debugPrint('Error rotating keys: $e');
    }
  }

  String get imgbbApiKey => _remoteConfig?.getString('imgbb_api_key') ?? '';

  void dispose() {
    _keyRotationTimer?.cancel();
  }
}

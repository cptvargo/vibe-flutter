import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/jellyfin_config.dart';
import '../config/vibe_config.dart';

class ConnectionNotifier extends ChangeNotifier {
  bool _isConnected = false;
  bool _isDemoMode  = false;

  bool get isConnected => _isConnected;
  bool get isDemoMode  => _isDemoMode;

  // Called once at startup — reads Hive to see if user previously connected.
  Future<void> load() async {
    final box = await Hive.openBox<String>('jellyfin_cfg');
    _isConnected = (box.get('serverUrl') ?? '').isNotEmpty;
    // No notifyListeners — called before the app renders.
  }

  void enterDemo() {
    JellyfinConfig.serverUrl = VibeConfig.serverUrl;
    JellyfinConfig.apiKey    = VibeConfig.demoApiKey;
    JellyfinConfig.userId    = VibeConfig.demoUserId;
    JellyfinConfig.vibeLib   = '';
    JellyfinConfig.aiLib     = VibeConfig.aiLibrary;
    _isDemoMode  = true;
    _isConnected = true;
    notifyListeners();
  }

  void connect() {
    _isDemoMode  = false;
    _isConnected = true;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await JellyfinConfig.clear();
    _isDemoMode  = false;
    _isConnected = false;
    notifyListeners();
  }
}

final connectionNotifier = ConnectionNotifier();

final connectionProvider =
    ChangeNotifierProvider<ConnectionNotifier>((_) => connectionNotifier);

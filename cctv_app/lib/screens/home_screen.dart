import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _defaultRoomId = 'HOME-101';
  static const _defaultPin = '123456';

  final TextEditingController _roomIdController = TextEditingController(
    text: _defaultRoomId,
  );
  final TextEditingController _serverUrlController = TextEditingController(
    text: 'https://smart-cctv-signaling.onrender.com',
  );
  final TextEditingController _pinController = TextEditingController(
    text: _defaultPin,
  );
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_room_id', _defaultRoomId);
    await prefs.setString(
      'saved_server_url',
      'https://smart-cctv-signaling.onrender.com',
    );
    _pinController.text = _defaultPin;
    await prefs.setString('saved_room_pin', _defaultPin);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_room_id',
      _roomIdController.text.trim().toUpperCase(),
    );
    await prefs.setString('saved_server_url', _serverUrlController.text.trim());
    await prefs.setString('saved_room_pin', _pinController.text.trim());
  }

  void _openCameraMode() async {
    final roomId = _roomIdController.text.trim().toUpperCase();
    final serverUrl = _serverUrlController.text.trim();
    final pin = _pinController.text.trim();

    if (roomId.isEmpty ||
        serverUrl.isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Room ID and Server URL')),
      );
      return;
    }

    await _saveSettings();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CameraScreen(roomId: roomId, serverUrl: serverUrl, pin: pin),
      ),
    );
  }

  void _openViewerMode() async {
    final roomId = _roomIdController.text.trim().toUpperCase();
    final serverUrl = _serverUrlController.text.trim();
    final pin = _pinController.text.trim();

    if (roomId.isEmpty ||
        serverUrl.isEmpty ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Room ID, Server URL and 6-digit PIN'),
        ),
      );
      return;
    }

    await _saveSettings();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ViewerScreen(roomId: roomId, serverUrl: serverUrl, pin: pin),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Connection settings',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Secure cloud connection is configured for this device.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_done, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Cloud server connected',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Done', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Text(
              '◉ ',
              style: TextStyle(fontSize: 22, color: Color(0xFF60A5FA)),
            ),
            Text(
              'SecureCam',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Server Settings',
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your private live camera workspace',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect a camera device and view it securely from anywhere.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF102A43),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1D4E89)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, color: Color(0xFF60A5FA), size: 19),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Private room connection • Live video stays peer-to-peer',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Room ID Input Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONNECTION DETAILS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: _obscurePin,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      letterSpacing: 4,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: Colors.orangeAccent,
                      ),
                      hintText: '6-digit PIN',
                      hintStyle: const TextStyle(color: Colors.white24),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Show or hide PIN',
                            icon: Icon(
                              _obscurePin
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              setState(() => _obscurePin = !_obscurePin);
                            },
                          ),
                          IconButton(
                            tooltip: 'Copy PIN',
                            icon: const Icon(Icons.copy, color: Colors.white54),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _pinController.text),
                              );
                            },
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _roomIdController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(
                        Icons.tag,
                        color: Colors.blueAccent,
                      ),
                      hintText: 'HOME-101',
                      hintStyle: const TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use the same room and access PIN on both devices.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Mode Selection
            const Text(
              'Choose how you want to use this device',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),

            _RoleCard(
              title: 'Camera device',
              subtitle: 'Use this device as a live camera source. You can control the stream from a viewer.',
              badge: 'BROADCAST',
              badgeColor: Colors.blueAccent,
              icon: Icons.videocam,
              buttonText: 'Start camera device',
              buttonColor: const Color(0xFF2563EB),
              onTap: _openCameraMode,
            ),

            const SizedBox(height: 14),

            _RoleCard(
              title: 'Live viewer',
              subtitle: 'Join an active camera, watch the live feed and use remote controls.',
              badge: 'MONITOR',
              badgeColor: Colors.greenAccent,
              icon: Icons.visibility,
              buttonText: '＋ Join live camera',
              buttonColor: const Color(0xFF059669),
              onTap: _openViewerMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final String buttonText;
  final Color buttonColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.buttonText,
    required this.buttonColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onTap,
              child: Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

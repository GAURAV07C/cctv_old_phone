import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'camera_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _roomIdController = TextEditingController(text: 'HOME-101');
  final TextEditingController _serverUrlController = TextEditingController(text: 'http://192.168.1.7:3001');
  final TextEditingController _pinController = TextEditingController(text: '123456');

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoom = prefs.getString('saved_room_id');
    final savedServer = prefs.getString('saved_server_url');
    final savedPin = prefs.getString('saved_room_pin');

    if (savedRoom != null && savedRoom.isNotEmpty) {
      _roomIdController.text = savedRoom;
    }
    if (savedServer != null && savedServer.isNotEmpty) {
      _serverUrlController.text = savedServer;
    }
    if (savedPin != null && savedPin.isNotEmpty) _pinController.text = savedPin;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_room_id', _roomIdController.text.trim().toUpperCase());
    await prefs.setString('saved_server_url', _serverUrlController.text.trim());
    await prefs.setString('saved_room_pin', _pinController.text.trim());
  }

  void _openCameraMode() async {
    final roomId = _roomIdController.text.trim().toUpperCase();
    final serverUrl = _serverUrlController.text.trim();
    final pin = _pinController.text.trim();

    if (roomId.isEmpty || serverUrl.isEmpty || !RegExp(r'^\d{6}$').hasMatch(pin)) {
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
        builder: (_) => CameraScreen(roomId: roomId, serverUrl: serverUrl, pin: pin),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Signaling Server Settings', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Signaling Server URL (Local IP or Cloud URL):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverUrlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                hintText: 'e.g. http://192.168.1.5:3000',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
            onPressed: () {
              _saveSettings();
              Navigator.pop(ctx);
            },
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
            Text('📹 ', style: TextStyle(fontSize: 22)),
            Text(
              'Smart CCTV',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
              'Turn your old phone into a secure, low-latency CCTV camera.',
              style: TextStyle(color: Colors.white60, fontSize: 15),
            ),
            const SizedBox(height: 28),

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
                    'CAMERA ROOM ID / PIN',
                    style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4),
                    decoration: InputDecoration(
                      counterText: '', filled: true, fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(Icons.lock, color: Colors.orangeAccent),
                      hintText: '6-digit PIN', hintStyle: const TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _roomIdController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      prefixIcon: const Icon(Icons.tag, color: Colors.blueAccent),
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
                    'Both Camera and Viewer must use this same ID to connect.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Mode Selection
            const Text(
              'Select Device Role',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),

            // Option 1: Old Phone (Camera Mode)
            _RoleCard(
              title: 'Camera Mode',
              subtitle: 'Select this on your OLD phone.\nIncludes Screen-Off Stealth Mode & Battery Saver.',
              badge: 'OLD PHONE',
              badgeColor: Colors.blueAccent,
              icon: Icons.videocam,
              buttonText: 'Start as Camera',
              buttonColor: const Color(0xFF2563EB),
              onTap: _openCameraMode,
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
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                  style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onTap,
              child: Text(
                buttonText,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

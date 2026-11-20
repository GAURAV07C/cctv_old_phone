import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

class CameraScreen extends StatefulWidget {
  final String roomId;
  final String serverUrl;

  const CameraScreen({
    super.key,
    required this.roomId,
    required this.serverUrl,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late SignalingService _signalingService;
  late WebRTCService _webrtcService;

  bool _isConnected = false;
  int _activeViewers = 0;
  bool _isStealthMode = false;
  String _currentTime = '';
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    // Keep device awake while camera is operating
    await WakelockPlus.enable();

    // Request permissions
    await [Permission.camera, Permission.microphone].request();

    _signalingService = SignalingService(serverUrl: widget.serverUrl);
    _webrtcService = WebRTCService(signalingService: _signalingService);

    await _webrtcService.initRenderers();
    await _webrtcService.startLocalCamera();

    _setupSignalingCallbacks();
    _signalingService.connect();

    _startClock();
  }

  void _startClock() {
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  void _updateClock() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    }
  }

  void _setupSignalingCallbacks() {
    _signalingService.onConnectionChange = (connected) {
      if (mounted) {
        setState(() => _isConnected = connected);
        if (connected) {
          _signalingService.registerCamera(widget.roomId);
        }
      }
    };

    _signalingService.onNewViewer = (viewerSocketId) async {
      if (mounted) {
        setState(() => _activeViewers++);
      }
      await _webrtcService.handleNewViewer(viewerSocketId);
    };

    _signalingService.onViewerLeft = (viewerSocketId) {
      if (mounted) {
        setState(() => _activeViewers = (_activeViewers > 0) ? _activeViewers - 1 : 0);
      }
      _webrtcService.removeViewer(viewerSocketId);
    };

    _signalingService.onAnswer = (sdp, viewerSocketId) {
      _webrtcService.handleAnswerFromViewer(sdp, viewerSocketId);
    };

    _signalingService.onIceCandidate = (candidate, viewerSocketId) {
      _webrtcService.handleViewerIceCandidate(candidate, viewerSocketId);
    };

    _signalingService.onRemoteCommand = (command, value) {
      debugPrint('[Camera Screen] Received remote command: $command');
      if (command == 'toggle_flash') {
        _webrtcService.toggleTorch();
      } else if (command == 'switch_camera') {
        _webrtcService.switchCamera();
      }
    };
  }

  void _toggleStealthMode() {
    setState(() {
      _isStealthMode = !_isStealthMode;
    });

    if (_isStealthMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WakelockPlus.disable();
    _webrtcService.dispose();
    _signalingService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isStealthMode) {
      return GestureDetector(
        onDoubleTap: _toggleStealthMode,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentTime,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.12),
                    fontSize: 32,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Double tap anywhere to exit stealth mode',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.08),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CCTV Camera Mode',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Online: Room ${widget.roomId}' : 'Connecting...',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch Camera',
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () => _webrtcService.switchCamera(),
          ),
          IconButton(
            tooltip: 'Toggle Torch',
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _webrtcService.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Camera Preview
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RTCVideoView(
                  _webrtcService.localRenderer,
                  mirror: _webrtcService.isFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
                // Overlay Badges
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.visibility, color: Colors.lightBlueAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '$_activeViewers Viewer${_activeViewers == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'REC / LIVE',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Control Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Camera Room ID',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          Text(
                            widget.roomId,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Battery Saver ON',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Stealth / Black Screen Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.visibility_off, color: Colors.white),
                      label: const Text(
                        'Turn Screen OFF (Stealth Mode)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: _toggleStealthMode,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Stealth mode turns display black to save battery & look turned off.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

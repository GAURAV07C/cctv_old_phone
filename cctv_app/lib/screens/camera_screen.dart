import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';

class CameraScreen extends StatefulWidget {
  final String roomId;
  final String serverUrl;
  final String pin;

  const CameraScreen({
    super.key,
    required this.roomId,
    required this.serverUrl,
    required this.pin,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late SignalingService _signalingService;
  late WebRTCService _webrtcService;

  bool _isConnected = false;
  int _activeViewers = 0;
  final Set<String> _activeViewerIds = <String>{};
  bool _isStealthMode = false;
  bool _isCameraEnabled = true;
  Future<void>? _cameraStartFuture;
  String _currentTime = '';
  Timer? _clockTimer;
  Timer? _statusTimer;
  int _batteryLevel = -1;
  BatteryState _batteryState = BatteryState.unknown;
  static const MethodChannel _serviceChannel = MethodChannel('com.cctv/foreground_service');

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    // Keep device awake while camera is operating
    await WakelockPlus.enable();

    // Request permissions (Camera, Mic, Notification, Ignore Battery Optimizations)
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
    ].request();

    // Start Native Android Foreground Service (Survives Recent Apps Swipe)
    try {
      await _serviceChannel.invokeMethod('startService', {'roomId': widget.roomId});
    } catch (e) {
      debugPrint('[Service] Start error: $e');
    }

    _signalingService = SignalingService(serverUrl: widget.serverUrl);
    _webrtcService = WebRTCService(signalingService: _signalingService);

    await _webrtcService.initRenderers();
    _setupSignalingCallbacks();
    await _signalingService.connect();

    _startClock();
    _startDeviceStatusMonitor();
  }

  void _startDeviceStatusMonitor() {
    final battery = Battery();
    Future<void> update() async {
      try {
        final level = await battery.batteryLevel;
        final state = await battery.batteryState;
        if (!mounted) return;
        setState(() { _batteryLevel = level; _batteryState = state; });
        if (level <= 15 && state != BatteryState.charging) {
          NotificationService.instance.showStatus('Low battery', 'Camera phone battery is $level%');
        }
      } catch (_) {}
    }
    update();
    _statusTimer = Timer.periodic(const Duration(minutes: 5), (_) => update());
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
        NotificationService.instance.showStatus('CCTV server', connected ? 'Camera connected' : 'Disconnected; reconnecting');
        if (connected) {
          _signalingService.registerCamera(widget.roomId, widget.pin);
        }
      }
    };

    _signalingService.onNewViewer = (viewerSocketId) async {
      // Signaling can repeat a join after reconnect; count each socket only once.
      if (!_activeViewerIds.add(viewerSocketId)) {
        return;
      }
      // Demand-based battery optimization: capture only while a viewer exists.
      if (_webrtcService.localStream == null) {
        _cameraStartFuture ??= _webrtcService.startLocalCamera();
        await _cameraStartFuture;
        _cameraStartFuture = null;
        NotificationService.instance.showStatus('Stream started', 'Camera and microphone are active');
      }
      if (mounted) {
        setState(() => _activeViewers = _activeViewerIds.length);
      }
      NotificationService.instance.showStatus('Viewer connected', '$_activeViewers viewer connected');
      await _webrtcService.handleNewViewer(viewerSocketId);
    };

    _signalingService.onViewerLeft = (viewerSocketId) {
      _activeViewerIds.remove(viewerSocketId);
      if (mounted) {
        setState(() => _activeViewers = _activeViewerIds.length);
      }
      NotificationService.instance.showStatus('Viewer disconnected', '$_activeViewers viewers connected');
      _webrtcService.removeViewer(viewerSocketId);
      if (_activeViewers == 0) {
        _webrtcService.stopLocalCamera();
        NotificationService.instance.showStatus('Stream stopped', 'No viewers connected; camera paused');
      }
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
      } else if (command == 'set_camera_enabled') {
        final enabled = value != false;
        _webrtcService.setCameraEnabled(enabled);
        if (mounted) setState(() => _isCameraEnabled = enabled);
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
    _statusTimer?.cancel();
    WakelockPlus.disable();
    _webrtcService.dispose();
    _signalingService.disconnect();
    try {
      _serviceChannel.invokeMethod('stopService');
    } catch (_) {}
    super.dispose();
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('CCTV Camera Active', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to keep streaming in the background or stop the camera completely?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop(); // Actually pop and trigger dispose()
            },
            child: const Text('Stop & Exit', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            onPressed: () {
              Navigator.pop(ctx);
              _serviceChannel.invokeMethod('moveToBackground');
            },
            child: const Text('Stream in Background', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_isStealthMode) {
      content = GestureDetector(
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
    } else {
      content = Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _showExitDialog,
          ),
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
              tooltip: 'Minimize / Run in Background',
              icon: const Icon(Icons.download_for_offline_outlined, color: Colors.lightBlueAccent),
              onPressed: () {
                _serviceChannel.invokeMethod('moveToBackground');
              },
            ),
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
                        child: Text(
                          _isCameraEnabled ? 'REC / LIVE' : 'CAMERA PAUSED',
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
                        child: Text(
                          _batteryLevel >= 0
                              ? 'Battery $_batteryLevel%${_batteryState == BatteryState.charging ? ' • Charging' : ''}'
                              : 'Battery status loading',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showExitDialog();
        }
      },
      child: content,
    );
  }
}

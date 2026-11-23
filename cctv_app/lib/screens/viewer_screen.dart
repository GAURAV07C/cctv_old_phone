import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../services/notification_service.dart';

class ViewerScreen extends StatefulWidget {
  final String roomId;
  final String serverUrl;
  final String pin;

  const ViewerScreen({
    super.key,
    required this.roomId,
    required this.serverUrl,
    required this.pin,
  });

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late SignalingService _signalingService;
  late WebRTCService _webrtcService;

  bool _isServerConnected = false;
  bool _isCameraOnline = false;
  bool _isStreaming = false;
  bool _isMuted = false;
  bool _isCameraEnabled = true;

  @override
  void initState() {
    super.initState();
    _initViewer();
  }

  Future<void> _initViewer() async {
    _signalingService = SignalingService(serverUrl: widget.serverUrl);
    _webrtcService = WebRTCService(signalingService: _signalingService);

    await _webrtcService.initRenderers();

    _setupCallbacks();
    _signalingService.connect();
  }

  void _setupCallbacks() {
    _signalingService.onConnectionChange = (connected) {
      if (mounted) {
        setState(() => _isServerConnected = connected);
        NotificationService.instance.showStatus('CCTV connection', connected ? 'Connected to server' : 'Disconnected; reconnecting');
        if (connected) {
          _signalingService.joinViewer(widget.roomId, widget.pin);
        }
      }
    };

    _signalingService.onCameraStatus = (online) {
      if (mounted) {
        setState(() {
          _isCameraOnline = online;
          if (!online) {
            _isStreaming = false;
          }
        });
        NotificationService.instance.showStatus('Camera status', online ? 'Camera is online' : 'Camera went offline');
      }
    };

    _signalingService.onOffer = (sdp, cameraSocketId) async {
      await _webrtcService.handleCameraOffer(sdp, cameraSocketId);
      if (mounted) {
        setState(() => _isStreaming = true);
      }
      NotificationService.instance.showStatus('Stream started', 'Live camera stream is active');
    };

    _signalingService.onIceCandidate = (candidate, cameraSocketId) {
      _webrtcService.handleCameraIceCandidate(candidate);
    };
  }

  void _sendRemoteCmd(String command) {
    _signalingService.sendRemoteCommand(command, true);
  }

  void _setRemoteCameraEnabled(bool enabled) {
    setState(() => _isCameraEnabled = enabled);
    _signalingService.sendRemoteCommand('set_camera_enabled', enabled);
  }

  @override
  void dispose() {
    NotificationService.instance.showStatus('Stream stopped', 'Viewer session ended');
    _webrtcService.dispose();
    _signalingService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Viewing: ${widget.roomId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isStreaming ? Colors.greenAccent : (_isCameraOnline ? Colors.amberAccent : Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  !_isServerConnected
                      ? 'Connecting to Server...'
                      : (_isStreaming
                          ? 'Live Stream Active'
                          : (_isCameraOnline ? 'Camera Online (Connecting...)' : 'Camera Offline')),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Video Viewport
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.black,
                  child: _isStreaming
                      ? RTCVideoView(
                          _webrtcService.remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isCameraOnline ? Icons.sync : Icons.videocam_off,
                                size: 56,
                                color: Colors.white30,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isCameraOnline
                                    ? 'Requesting video feed from camera...'
                                    : 'Camera is currently offline.\nMake sure the app is open on your old phone.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white60, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                ),

                // Live Badge
                if (_isStreaming)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'LIVE P2P',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Remote Control Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Remote Camera Controls',
                    style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ControlButton(
                        icon: _isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                        label: _isCameraEnabled ? 'Camera Off' : 'Camera On',
                        onTap: () => _setRemoteCameraEnabled(!_isCameraEnabled),
                      ),
                      // Torch Toggle
                      _ControlButton(
                        icon: Icons.flash_on,
                        label: 'Flashlight',
                        onTap: () => _sendRemoteCmd('toggle_flash'),
                      ),
                      // Camera Switch
                      _ControlButton(
                        icon: Icons.flip_camera_ios,
                        label: 'Switch Cam',
                        onTap: () => _sendRemoteCmd('switch_camera'),
                      ),
                      // Audio Mute
                      _ControlButton(
                        icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        onTap: () {
                          setState(() {
                            _isMuted = !_isMuted;
                            _webrtcService.remoteRenderer.muted = _isMuted;
                          });
                        },
                      ),
                    ],
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

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF334155),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

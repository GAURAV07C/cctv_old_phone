import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SignalingService {
  WebSocket? _socket;
  final String serverUrl;

  // Callbacks
  Function(bool isConnected)? onConnectionChange;
  Function(String viewerSocketId)? onNewViewer;
  Function(String viewerSocketId)? onViewerLeft;
  Function(dynamic sdp, String senderSocketId)? onOffer;
  Function(dynamic sdp, String senderSocketId)? onAnswer;
  Function(dynamic candidate, String senderSocketId)? onIceCandidate;
  Function(String command, dynamic value)? onRemoteCommand;
  Function(bool cameraOnline)? onCameraStatus;

  SignalingService({required this.serverUrl});

  Future<void> connect() async {
    final urlsToTry = [serverUrl];
    if (!serverUrl.contains('127.0.0.1') && !serverUrl.contains('localhost')) {
      urlsToTry.add('ws://127.0.0.1:3000');
    }

    for (final rawUrl in urlsToTry) {
      try {
        String wsUrl = rawUrl.trim();
        if (wsUrl.startsWith('http://')) {
          wsUrl = wsUrl.replaceFirst('http://', 'ws://');
        } else if (wsUrl.startsWith('https://')) {
          wsUrl = wsUrl.replaceFirst('https://', 'wss://');
        } else if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
          wsUrl = 'ws://$wsUrl';
        }

        debugPrint('[Signaling] Attempting connection to $wsUrl');
        _socket = await WebSocket.connect(
          wsUrl,
          compression: CompressionOptions.compressionOff,
        ).timeout(const Duration(seconds: 4));

        debugPrint('[Signaling] Successfully connected to server: $wsUrl');
        onConnectionChange?.call(true);

        _socket?.listen(
          (data) {
            try {
              final msg = jsonDecode(data.toString());
              _handleMessage(msg);
            } catch (e) {
              debugPrint('[Signaling] JSON parse error: $e');
            }
          },
          onDone: () {
            debugPrint('[Signaling] Connection closed');
            onConnectionChange?.call(false);
          },
          onError: (err) {
            debugPrint('[Signaling] Socket error: $err');
            onConnectionChange?.call(false);
          },
        );
        return; // Success!
      } catch (e) {
        debugPrint('[Signaling] Connect failed for $rawUrl: $e');
      }
    }

    onConnectionChange?.call(false);
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'];

    switch (type) {
      case 'new_viewer':
        if (msg['viewerSocketId'] != null) {
          onNewViewer?.call(msg['viewerSocketId']);
        }
        break;
      case 'viewer_left':
        if (msg['viewerSocketId'] != null) {
          onViewerLeft?.call(msg['viewerSocketId']);
        }
        break;
      case 'camera_status':
        if (msg['online'] != null) {
          onCameraStatus?.call(msg['online'] == true);
        }
        break;
      case 'viewer_joined':
        if (msg['cameraOnline'] != null) {
          onCameraStatus?.call(msg['cameraOnline'] == true);
        }
        break;
      case 'offer':
        onOffer?.call(msg['sdp'], msg['senderSocketId'] ?? '');
        break;
      case 'answer':
        onAnswer?.call(msg['sdp'], msg['senderSocketId'] ?? '');
        break;
      case 'ice_candidate':
        onIceCandidate?.call(msg['candidate'], msg['senderSocketId'] ?? '');
        break;
      case 'execute_command':
        onRemoteCommand?.call(msg['command'], msg['value']);
        break;
    }
  }

  void _send(Map<String, dynamic> data) {
    if (_socket != null && _socket?.readyState == WebSocket.open) {
      _socket?.add(jsonEncode(data));
    }
  }

  void registerCamera(String roomId, String pin) {
    _send({'type': 'register_camera', 'roomId': roomId, 'pin': pin});
  }

  void joinViewer(String roomId, String pin) {
    _send({'type': 'join_viewer', 'roomId': roomId, 'pin': pin});
  }

  void sendOffer(String targetSocketId, dynamic sdp) {
    _send({
      'type': 'offer',
      'targetSocketId': targetSocketId,
      'sdp': sdp,
    });
  }

  void sendAnswer(String targetSocketId, dynamic sdp) {
    _send({
      'type': 'answer',
      'targetSocketId': targetSocketId,
      'sdp': sdp,
    });
  }

  void sendIceCandidate(String targetSocketId, dynamic candidate) {
    _send({
      'type': 'ice_candidate',
      'targetSocketId': targetSocketId,
      'candidate': candidate,
    });
  }

  void sendRemoteCommand(String command, dynamic value) {
    _send({
      'type': 'remote_command',
      'command': command,
      'value': value,
    });
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
  }
}

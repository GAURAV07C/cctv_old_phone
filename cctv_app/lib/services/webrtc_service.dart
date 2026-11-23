import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_service.dart';

class WebRTCService {
  final SignalingService signalingService;

  MediaStream? localStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // For Camera: map of viewerSocketId -> RTCPeerConnection
  final Map<String, RTCPeerConnection> _peerConnections = {};

  // For Viewer: single peer connection to camera
  RTCPeerConnection? _viewerPeerConnection;

  bool isFrontCamera = false;
  bool isTorchOn = false;
  bool isCameraEnabled = true;

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turn:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  WebRTCService({required this.signalingService});

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  // ================= CAMERA MODE METHODS =================

  Future<void> startLocalCamera() async {
    if (localStream != null) return;
    // Battery-optimized constraints: 720p, 20fps
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'idealWidth': '1280',
          'idealHeight': '720',
          'minFrameRate': '15',
          'maxFrameRate': '20',
        },
        'facingMode': isFrontCamera ? 'user' : 'environment',
        'optional': [],
      },
    };

    try {
      localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = localStream;
    } catch (e) {
      debugPrint('[WebRTC] Camera start error: $e');
    }
  }

  Future<void> stopLocalCamera() async {
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await localStream?.dispose();
    localStream = null;
    localRenderer.srcObject = null;
    isCameraEnabled = true;
  }

  Future<void> handleNewViewer(String viewerSocketId) async {
    debugPrint('[WebRTC Camera] Connecting to viewer: $viewerSocketId');

    if (localStream == null) {
      await startLocalCamera();
    }
    if (localStream == null) {
      debugPrint(
        '[WebRTC Camera] Cannot create offer: local camera unavailable',
      );
      return;
    }

    final pc = await createPeerConnection(_iceConfiguration);
    _peerConnections[viewerSocketId] = pc;

    // Add local tracks to peer connection
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        await pc.addTrack(track, localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      signalingService.sendIceCandidate(viewerSocketId, candidate.toMap());
    };

    pc.onConnectionState = (state) {
      debugPrint(
        '[WebRTC Camera] Viewer $viewerSocketId connection state: $state',
      );
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        removeViewer(viewerSocketId);
      }
    };

    // Create SDP Offer
    final offer = await pc.createOffer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });
    await pc.setLocalDescription(offer);

    signalingService.sendOffer(viewerSocketId, offer.toMap());
    debugPrint('[WebRTC Camera] Offer sent to viewer: $viewerSocketId');
  }

  Future<void> handleAnswerFromViewer(
    dynamic sdp,
    String viewerSocketId,
  ) async {
    final pc = _peerConnections[viewerSocketId];
    if (pc != null) {
      final answer = RTCSessionDescription(sdp['sdp'], sdp['type']);
      await pc.setRemoteDescription(answer);
    }
  }

  Future<void> handleViewerIceCandidate(
    dynamic candidateData,
    String viewerSocketId,
  ) async {
    final pc = _peerConnections[viewerSocketId];
    if (pc != null && candidateData != null) {
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );
      await pc.addCandidate(candidate);
    }
  }

  void removeViewer(String viewerSocketId) {
    final pc = _peerConnections.remove(viewerSocketId);
    pc?.close();
    pc?.dispose();
    debugPrint('[WebRTC Camera] Viewer removed: $viewerSocketId');
  }

  Future<void> switchCamera() async {
    if (localStream != null) {
      final videoTrack = localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
        isFrontCamera = !isFrontCamera;
      }
    }
  }

  Future<void> toggleTorch() async {
    if (localStream != null) {
      final videoTrack = localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        try {
          isTorchOn = !isTorchOn;
          final hasTorch = await videoTrack.hasTorch().catchError((_) => false);
          if (hasTorch) {
            await videoTrack.setTorch(isTorchOn).catchError((_) {});
          }
        } catch (e) {
          debugPrint('[WebRTC] Torch toggle handled: $e');
        }
      }
    }
  }

  /// Turns the camera video track on/off without destroying the WebRTC peer
  /// connections. This lets a viewer remotely pause/resume video instantly.
  Future<void> setCameraEnabled(bool enabled) async {
    isCameraEnabled = enabled;
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  // ================= VIEWER MODE METHODS =================

  Future<void> handleCameraOffer(dynamic sdp, String cameraSocketId) async {
    _viewerPeerConnection = await createPeerConnection(_iceConfiguration);

    _viewerPeerConnection!.onTrack = (event) {
      debugPrint('[WebRTC Viewer] Track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    _viewerPeerConnection!.onIceCandidate = (candidate) {
      signalingService.sendIceCandidate(cameraSocketId, candidate.toMap());
    };

    final offer = RTCSessionDescription(sdp['sdp'], sdp['type']);
    await _viewerPeerConnection!.setRemoteDescription(offer);

    final answer = await _viewerPeerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });
    await _viewerPeerConnection!.setLocalDescription(answer);

    signalingService.sendAnswer(cameraSocketId, answer.toMap());
  }

  Future<void> handleCameraIceCandidate(dynamic candidateData) async {
    if (_viewerPeerConnection != null && candidateData != null) {
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );
      await _viewerPeerConnection!.addCandidate(candidate);
    }
  }

  void dispose() {
    for (var pc in _peerConnections.values) {
      pc.close();
      pc.dispose();
    }
    _peerConnections.clear();

    _viewerPeerConnection?.close();
    _viewerPeerConnection?.dispose();

    localStream?.dispose();
    localRenderer.dispose();
    remoteRenderer.dispose();
  }
}

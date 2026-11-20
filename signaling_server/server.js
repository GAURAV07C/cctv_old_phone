const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// Map to store active rooms: roomId -> { cameraSocketId, viewerSocketIds: Set }
const rooms = new Map();

io.on('connection', (socket) => {
  console.log(`[Socket Connected] ID: ${socket.id}`);

  // Register as Camera
  socket.on('register_camera', ({ roomId }) => {
    roomId = roomId.toUpperCase().trim();
    socket.join(roomId);
    socket.data.role = 'camera';
    socket.data.roomId = roomId;

    if (!rooms.has(roomId)) {
      rooms.set(roomId, { cameraSocketId: socket.id, viewerSocketIds: new Set() });
    } else {
      rooms.get(roomId).cameraSocketId = socket.id;
    }

    console.log(`[Camera Registered] Room: ${roomId}, Socket: ${socket.id}`);
    socket.emit('camera_registered', { roomId, success: true });

    // Notify any existing viewers in this room
    const room = rooms.get(roomId);
    if (room && room.viewerSocketIds.size > 0) {
      socket.emit('viewers_waiting', { count: room.viewerSocketIds.size });
      io.to(roomId).emit('camera_status', { online: true, roomId });
    }
  });

  // Register as Viewer
  socket.on('join_viewer', ({ roomId }) => {
    roomId = roomId.toUpperCase().trim();
    socket.join(roomId);
    socket.data.role = 'viewer';
    socket.data.roomId = roomId;

    if (!rooms.has(roomId)) {
      rooms.set(roomId, { cameraSocketId: null, viewerSocketIds: new Set([socket.id]) });
    } else {
      rooms.get(roomId).viewerSocketIds.add(socket.id);
    }

    const room = rooms.get(roomId);
    const cameraOnline = room.cameraSocketId !== null;

    console.log(`[Viewer Joined] Room: ${roomId}, Socket: ${socket.id}, Camera Online: ${cameraOnline}`);
    socket.emit('viewer_joined', { roomId, cameraOnline });

    if (cameraOnline) {
      // Notify camera that a new viewer wants a stream
      io.to(room.cameraSocketId).emit('new_viewer', { viewerSocketId: socket.id });
    }
  });

  // WebRTC Signaling: Offer (from Camera or Viewer)
  socket.on('offer', ({ targetSocketId, sdp }) => {
    console.log(`[Relay Offer] from ${socket.id} to ${targetSocketId}`);
    io.to(targetSocketId).emit('offer', {
      senderSocketId: socket.id,
      sdp
    });
  });

  // WebRTC Signaling: Answer
  socket.on('answer', ({ targetSocketId, sdp }) => {
    console.log(`[Relay Answer] from ${socket.id} to ${targetSocketId}`);
    io.to(targetSocketId).emit('answer', {
      senderSocketId: socket.id,
      sdp
    });
  });

  // WebRTC Signaling: ICE Candidate
  socket.on('ice_candidate', ({ targetSocketId, candidate }) => {
    io.to(targetSocketId).emit('ice_candidate', {
      senderSocketId: socket.id,
      candidate
    });
  });

  // Remote Control Commands (e.g. toggle flashlight, switch front/back camera)
  socket.on('remote_command', ({ command, value }) => {
    const roomId = socket.data.roomId;
    if (roomId && rooms.has(roomId)) {
      const cameraSocketId = rooms.get(roomId).cameraSocketId;
      if (cameraSocketId) {
        console.log(`[Remote Command] ${command} sent to camera in room ${roomId}`);
        io.to(cameraSocketId).emit('execute_command', { command, value });
      }
    }
  });

  // Disconnect handling
  socket.on('disconnect', () => {
    console.log(`[Socket Disconnected] ID: ${socket.id}`);
    const roomId = socket.data.roomId;
    if (roomId && rooms.has(roomId)) {
      const room = rooms.get(roomId);
      if (socket.data.role === 'camera') {
        room.cameraSocketId = null;
        io.to(roomId).emit('camera_status', { online: false, roomId });
        console.log(`[Camera Offline] Room: ${roomId}`);
      } else if (socket.data.role === 'viewer') {
        room.viewerSocketIds.delete(socket.id);
        if (room.cameraSocketId) {
          io.to(room.cameraSocketId).emit('viewer_left', { viewerSocketId: socket.id });
        }
      }

      if (!room.cameraSocketId && room.viewerSocketIds.size === 0) {
        rooms.delete(roomId);
      }
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`===============================================`);
  console.log(` CCTV WebRTC Signaling Server Running!`);
  console.log(` Local URL: http://localhost:${PORT}`);
  console.log(` Network URL: http://<your-ip>:${PORT}`);
  console.log(`===============================================`);
});

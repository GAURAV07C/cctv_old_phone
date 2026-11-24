const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

// Room registry: roomId -> { camera, viewers: Map }
const rooms = new Map();
let socketIdCounter = 1;

class WSConnection {
  constructor(socket) {
    this.socket = socket;
    this.id = 'sock_' + (socketIdCounter++);
    this.role = null;
    this.roomId = null;
    this.isAlive = true;
    this.buffer = Buffer.alloc(0);
    this.fragmentedOpcode = null;
    this.fragmentedPayload = Buffer.alloc(0);

    socket.on('data', (chunk) => this._handleChunk(chunk));
    socket.on('close', () => this._handleClose());
    socket.on('error', (err) => {
      console.error(`[Socket Error] ${this.id}:`, err.message);
      this._handleClose();
    });
  }

  send(data) {
    if (!this.socket.writable) return;
    const jsonStr = typeof data === 'string' ? data : JSON.stringify(data);
    const payload = Buffer.from(jsonStr, 'utf8');
    const length = payload.length;

    let header;
    if (length < 126) {
      header = Buffer.alloc(2);
      header[0] = 0x81; // FIN + text frame
      header[1] = length;
    } else if (length < 65536) {
      header = Buffer.alloc(4);
      header[0] = 0x81;
      header[1] = 126;
      header.writeUInt16BE(length, 2);
    } else {
      header = Buffer.alloc(10);
      header[0] = 0x81;
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(length), 2);
    }

    try {
      this.socket.write(Buffer.concat([header, payload]));
    } catch (e) {
      console.error('[Send Error]', e.message);
    }
  }

  _handleChunk(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (this.buffer.length >= 2) {
      const b0 = this.buffer[0];
      const opcode = b0 & 0x0f;
      const isFinal = (b0 & 0x80) !== 0;

      const b1 = this.buffer[1];
      const isMasked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let offset = 2;

      if (len === 126) {
        if (this.buffer.length < 4) return;
        len = this.buffer.readUInt16BE(2);
        offset = 4;
      } else if (len === 127) {
        if (this.buffer.length < 10) return;
        len = Number(this.buffer.readBigUInt64BE(2));
        offset = 10;
      }

      const maskLen = isMasked ? 4 : 0;
      if (this.buffer.length < offset + maskLen + len) {
        // Incomplete frame, wait for next TCP chunk
        return;
      }

      const mask = isMasked ? this.buffer.slice(offset, offset + 4) : null;
      offset += maskLen;

      const payload = Buffer.alloc(len);
      if (isMasked) {
        for (let i = 0; i < len; i++) {
          payload[i] = this.buffer[offset + i] ^ mask[i % 4];
        }
      } else {
        this.buffer.copy(payload, 0, offset, offset + len);
      }

      // Remove consumed frame from buffer
      this.buffer = this.buffer.slice(offset + len);

      if (opcode === 8) { // Close
        this.socket.end();
        this._handleClose();
        return;
      }
      if (opcode === 9) { // Ping
        const pong = Buffer.from([0x8a, 0x00]);
        this.socket.write(pong);
        continue;
      }

      // WebSocket messages can be split into multiple frames by proxies or
      // clients. Accumulate text fragments before parsing JSON; otherwise a
      // large SDP offer can be parsed halfway through at a boundary such as
      // 4096 bytes.
      if (opcode === 1 && !isFinal) {
        this.fragmentedOpcode = 1;
        this.fragmentedPayload = Buffer.concat([this.fragmentedPayload, payload]);
        continue;
      }
      if (opcode === 0 && this.fragmentedOpcode === 1) {
        this.fragmentedPayload = Buffer.concat([this.fragmentedPayload, payload]);
        if (!isFinal) continue;
        const completePayload = this.fragmentedPayload;
        this.fragmentedOpcode = null;
        this.fragmentedPayload = Buffer.alloc(0);
        try {
          const message = JSON.parse(completePayload.toString('utf8'));
          handleClientMessage(this, message);
        } catch (e) {
          console.error('[JSON Parse Error]', e.message);
        }
        continue;
      }
      if (opcode === 1) { // Text frame
        try {
          const str = payload.toString('utf8');
          const message = JSON.parse(str);
          handleClientMessage(this, message);
        } catch (e) {
          console.error('[JSON Parse Error]', e.message);
        }
      }
    }
  }

  _handleClose() {
    if (!this.isAlive) return;
    this.isAlive = false;
    handleClientDisconnect(this);
  }
}

// HTTP Server
const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');

  let filePath = path.join(__dirname, 'public', req.url === '/' ? 'index.html' : req.url);
  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('404 Not Found');
    } else {
      const ext = path.extname(filePath);
      let contentType = 'text/html';
      if (ext === '.js') contentType = 'text/javascript';
      if (ext === '.css') contentType = 'text/css';
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    }
  });
});

// Upgrade to WebSocket
server.on('upgrade', (req, socket) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) {
    socket.destroy();
    return;
  }

  const hash = crypto.createHash('sha1').update(key + GUID).digest('base64');
  const responseHeaders = [
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: websocket',
    'Connection: Upgrade',
    `Sec-WebSocket-Accept: ${hash}`
  ];

  socket.write(responseHeaders.join('\r\n') + '\r\n\r\n');
  new WSConnection(socket);
});

// Routing & Signaling Logic
function handleClientMessage(client, msg) {
  const { type, roomId, pin, targetSocketId, sdp, candidate, command, value } = msg;
  const cleanRoomId = (roomId || client.roomId || '').toUpperCase().trim();

  switch (type) {
    case 'register_camera': {
      client.role = 'camera';
      client.roomId = cleanRoomId;

      if (!rooms.has(cleanRoomId)) {
        rooms.set(cleanRoomId, { camera: client, pin: String(pin || ''), viewers: new Map() });
      } else {
        rooms.get(cleanRoomId).camera = client;
        rooms.get(cleanRoomId).pin = String(pin || '');
      }

      console.log(`[Camera Registered] Room: ${cleanRoomId}, Client: ${client.id}`);
      client.send({ type: 'camera_registered', roomId: cleanRoomId, success: true });

      // Notify existing viewers
      const room = rooms.get(cleanRoomId);
      for (const viewer of room.viewers.values()) {
        viewer.send({ type: 'camera_status', online: true });
        client.send({ type: 'new_viewer', viewerSocketId: viewer.id });
      }
      break;
    }

    case 'join_viewer': {
      client.role = 'viewer';
      client.roomId = cleanRoomId;

      if (!rooms.has(cleanRoomId)) {
        rooms.set(cleanRoomId, { camera: null, pin: null, viewers: new Map() });
      }
      const room = rooms.get(cleanRoomId);
      if (!room.pin || String(pin || '') !== room.pin) {
        client.send({ type: 'auth_failed', reason: 'Invalid room PIN' });
        return;
      }
      room.viewers.set(client.id, client);

      const isCameraOnline = room.camera !== null;
      console.log(`[Viewer Joined] Room: ${cleanRoomId}, Client: ${client.id}, Camera Online: ${isCameraOnline}`);

      client.send({ type: 'viewer_joined', roomId: cleanRoomId, cameraOnline: isCameraOnline });

      if (isCameraOnline) {
        room.camera.send({ type: 'new_viewer', viewerSocketId: client.id });
      }
      break;
    }

    case 'offer': {
      const room = rooms.get(cleanRoomId);
      if (room) {
        const target = room.viewers.get(targetSocketId) || (room.camera && room.camera.id === targetSocketId ? room.camera : null);
        if (target) {
          console.log(`[Relay Offer] ${client.id} -> ${targetSocketId}`);
          target.send({ type: 'offer', senderSocketId: client.id, sdp });
        }
      }
      break;
    }

    case 'answer': {
      const room = rooms.get(cleanRoomId);
      if (room) {
        const target = room.viewers.get(targetSocketId) || (room.camera && room.camera.id === targetSocketId ? room.camera : null);
        if (target) {
          console.log(`[Relay Answer] ${client.id} -> ${targetSocketId}`);
          target.send({ type: 'answer', senderSocketId: client.id, sdp });
        }
      }
      break;
    }

    case 'ice_candidate': {
      const room = rooms.get(cleanRoomId);
      if (room) {
        const target = room.viewers.get(targetSocketId) || (room.camera && room.camera.id === targetSocketId ? room.camera : null);
        if (target) {
          console.log(`[Relay ICE] ${client.id} -> ${targetSocketId}`);
          target.send({ type: 'ice_candidate', senderSocketId: client.id, candidate });
        }
      }
      break;
    }

    case 'remote_command': {
      const room = rooms.get(cleanRoomId);
      if (room && room.camera) {
        console.log(`[Remote Command] ${command} sent to camera in room: ${cleanRoomId}`);
        room.camera.send({ type: 'execute_command', command, value });
      }
      break;
    }

    case 'request_offer': {
      const room = rooms.get(cleanRoomId);
      if (room && room.camera) {
        const viewerSocketId = targetSocketId || client.id;
        console.log(`[Request Offer] ${client.id} -> camera for viewer ${viewerSocketId}`);
        room.camera.send({ type: 'request_offer', viewerSocketId });
      }
      break;
    }
  }
}

function handleClientDisconnect(client) {
  console.log(`[Disconnected] Client: ${client.id}, Room: ${client.roomId}, Role: ${client.role}`);
  if (!client.roomId || !rooms.has(client.roomId)) return;

  const room = rooms.get(client.roomId);
  if (client.role === 'camera') {
    room.camera = null;
    for (const viewer of room.viewers.values()) {
      viewer.send({ type: 'camera_status', online: false });
    }
  } else if (client.role === 'viewer') {
    room.viewers.delete(client.id);
    if (room.camera) {
      room.camera.send({ type: 'viewer_left', viewerSocketId: client.id });
    }
  }

  if (!room.camera && room.viewers.size === 0) {
    rooms.delete(client.roomId);
  }
}

server.listen(PORT, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(` Standalone CCTV WebRTC Signaling Server Running!`);
  console.log(` Buffer Accumulation Enabled`);
  console.log(` Port: ${PORT}`);
  console.log(` Web Viewer: http://localhost:${PORT}`);
  console.log(`=======================================================`);
});

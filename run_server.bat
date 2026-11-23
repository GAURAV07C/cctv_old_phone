@echo off
title CCTV Signaling Server
echo =======================================================
echo  Starting Smart CCTV Signaling Server...
echo  Zero dependencies required!
echo =======================================================
set PORT=3001
node signaling_server\server_standalone.js
pause

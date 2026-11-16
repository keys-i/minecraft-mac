"use strict";

const video = document.querySelector("#game");
const start = document.querySelector("#start");
const connect = document.querySelector("#connect");
const message = document.querySelector("#message");
const bar = document.querySelector("#bar");
const state = document.querySelector("#state");
const stats = document.querySelector("#stats");
const capture = document.querySelector("#capture");
const fullscreen = document.querySelector("#fullscreen");

let peer;
let socket;
let resource;
let sequence = 0;
let pingAt = 0;
const latencies = [];
const timers = [];
const mouseButtons = [0, 2, 1, 3, 4];

const keys = {
  Escape: 1, Digit1: 2, Digit2: 3, Digit3: 4, Digit4: 5, Digit5: 6,
  Digit6: 7, Digit7: 8, Digit8: 9, Digit9: 10, Digit0: 11, Minus: 12,
  Equal: 13, Backspace: 14, Tab: 15, KeyQ: 16, KeyW: 17, KeyE: 18,
  KeyR: 19, KeyT: 20, KeyY: 21, KeyU: 22, KeyI: 23, KeyO: 24,
  KeyP: 25, BracketLeft: 26, BracketRight: 27, Enter: 28, ControlLeft: 29,
  KeyA: 30, KeyS: 31, KeyD: 32, KeyF: 33, KeyG: 34, KeyH: 35,
  KeyJ: 36, KeyK: 37, KeyL: 38, Semicolon: 39, Quote: 40,
  Backquote: 41, ShiftLeft: 42, Backslash: 43, KeyZ: 44, KeyX: 45,
  KeyC: 46, KeyV: 47, KeyB: 48, KeyN: 49, KeyM: 50, Comma: 51,
  Period: 52, Slash: 53, ShiftRight: 54, AltLeft: 56, Space: 57,
  CapsLock: 58, F1: 59, F2: 60, F3: 61, F4: 62, F5: 63, F6: 64,
  F7: 65, F8: 66, F9: 67, F10: 68, F11: 87, F12: 88,
  ControlRight: 97, AltRight: 100, Home: 102, ArrowUp: 103, PageUp: 104,
  ArrowLeft: 105, ArrowRight: 106, End: 107, ArrowDown: 108,
  PageDown: 109, Insert: 110, Delete: 111, Pause: 119, MetaLeft: 125,
  MetaRight: 126,
};

function ticket() {
  const value = new URLSearchParams(location.hash.slice(1)).get("ticket") || "";
  history.replaceState(null, "", location.pathname + location.search);
  return value;
}

const token = ticket();
if (token.length < 32) {
  connect.disabled = true;
  message.textContent = "Open the private session link supplied by your host";
}

function event(kind, flags = 0, code = 0, x = 0, y = 0) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  const bytes = new ArrayBuffer(24);
  const view = new DataView(bytes);
  view.setUint8(0, 1);
  view.setUint8(1, kind);
  view.setUint8(2, flags);
  view.setUint16(4, code, true);
  view.setInt32(8, x, true);
  view.setInt32(12, y, true);
  view.setUint32(16, ++sequence, true);
  view.setUint32(20, Math.floor(performance.now() * 1000), true);
  socket.send(bytes);
}

function waitIce(connection) {
  if (connection.iceGatheringState === "complete") return Promise.resolve();
  return new Promise((resolve) => {
    const changed = () => {
      if (connection.iceGatheringState === "complete") {
        connection.removeEventListener("icegatheringstatechange", changed);
        resolve();
      }
    };
    connection.addEventListener("icegatheringstatechange", changed);
  });
}

async function whep() {
  peer = new RTCPeerConnection({ bundlePolicy: "max-bundle" });
  peer.addTransceiver("video", { direction: "recvonly" });
  peer.addTransceiver("audio", { direction: "recvonly" });
  peer.addEventListener("track", ({ streams }) => { video.srcObject = streams[0]; });
  peer.addEventListener("connectionstatechange", () => {
    state.textContent = peer.connectionState;
    if (peer.connectionState === "failed") stop("The stream connection failed");
  });
  await peer.setLocalDescription(await peer.createOffer());
  await waitIce(peer);
  const response = await fetch("/minecraft/whep", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/sdp",
    },
    body: peer.localDescription.sdp,
  });
  if (!response.ok) throw new Error(`WebRTC returned ${response.status}`);
  const resourceHeader = response.headers.get("Location");
  if (!resourceHeader) throw new Error("WebRTC did not return a session location");
  const resourceUrl = new URL(resourceHeader, location.href);
  if (!resourceUrl.pathname.startsWith("/minecraft/")) {
    throw new Error("WebRTC returned an invalid session location");
  }
  resource = resourceUrl.pathname + resourceUrl.search;
  await peer.setRemoteDescription({ type: "answer", sdp: await response.text() });
}

function controls() {
  socket = new WebSocket(`wss://${location.host}/input`);
  socket.binaryType = "arraybuffer";
  return new Promise((resolve, reject) => {
    socket.addEventListener("open", () => {
      socket.send(token);
      resolve();
    }, { once: true });
    socket.addEventListener("error", () => reject(new Error("Input connection failed")), { once: true });
    socket.addEventListener("message", ({ data }) => {
      if (!(data instanceof ArrayBuffer) || data.byteLength !== 24) return;
      const view = new DataView(data);
      if (view.getUint8(1) !== 5) return;
      latencies.push(performance.now() - pingAt);
      if (latencies.length > 120) latencies.shift();
    });
    socket.addEventListener("close", () => {
      if (peer && peer.connectionState !== "closed") stop("Input connection closed");
    });
  });
}

async function begin() {
  connect.disabled = true;
  message.textContent = "Connecting to your private session";
  try {
    await Promise.all([whep(), controls()]);
    await video.play();
    start.hidden = true;
    bar.hidden = false;
    capture.hidden = false;
    state.textContent = "connected";
    timers.push(setInterval(ping, 1000));
    timers.push(setInterval(report, 1000));
  } catch (error) {
    stop(error.message);
  }
}

function stop(reason) {
  while (timers.length) clearInterval(timers.pop());
  if (resource) fetch(resource, {
    method: "DELETE",
    headers: { "Authorization": `Bearer ${token}` },
    keepalive: true,
  }).catch(() => {});
  resource = undefined;
  if (socket) socket.close();
  if (peer) peer.close();
  socket = undefined;
  peer = undefined;
  start.hidden = false;
  bar.hidden = true;
  capture.hidden = true;
  connect.disabled = token.length < 32;
  message.textContent = reason;
}

function ping() {
  pingAt = performance.now();
  event(5);
}

function percentile(values, fraction) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * fraction))];
}

async function report() {
  if (!peer) return;
  let frames = 0;
  let dropped = 0;
  let decode = 0;
  const values = await peer.getStats();
  values.forEach((entry) => {
    if (entry.type === "inbound-rtp" && entry.kind === "video") {
      frames = entry.framesPerSecond || 0;
      dropped = entry.framesDropped || 0;
      decode = entry.totalDecodeTime && entry.framesDecoded ? entry.totalDecodeTime / entry.framesDecoded * 1000 : 0;
    }
  });
  stats.textContent = `${frames.toFixed(0)} fps · input p50 ${percentile(latencies, 0.5).toFixed(1)} ms · p95 ${percentile(latencies, 0.95).toFixed(1)} ms · decode ${decode.toFixed(1)} ms · ${dropped} dropped`;
}

connect.addEventListener("click", begin);
fullscreen.addEventListener("click", () => document.documentElement.requestFullscreen());
video.addEventListener("click", () => video.requestPointerLock());
document.addEventListener("pointerlockchange", () => { capture.hidden = document.pointerLockElement === video; });

document.addEventListener("keydown", (input) => {
  const code = keys[input.code];
  if (!code || input.repeat) return;
  input.preventDefault();
  event(1, 1, code);
});

document.addEventListener("keyup", (input) => {
  const code = keys[input.code];
  if (!code) return;
  input.preventDefault();
  event(1, 0, code);
});

document.addEventListener("mousemove", (input) => {
  if (document.pointerLockElement === video) event(2, 0, 0, input.movementX, input.movementY);
});

document.addEventListener("mousedown", (input) => {
  if (document.pointerLockElement === video && input.button <= 4) event(3, 1, mouseButtons[input.button]);
});

document.addEventListener("mouseup", (input) => {
  if (document.pointerLockElement === video && input.button <= 4) event(3, 0, mouseButtons[input.button]);
});

document.addEventListener("wheel", (input) => {
  if (document.pointerLockElement !== video) return;
  input.preventDefault();
  event(4, 0, 0, 0, Math.sign(-input.deltaY));
}, { passive: false });

window.addEventListener("blur", () => event(6));
window.addEventListener("pagehide", () => stop("Session closed"));

const API_BASE = "https://TU_BACKEND_PUBLIC_URL_OR_LOCAL"; // <-- CAMBIAR
const API_KEY = "TU_API_KEY_SEGURA"; // <-- CAMBIAR

async function api(path, opts = {}) {
  const headers = opts.headers || {};
  if (opts.auth) headers["x-api-key"] = API_KEY;
  if (opts.body && !headers["Content-Type"]) headers["Content-Type"] = "application/json";
  const res = await fetch(API_BASE + path, {...opts, headers});
  return res.json();
}

// UI elements
const btnShiftToggle = document.getElementById("btnShiftToggle");
const btnMotorToggle = document.getElementById("btnMotorToggle");
const btnHistory = document.getElementById("btnHistory");
const btnBack = document.getElementById("btnBack");

// actions
btnShiftToggle.onclick = async () => {
  const active = document.getElementById("turnTitle").innerText !== "No hay turno activo";
  if (!active) {
    const name = prompt("Nombre del turno:", "Turno " + new Date().toLocaleString());
    await api("/api/shift/start", {method:"POST", body: JSON.stringify({name}), auth:true});
  } else {
    await api("/api/shift/end", {method:"POST", auth:true});
  }
  await refresh();
};

btnMotorToggle.onclick = async () => {
  // only allow if turno active
  const cur = await api("/api/shift/active");
  if (!cur.active) { alert("Activa un turno primero"); return; }
  const state = (document.getElementById("motorState").innerText === "ENCENDIDO");
  await api("/api/device_state", {method:"POST", body: JSON.stringify({motor_on: !state}), auth:true});
  await refresh();
};

btnHistory.onclick = async () => {
  document.querySelector('#historySection').style.display = 'block';
  document.querySelector('#turnoSection').style.display = 'none';
  document.querySelector('body').scrollTop = 0;
  const hist = await api("/api/shift/history");
  document.getElementById("history").innerText = JSON.stringify(hist, null, 2);
};

btnBack.onclick = () => {
  document.querySelector('#historySection').style.display = 'none';
  document.querySelector('#turnoSection').style.display = 'block';
};

async function refresh() {
  try {
    const ds = await api("/api/device_state");
    document.getElementById("motorState").innerText = ds.motor_on ? "ENCENDIDO" : "APAGADO";
    document.getElementById("turnLed").innerText = ds.turn_led_on ? "ENCENDIDO" : "APAGADO";
    document.getElementById("storageState").innerText = ds.box_full ? "Almacenamiento: LLENO" : "Almacenamiento: disponible";

    const cur = await api("/api/counts/current");
    if (cur.active) {
      document.getElementById("turnTitle").innerText = "Turno " + cur.shift_id;
      document.getElementById("totalCnt").innerText = cur.counts.total || 0;
      document.getElementById("smallCnt").innerText = cur.counts.small || 0;
      document.getElementById("medCnt").innerText = cur.counts.medium || 0;
      document.getElementById("largeCnt").innerText = cur.counts.large || 0;
      btnShiftToggle.innerText = "Acabar Turno";
      btnMotorToggle.innerText = ds.motor_on ? "Detener Cinta" : "Activar Cinta";
    } else {
      document.getElementById("turnTitle").innerText = "No hay turno activo";
      btnShiftToggle.innerText = "Activar Turno";
      btnMotorToggle.innerText = "Activar Cinta";
      document.getElementById("totalCnt").innerText = 0;
      document.getElementById("smallCnt").innerText = 0;
      document.getElementById("medCnt").innerText = 0;
      document.getElementById("largeCnt").innerText = 0;
    }
  } catch (e) {
    console.error(e);
  }
}

setInterval(refresh, 2000);
refresh();

const API_BASE = "https://iot-automatizacion-g9.onrender.com"; // cambiar si hace falta
const API_KEY = "patroclo";

async function post(path, body) {
  const res = await fetch(`${API_BASE}/api${path}`, {
    method: "POST",
    headers: {
      "Content-Type":"application/json",
      "x-api-key": API_KEY
    },
    body: JSON.stringify(body)
  });
  return res;
}

async function get(path) {
  const res = await fetch(`${API_BASE}/api${path}`, {
    headers: { "x-api-key": API_KEY }
  });
  return res;
}

async function toggleMotor() {
  // leer estado actual
  const st = await get('/device_state');
  let motor_on = false;
  if (st.status === 200) {
    const j = await st.json();
    motor_on = j.motor_on;
  }
  await post('/device_state', { motor_on: !motor_on });
  alert("Motor toggled");
}

async function toggleTurn() {
  // si no hay turno activo -> start
  const st = await get('/counts/current');
  const status = await get('/shift/history');
  // simple: pedimos start o end de forma manual
  const activeShift = await fetch(`${API_BASE}/api/shift/history`, { headers: {"x-api-key": API_KEY}}).then(r=>r.json()).then(list => list.find(s => s.end_at === null));
  if (!activeShift) {
    const name = prompt("Nombre del turno", `Turno ${new Date().toLocaleString()}`);
    await post('/shift/start', { name: name || undefined });
    alert("Turno iniciado");
  } else {
    await post('/shift/end', {});
    alert("Turno finalizado");
  }
}

async function getStatus() {
  try {
    const res = await get('/device_state');
    const counts = await get('/counts/current');
    let out = "";
    if (res.status === 200) {
      const j = await res.json();
      out += `Motor: ${j.motor_on}\nTurn LED: ${j.turn_led_on}\nBox full: ${j.box_full}\nUpdated: ${j.timestamp}\n\n`;
    } else out += "No device state\n\n";
    if (counts.status === 200) {
      const c = await counts.json();
      out += `Counts: ${JSON.stringify(c.counts, null, 2)}\n`;
    }
    document.getElementById("status").innerText = out;
  } catch (e) {
    document.getElementById("status").innerText = "Error: " + e.message;
  }
}

document.getElementById("btnMotor").onclick = toggleMotor;
document.getElementById("btnLed").onclick = toggleTurn;
document.getElementById("btnHistory").onclick = async () => {
  const res = await get('/shift/history');
  if (res.status === 200) {
    const list = await res.json();
    document.getElementById("status").innerText = JSON.stringify(list, null, 2);
  }
};

setInterval(getStatus, 3000);
getStatus();

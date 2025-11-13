const API_BASE = "https://iot-automatizacion-g9.onrender.com"; // URL Render del backend 
const API_KEY = "patroclo";

async function toggleMotor() {
  await fetch(`${API_BASE}/update`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": API_KEY,
    },
    body: JSON.stringify({ motor: true })
  });
  alert("Motor activado");
}

async function toggleLed() {
  await fetch(`${API_BASE}/update`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": API_KEY,
    },
    body: JSON.stringify({ turnLed: true })
  });
  alert("LED activado");
}

async function getStatus() {
  const res = await fetch(`${API_BASE}/latest`);
  const data = await res.json();
  document.getElementById("status").innerText = JSON.stringify(data, null, 2);
}

document.getElementById("btnMotor").onclick = toggleMotor;
document.getElementById("btnLed").onclick = toggleLed;

setInterval(getStatus, 5000);

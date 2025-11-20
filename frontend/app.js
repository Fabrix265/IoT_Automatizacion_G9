const API = "https://iot-automatizacion-g9.onrender.com";
const HEADERS = { "x-api-key": "patroclo", "Content-Type": "application/json" };

// --- Botones ---
const btnTurno = document.getElementById("btnTurno");
const btnMotor = document.getElementById("btnMotor");
const btnHistorial = document.getElementById("btnHistorial");

// --- Estado actual ---
async function cargarEstado() {
    const res = await fetch(`${API}/api/device_state`, { headers: HEADERS });
    const data = await res.json();

    const motorState = data.motor_on === true || data.motor_on === "true";
    const turnState = data.turn_led_on === true || data.turn_led_on === "true";
    const boxState = data.box_full === true || data.box_full === "true";
    
    // Actualizar estado visual
    actualizarEstadoVisual("motor_state", motorState);
    actualizarEstadoVisual("turn_state", turnState);
    actualizarEstadoVisual("box_state", boxState);
    
    // Actualizar timestamp
    const fecha = new Date(data.timestamp);
    document.getElementById("timestamp").textContent = fecha.toLocaleString('es-ES');
    
    // Actualizar botones
    btnTurno.textContent = turnState ? "Terminar Turno" : "Iniciar Turno";
    btnMotor.textContent = motorState ? "Desactivar Motor" : "Activar Motor";
}

// --- Función para actualizar estado visual ---
function actualizarEstadoVisual(elementId, estado) {
    const elemento = document.getElementById(elementId);
    elemento.textContent = estado ? "✓ Activo" : "✗ Inactivo";
    elemento.className = estado ? "estado-activo" : "estado-inactivo";
}

// --- Conteos ---
async function cargarConteos() {
    const res = await fetch(`${API}/api/counts/current`, { headers: HEADERS });
    const data = await res.json();

    document.getElementById("count_total").textContent = data.counts.total;
    document.getElementById("count_small").textContent = data.counts.small;
    document.getElementById("count_medium").textContent = data.counts.medium;
    document.getElementById("count_large").textContent = data.counts.large;
}

// --- Iniciar / terminar turno ---
btnTurno.addEventListener("click", async () => {
    const turnState = document.getElementById("turn_state").textContent.includes("Activo");

    if (!turnState) {
        const nombre = prompt("Nombre del turno:");
        if (!nombre) return;

        await fetch(`${API}/api/shift/start`, {
            method: "POST",
            headers: HEADERS,
            body: JSON.stringify({ name: nombre })
        });

    } else {
        await fetch(`${API}/api/shift/end`, {
            method: "POST",
            headers: HEADERS
        });
    }

    cargarEstado();
    cargarConteos();
});

// --- Motor encender/apagar ---
btnMotor.addEventListener("click", async () => {
    const motorState = document.getElementById("motor_state").textContent.includes("Activo");
    const turnState = document.getElementById("turn_state").textContent.includes("Activo");

    const res = await fetch(`${API}/api/device_state`, {
        method: "POST",
        headers: HEADERS,
        body: JSON.stringify({
            motor_on: !motorState,
            turn_led_on: turnState,
            box_full: false
        })
    });

    // ------------------------------
    // VALIDAR SI EL BACK RECHAZÓ LA PETICIÓN
    // ------------------------------
    if (!res.ok) {
        const data = await res.json();
        alert(data.error || "No se pudo actualizar el motor");

        // Forzar recarga visual correcta
        cargarEstado();
        return;
    }

    // Si todo ok
    cargarEstado();
});


// --- Historial ---
btnHistorial.addEventListener("click", async () => {
    const res = await fetch(`${API}/api/shift/history`, { headers: HEADERS });
    const data = await res.json();

    const tbody = document.querySelector("#tablaHistorial tbody");
    tbody.innerHTML = "";

    data.forEach(t => {
        const finAt = t.end_at ? new Date(t.end_at).toLocaleString('es-ES') : "-";
        const startAt = new Date(t.start_at).toLocaleString('es-ES');
        
        tbody.innerHTML += `
            <tr>
                <td>${t.id}</td>
                <td>${t.name}</td>
                <td>${startAt}</td>
                <td>${finAt}</td>
                <td>${t.counts.total}</td>
                <td>${t.counts.small}</td>
                <td>${t.counts.medium}</td>
                <td>${t.counts.large}</td>
            </tr>
        `;
    });
});

// --- Auto refresco ---
setInterval(() => {
    cargarEstado();
    cargarConteos();
}, 1500);

cargarEstado();
cargarConteos();
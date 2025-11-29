const API = "https://iot-automatizacion-g9.onrender.com";
const HEADERS = { "x-api-key": "patroclo", "Content-Type": "application/json" };

// botones y elementos
const btnTurno = document.getElementById("btnTurno");
const btnMotor = document.getElementById("btnMotor");

const qSearch = document.getElementById("q_search");
const startDate = document.getElementById("start_date");
const endDate = document.getElementById("end_date");
const btnFilter = document.getElementById("btnFilter");
const btnClear = document.getElementById("btnClear");
const btnExportExcel = document.getElementById("btnExportExcel");
const btnExportPdf = document.getElementById("btnExportPdf");

let historyCache = [];
let historyFiltered = [];
let shiftsChart = null;
let categoryChart = null;

// construir query params según filtros UI
function buildFilterQueryParams() {
    const params = new URLSearchParams();
    if (qSearch.value && qSearch.value.trim() !== "") {
        params.set("q", qSearch.value.trim());
    }
    if (startDate.value) {
        params.set("start_date", startDate.value);
    }
    if (endDate.value) {
        params.set("end_date", endDate.value);
    }
    return params.toString();
}

// cargar estado actual
async function cargarEstado() {
    try {
        const res = await fetch(`${API}/api/device_state`, { headers: HEADERS });
        if (!res.ok) return;
        const data = await res.json();

        const motorState = data.motor_on === true || data.motor_on === "true";
        const turnState = data.turn_led_on === true || data.turn_led_on === "true";
        const boxState = data.box_full === true || data.box_full === "true";

        actualizarEstadoVisual("motor_state", motorState);
        actualizarEstadoVisual("turn_state", turnState);
        actualizarEstadoVisual("box_state", boxState);

        // timestamp
        try {
            const fecha = new Date(data.timestamp);
            document.getElementById("timestamp").textContent = fecha.toLocaleString('es-ES');
        } catch(e) { 
            document.getElementById("timestamp").textContent = "-";
        }

        // botones
        btnTurno.textContent = turnState ? "Terminar Turno" : "Iniciar Turno";
        btnMotor.textContent = motorState ? "Desactivar Motor" : "Activar Motor";
        
        // deshabilitar motor si no hay turno activo
        btnMotor.disabled = !turnState;
        btnMotor.style.opacity = !turnState ? 0.6 : 1;
        btnMotor.style.cursor = !turnState ? 'not-allowed' : 'pointer';
    } catch (err) {
        console.error("cargarEstado error", err);
    }
}

// actualizar estado visual
function actualizarEstadoVisual(elementId, estado) {
    const elemento = document.getElementById(elementId);
    if (!elemento) return;
    elemento.textContent = estado ? "✓ Activo" : "✗ Inactivo";
    elemento.className = estado ? "estado-activo" : "estado-inactivo";
}

// cargar conteos
async function cargarConteos() {
    try {
        const res = await fetch(`${API}/api/counts/current`, { headers: HEADERS });
        if (!res.ok) return;
        const data = await res.json();
        document.getElementById("count_total").textContent = data.counts.total || 0;
        document.getElementById("count_small").textContent = data.counts.small || 0;
        document.getElementById("count_medium").textContent = data.counts.medium || 0;
        document.getElementById("count_large").textContent = data.counts.large || 0;
        
        // Actualizar gráfico de categorías
        updateCategoryChart(data.counts);
    } catch(e) { 
        console.error("cargarConteos", e); 
    }
}

// Modal personalizado para input
function showInputModal(title, placeholder) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-content">
                <h3>${title}</h3>
                <input 
                    type="text" 
                    id="modalInput" 
                    placeholder="Ingrese el nombre del turno"
                    autocomplete="off"
                />
                <div class="modal-buttons">
                    <button class="btn btn-gray" id="modalCancel">Cancelar</button>
                    <button class="btn" id="modalConfirm">Aceptar</button>
                </div>
            </div>
        `;
        
        document.body.appendChild(modal);
        
        const input = modal.querySelector('#modalInput');
        const confirmBtn = modal.querySelector('#modalConfirm');
        const cancelBtn = modal.querySelector('#modalCancel');
        
        input.focus();
        
        const cleanup = (value) => {
            document.body.removeChild(modal);
            resolve(value);
        };
        
        confirmBtn.onclick = () => cleanup(input.value.trim());
        cancelBtn.onclick = () => cleanup(null);
        
        input.onkeypress = (e) => {
            if (e.key === 'Enter') cleanup(input.value.trim());
        };
        
        modal.onclick = (e) => {
            if (e.target === modal) cleanup(null);
        };
    });
}

// iniciar / terminar turno
btnTurno.addEventListener("click", async () => {
    const turnState = document.getElementById("turn_state").textContent.includes("Activo");

    if (!turnState) {
        const nombre = await showInputModal("Iniciar Turno", "Ingrese el nombre del turno");
        if (!nombre || nombre === "") return;
        
        try {
            const res = await fetch(`${API}/api/shift/start`, {
                method: "POST",
                headers: HEADERS,
                body: JSON.stringify({ name: nombre })
            });
            
            if (!res.ok) {
                showNotification("Error al iniciar turno", "error");
                return;
            }
            showNotification("Turno iniciado correctamente", "success");
        } catch(e) {
            console.error("Error iniciando turno:", e);
            showNotification("Error de conexión", "error");
            return;
        }
    } else {
        const confirmar = await showConfirmModal("¿Deseas terminar el turno actual?");
        if (!confirmar) return;
        
        try {
            const res = await fetch(`${API}/api/shift/end`, { 
                method: "POST", 
                headers: HEADERS 
            });
            
            if (!res.ok) {
                showNotification("Error al terminar turno", "error");
                return;
            }
            showNotification("Turno terminado correctamente", "success");
        } catch(e) {
            console.error("Error terminando turno:", e);
            showNotification("Error de conexión", "error");
            return;
        }
    }

    await cargarEstado();
    await cargarConteos();
    await fetchHistoryAndRender();
    await fetchStatsAndRenderChart();
});

// Modal de confirmación
function showConfirmModal(message) {
    return new Promise((resolve) => {
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-content">
                <h3>Confirmación</h3>
                <p>${message}</p>
                <div class="modal-buttons">
                    <button class="btn btn-gray" id="modalCancel">Cancelar</button>
                    <button class="btn" id="modalConfirm">Aceptar</button>
                </div>
            </div>
        `;
        
        document.body.appendChild(modal);
        
        const confirmBtn = modal.querySelector('#modalConfirm');
        const cancelBtn = modal.querySelector('#modalCancel');
        
        const cleanup = (value) => {
            document.body.removeChild(modal);
            resolve(value);
        };
        
        confirmBtn.onclick = () => cleanup(true);
        cancelBtn.onclick = () => cleanup(false);
        
        modal.onclick = (e) => {
            if (e.target === modal) cleanup(false);
        };
    });
}

// Sistema de notificaciones
function showNotification(message, type = 'info') {
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    setTimeout(() => {
        notification.classList.add('show');
    }, 10);
    
    setTimeout(() => {
        notification.classList.remove('show');
        setTimeout(() => {
            document.body.removeChild(notification);
        }, 300);
    }, 3000);
}

// motor on/off
btnMotor.addEventListener("click", async () => {
    const motorState = document.getElementById("motor_state").textContent.includes("Activo");
    const turnState = document.getElementById("turn_state").textContent.includes("Activo");

    if (!turnState) {
        showNotification("No se puede activar el motor sin turno activo", "error");
        return;
    }

    try {
        const res = await fetch(`${API}/api/device_state`, {
            method: "POST",
            headers: HEADERS,
            body: JSON.stringify({
                motor_on: !motorState,
                turn_led_on: turnState,
                box_full: false
            })
        });

        if (!res.ok) {
            const data = await res.json().catch(()=>({error:"Error desconocido"}));
            showNotification(data.error || "No se pudo actualizar el motor", "error");
        } else {
            showNotification(motorState ? "Motor desactivado" : "Motor activado", "success");
        }
    } catch(e) {
        console.error("Error actualizando motor:", e);
        showNotification("Error de conexión", "error");
    }
    
    await cargarEstado();
});

// historial: fetch + render con filtros
async function fetchHistoryAndRender() {
    try {
        const params = buildFilterQueryParams();
        const url = `${API}/api/shift/history${params ? '?'+params : ''}`;
        const res = await fetch(url, { headers: HEADERS });
        if (!res.ok) {
            showNotification("Error al cargar historial", "error");
            return;
        }
        const data = await res.json();
        historyCache = data;
        historyFiltered = data.slice();
        renderHistoryTable(historyFiltered);
        showNotification("Historial actualizado", "success");
    } catch(e) { 
        console.error("fetchHistoryAndRender", e);
        showNotification("Error de conexión", "error");
    }
}

function renderHistoryTable(list) {
    const tbody = document.querySelector("#tablaHistorial tbody");
    if (!tbody) return;
    
    tbody.innerHTML = "";
    
    if (list.length === 0) {
        const row = document.createElement("tr");
        row.innerHTML = '<td colspan="8" style="text-align:center; color:#999;">No hay turnos registrados</td>';
        tbody.appendChild(row);
        return;
    }
    
    list.forEach(t => {
        const finAt = t.end_at ? new Date(t.end_at).toLocaleString('es-ES') : "-";
        const startAt = new Date(t.start_at).toLocaleString('es-ES');
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${t.id}</td>
            <td>${escapeHtml(t.name)}</td>
            <td>${startAt}</td>
            <td>${finAt}</td>
            <td>${t.counts.total || 0}</td>
            <td>${t.counts.small || 0}</td>
            <td>${t.counts.medium || 0}</td>
            <td>${t.counts.large || 0}</td>
        `;
        tbody.appendChild(row);
    });
}

// helper escape
function escapeHtml(text) {
    if (!text) return "";
    return text.replace(/[&<>"']/g, (m) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[m]));
}

// filtros: aplicar
btnFilter.addEventListener("click", async () => {
    await fetchHistoryAndRender();
    await fetchStatsAndRenderChart();
});

// limpiar filtros
btnClear.addEventListener("click", async () => {
    qSearch.value = "";
    startDate.value = "";
    endDate.value = "";
    await fetchHistoryAndRender();
    await fetchStatsAndRenderChart();
});

// Export Excel
btnExportExcel.addEventListener("click", () => {
    const params = buildFilterQueryParams();
    const url = `${API}/api/shift/export/excel${params ? '?'+params : ''}`;
    const a = document.createElement('a');
    a.href = url;
    a.target = '_blank';
    a.click();
    showNotification("Descargando Excel...", "info");
});

// Export PDF
btnExportPdf.addEventListener("click", () => {
    const params = buildFilterQueryParams();
    const url = `${API}/api/shift/export/pdf${params ? '?'+params : ''}`;
    const a = document.createElement('a');
    a.href = url;
    a.target = '_blank';
    a.click();
    showNotification("Descargando PDF...", "info");
});

// Gráfico de barras de turnos
async function fetchStatsAndRenderChart() {
    try {
        const params = buildFilterQueryParams();
        const url = `${API}/api/shift/stats${params ? '?'+params : ''}`;
        const res = await fetch(url, { headers: HEADERS });
        if (!res.ok) return;
        const data = await res.json();

        const ctx = document.getElementById('shiftsChart');
        if (!ctx) return;
        
        if (shiftsChart) {
            shiftsChart.data.labels = data.labels || [];
            shiftsChart.data.datasets[0].data = data.totals || [];
            shiftsChart.update();
            return;
        }

        shiftsChart = new Chart(ctx.getContext('2d'), {
            type: 'bar',
            data: {
                labels: data.labels || [],
                datasets: [{
                    label: 'Total objetos por turno',
                    data: data.totals || [],
                    backgroundColor: 'rgba(102,170,255,0.8)',
                    borderColor: 'rgba(102,170,255,1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: { 
                    y: { 
                        beginAtZero: true,
                        ticks: {
                            precision: 0,
                            color: '#eaeaea'
                        },
                        grid: {
                            color: 'rgba(255,255,255,0.1)'
                        }
                    },
                    x: {
                        ticks: {
                            color: '#eaeaea',
                            maxRotation: 45,
                            minRotation: 45
                        },
                        grid: {
                            color: 'rgba(255,255,255,0.1)'
                        }
                    }
                },
                plugins: {
                    legend: {
                        labels: {
                            color: '#eaeaea'
                        }
                    }
                }
            }
        });

    } catch(e) { 
        console.error("fetchStatsAndRenderChart", e); 
    }
}

// Gráfico de dona de categorías
function updateCategoryChart(counts) {
    const ctx = document.getElementById('categoryChart');
    if (!ctx) return;
    
    const total = (counts.small || 0) + (counts.medium || 0) + (counts.large || 0);
    
    const data = {
        labels: ['Pequeños', 'Medianos', 'Grandes'],
        datasets: [{
            data: [counts.small || 0, counts.medium || 0, counts.large || 0],
            backgroundColor: [
                'rgba(255, 206, 86, 0.9)',
                'rgba(75, 192, 192, 0.9)',
                'rgba(255, 99, 132, 0.9)'
            ],
            borderColor: [
                'rgba(255, 206, 86, 1)',
                'rgba(75, 192, 192, 1)',
                'rgba(255, 99, 132, 1)'
            ],
            borderWidth: 2
        }]
    };
    
    if (categoryChart) {
        categoryChart.data.datasets[0].data = data.datasets[0].data;
        categoryChart.update();
        return;
    }
    
    categoryChart = new Chart(ctx.getContext('2d'), {
        type: 'doughnut',
        data: data,
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        color: '#eaeaea',
                        padding: 15,
                        font: {
                            size: 13,
                            weight: 600
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            const label = context.label || '';
                            const value = context.parsed || 0;
                            const percentage = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
                            return `${label}: ${value} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

// Auto refresh: estado y conteos periódicamente
setInterval(() => {
    cargarEstado();
    cargarConteos();
}, 2000);

// Inicializar todo al cargar la página
async function init() {
    await cargarEstado();
    await cargarConteos();
    await fetchHistoryAndRender();
    await fetchStatsAndRenderChart();
}

// Verificar que el DOM esté listo
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
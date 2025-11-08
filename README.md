# IoT_Automatizacion_G9
## 1. Descripción completa del caso (resumen funcional)

Tienes una banda transportadora con dos motores que mueven la cinta. Los objetos (pequeños, medianos, grandes) son transportados y pasan por un sensor ultrasónico superior que detecta su presencia y estima su tamaño (basado en distancia medida). Los objetos caen en una caja de almacenamiento con otro sensor ultrasónico que detecta cuando la caja está por llenarse.

### Comportamiento requerido:

- En la web / app existe un botón Activar turno que al pulsarlo cambia a Acabar turno. Mientras hay turno activo, se enciende LED verde.
- También hay un botón Activar cinta que cambia a Detener cinta. Solo se puede activar la cinta si existe un turno activo. Al activar la cinta se enciende LED rojo y la(s) cinta(s) arrancan (motores).
- Mientras turno + cinta están activos, el ESP32 cuenta objetos generales y clasifica cada objeto como pequeño/mediano/grande según la lectura del sensor superior. Cada evento se envía al backend (para asignarlo al turno activo).
- Cuando el sensor de la caja detecta que la caja está por llenarse, suena un buzzer, la cinta se detiene (motor OFF) y el frontend muestra almacenamiento lleno.
- Al final del turno (cuando el usuario pulsa Acabar turno) suena el buzzer.
- En la web/app se muestran: turno actual (id), botones, indicadores de almacenamiento, contador total de objetos y por tamaño, y botón Ver historial que muestra lista de turnos (inicio/fin y conteos). Al ver historial hay botón Producción para volver.

### Seguridad y arquitectura:

- ESP32 ↔ Backend (API REST) ↔ Base de datos (SQLite por defecto).
- Frontend y App móvil consumen la misma API REST.
- Autenticación mínima con x-api-key para endpoints de control/POST.

## 2. Materiales (lista concreta)

- 1 × ESP32 DevKit v1
- 2 × LED (verde y rojo) + 2 resistencias 220Ω
- 2 × motores DC (cinta) — o 1 motor con doble salida según tu mecánica
- 2 × módulos relé de 1 canal por motor (o driver L298N/driver MOSFET adecuado) — para alimentar los motores con su fuente
- 2 × sensor ultrasónico HC-SR04 (uno arriba para tamaño / conteo y otro en la caja para nivel)
- 1 × Buzzer (activo o pasivo; usaré buzzer activo para simplicidad)
- Fuente de alimentación para motores (por ejemplo 12V) y fuente 5V para relés (o alimentador según motores)
- Cables dupont, protoboard, tornillería / caja pequeña para almacenamiento

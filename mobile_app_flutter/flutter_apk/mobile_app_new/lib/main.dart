import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async'; // ← IMPORTANTE: agregar esto

const String API_BASE = "https://iot-automatizacion-g9.onrender.com/api";
const String API_KEY = "patroclo";

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map counts = {"small": 0, "medium": 0, "large": 0, "total": 0};
  bool motor = false;
  bool turnLed = false;
  bool boxFull = false;
  List shifts = [];

  @override
  void initState() {
    super.initState();
    fetchAll();

    // ← CAMBIO IMPORTANTE
    Timer.periodic(const Duration(seconds: 3), (_) => fetchAll());
  }

  Future<void> fetchAll() async {
    try {
      final st = await http.get(
        Uri.parse('$API_BASE/device_state'),
        headers: {'x-api-key': API_KEY},
      );

      final cur = await http.get(
        Uri.parse('$API_BASE/counts/current'),
        headers: {'x-api-key': API_KEY},
      );

      final hist = await http.get(
        Uri.parse('$API_BASE/shift/history'),
        headers: {'x-api-key': API_KEY},
      );

      if (st.statusCode == 200) {
        final j = json.decode(st.body);
        setState(() {
          motor = j['motor_on'];
          turnLed = j['turn_led_on'];
          boxFull = j['box_full'] ?? false;
        });
      }

      if (cur.statusCode == 200) {
        final j = json.decode(cur.body);
        setState(() {
          counts = j['counts'] ?? counts;
        });
      }

      if (hist.statusCode == 200) {
        setState(() {
          shifts = json.decode(hist.body);
        });
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> postDeviceState(bool newMotorState) async {
    await http.post(
      Uri.parse('$API_BASE/device_state'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY,
      },
      body: json.encode({
        "motor_on": newMotorState,
        "turn_led_on": turnLed,
        "box_full": false
      }),
    );
    fetchAll();
  }

  Future<void> postStartShift(String name) async {
    await http.post(
      Uri.parse('$API_BASE/shift/start'),
      headers: {'Content-Type': 'application/json', 'x-api-key': API_KEY},
      body: json.encode({"name": name}),
    );
    fetchAll();
  }

  Future<void> postEndShift() async {
    await http.post(
      Uri.parse('$API_BASE/shift/end'),
      headers: {'Content-Type': 'application/json', 'x-api-key': API_KEY},
    );
    fetchAll();
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cinta Transportadora IoT")),
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          // ---------------------------------------------------
          // TURNO
          // ---------------------------------------------------
          Card(
            child: ListTile(
              title: const Text("Turno"),
              subtitle: Text(turnLed ? "Activo" : "Inactivo"),
              trailing: ElevatedButton(
                child: Text(turnLed ? "Cerrar" : "Iniciar"),
                onPressed: () async {
                  if (!turnLed) {
                    final ctrl = TextEditingController();
                    final nombre = await showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                              title: const Text("Nombre del turno"),
                              content: TextField(controller: ctrl),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, null),
                                    child: const Text("Cancelar")),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, ctrl.text),
                                    child: const Text("Iniciar"))
                              ],
                            ));

                    if (nombre != null && nombre.isNotEmpty) {
                      await postStartShift(nombre);
                    }
                  } else {
                    await postEndShift();
                  }
                },
              ),
            ),
          ),

          // ---------------------------------------------------
          // MOTOR
          // ---------------------------------------------------
          Card(
            child: ListTile(
              title: const Text("Motor"),
              subtitle: Text(motor ? "ENCENDIDO" : "APAGADO"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                      onPressed: () => postDeviceState(true),
                      child: const Text("Activar")),
                  const SizedBox(width: 10),
                  ElevatedButton(
                      onPressed: () => postDeviceState(false),
                      child: const Text("Detener")),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------
          // CONTEOS
          // ---------------------------------------------------
          Card(
            child: Column(
              children: [
                Text("Total: ${counts['total']}"),
                Text("Pequeños: ${counts['small']}"),
                Text("Medianos: ${counts['medium']}"),
                Text("Grandes: ${counts['large']}"),
              ],
            ),
          ),

          // ---------------------------------------------------
          // HISTORIAL
          // ---------------------------------------------------
          Card(
            child: Column(
              children: [
                const Text("Historial de Turnos",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ...shifts.map((s) => ListTile(
                      title: Text("${s['name']}"),
                      subtitle: Text(
                          "Total: ${s['counts']['total']}  |  Inicio: ${s['start_at']}"),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

const String API = "https://iot-automatizacion-g9.onrender.com/api";
const String API_KEY = "patroclo";

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1f1f1f),
        cardColor: const Color(0xFF2b2b2b),
        primaryColor: const Color(0xFF66aaff),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool motor = false;
  bool turnLed = false;
  bool boxFull = false;

  Map counts = {"small": 0, "medium": 0, "large": 0, "total": 0};
  List shifts = [];

  @override
  void initState() {
    super.initState();
    fetchAll();
    Timer.periodic(const Duration(seconds: 2), (_) => fetchAll());
  }

  Future<void> fetchAll() async {
    try {
      final st = await http.get(Uri.parse("$API/device_state"), headers: {"x-api-key": API_KEY});
      final cur = await http.get(Uri.parse("$API/counts/current"), headers: {"x-api-key": API_KEY});
      final hist = await http.get(Uri.parse("$API/shift/history"), headers: {"x-api-key": API_KEY});

      if (st.statusCode == 200) {
        final j = json.decode(st.body);
        setState(() {
          motor = j["motor_on"];
          turnLed = j["turn_led_on"];
          boxFull = j["box_full"];
        });
      }

      if (cur.statusCode == 200) {
        final j = json.decode(cur.body);
        setState(() => counts = j["counts"]);
      }

      if (hist.statusCode == 200) {
        setState(() => shifts = json.decode(hist.body));
      }
    } catch (_) {}
  }

  Future<void> postMotor(bool value) async {
    await http.post(Uri.parse("$API/device_state"),
        headers: {"Content-Type": "application/json", "x-api-key": API_KEY},
        body: json.encode({
          "motor_on": value,
          "turn_led_on": turnLed,
          "box_full": false,
        }));
    fetchAll();
  }

  Future<void> startShift() async {
    final ctrl = TextEditingController();

    final nombre = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2b2b2b),
        title: const Text("Nombre del turno", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Ejemplo: Juan",
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(child: const Text("Cancelar"), onPressed: () => Navigator.pop(context, null)),
          TextButton(child: const Text("Iniciar"), onPressed: () => Navigator.pop(context, ctrl.text)),
        ],
      ),
    );

    if (nombre != null && nombre.isNotEmpty) {
      await http.post(Uri.parse("$API/shift/start"),
          headers: {"Content-Type": "application/json", "x-api-key": API_KEY},
          body: json.encode({"name": nombre}));
      fetchAll();
    }
  }

  Future<void> endShift() async {
    await http.post(Uri.parse("$API/shift/end"),
        headers: {"Content-Type": "application/json", "x-api-key": API_KEY});
    fetchAll();
  }

  // -----------------------------
  // ESTILOS
  // -----------------------------
  ButtonStyle btnBlue = ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF2b6cb0),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  ButtonStyle btnYellow = ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFFD6A300),
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  ButtonStyle btnGray = ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFF555555),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  Widget stateBox(String label, bool state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1b1b1b),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: state ? Colors.green : Colors.red, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: state ? const Color(0xFF1f4d2b) : const Color(0xFF4d1f1f),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              state ? "✓ Activo" : "✗ Inactivo",
              style: TextStyle(
                color: state ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget countBox(String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1b1b1b),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 6),
          Text("$value",
              style: const TextStyle(fontSize: 20, color: Color(0xFF66aaff)))
        ],
      ),
    );
  }

  // -----------------------------------------
  // UI PRINCIPAL
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel IoT", style: TextStyle(color: Color(0xFF66aaff))),
        backgroundColor: const Color(0xFF1f1f1f),
        elevation: 0,
      ),

      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ---------------------- BOTONES ----------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                style: btnBlue,
                onPressed: turnLed ? endShift : startShift,
                child: Text(turnLed ? "Terminar" : "Iniciar Turno"),
              ),
              ElevatedButton(
                style: btnYellow,
                onPressed: () => postMotor(!motor),
                child: Text(motor ? "Detener Motor" : "Activar Motor"),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ---------------------- ESTADO ----------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Estado Actual",
                      style: TextStyle(fontSize: 20, color: Color(0xFF66aaff))),
                  const SizedBox(height: 12),
                  stateBox("Motor:", motor),
                  const SizedBox(height: 10),
                  stateBox("Turno activo:", turnLed),
                  const SizedBox(height: 10),
                  stateBox("Caja llena:", boxFull),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ---------------------- CONTEOS ----------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Conteos",
                      style: TextStyle(fontSize: 20, color: Color(0xFF66aaff))),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      countBox("Total", counts["total"]),
                      countBox("Pequeños", counts["small"]),
                      countBox("Medianos", counts["medium"]),
                      countBox("Grandes", counts["large"]),
                    ],
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ---------------------- HISTORIAL ----------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Historial de Turnos",
                      style: TextStyle(fontSize: 20, color: Color(0xFF66aaff))),
                  const SizedBox(height: 14),
                  ...shifts.map((t) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1b1b1b),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t["name"],
                              style: const TextStyle(
                                  fontSize: 16, color: Color(0xFF66aaff))),
                          const SizedBox(height: 4),
                          Text("Inicio: ${t["start_at"]}"),
                          Text("Fin: ${t["end_at"] ?? "-"}"),
                          Text("Total: ${t["counts"]["total"]}"),
                        ],
                      ),
                    );
                  })
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

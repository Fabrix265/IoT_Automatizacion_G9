import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

const String API_BASE = "https://TU_BACKEND_PUBLIC_URL"; // <-- CAMBIAR
const String API_KEY = "TU_API_KEY_SEGURA";               // <-- CAMBIAR

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override Widget build(BuildContext ctx) => MaterialApp(home: HomePage());
}

class HomePage extends StatefulWidget { @override State createState() => _HomePageState(); }
class _HomePageState extends State<HomePage> {
  Map counts = {"small":0,"medium":0,"large":0,"total":0};
  bool motor = false;
  bool turnLed = false;
  bool boxFull = false;
  List shifts = [];

  @override void initState() {
    super.initState();
    fetchAll();
    Future.periodic(Duration(seconds: 3)).listen((_) => fetchAll());
  }

  Future<void> fetchAll() async {
    try {
      final st = await http.get(Uri.parse('$API_BASE/api/device_state'));
      final cur = await http.get(Uri.parse('$API_BASE/api/counts/current'));
      final hist = await http.get(Uri.parse('$API_BASE/api/shift/history'));
      if (st.statusCode == 200) {
        final j = jsonDecode(st.body);
        setState(()=> { motor = j['motor_on'], turnLed = j['turn_led_on'], boxFull = j['box_full'] ?? false });
      }
      if (cur.statusCode == 200) {
        final j = jsonDecode(cur.body);
        setState(()=> { counts = j['counts'] ?? counts });
      }
      if (hist.statusCode == 200) {
        final j = jsonDecode(hist.body);
        setState(()=> { shifts = j; });
      }
    } catch (e) { print(e); }
  }

  Future<void> post(String path, Map body) async {
    try {
      await http.post(Uri.parse('$API_BASE$path'),
        headers: {'Content-Type':'application/json','x-api-key': API_KEY},
        body: jsonEncode(body));
      await fetchAll();
    } catch (e) { print(e); }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Banda Conveyor')),
      body: Padding(padding: EdgeInsets.all(12), child: Column(children: [
        Card(child: ListTile(title: Text('Turno'), subtitle: Text(turnLed ? 'Activo' : 'Inactivo'), trailing: ElevatedButton(
          onPressed: () async {
            if (!turnLed) {
              final name = await showDialog(context: context, builder: (_) => AlertDialog(
                title: Text('Nombre turno'), content: TextField(controller: TextEditingController(text: "Turno ${DateTime.now()}")),
                actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text('Cancel')), TextButton(onPressed: ()=>Navigator.pop(context, 'Start'), child: Text('Start'))],
              ));
              await post('/api/shift/start', {'name': name ?? 'Turno'});
            } else {
              await post('/api/shift/end', {});
            }
          },
          child: Text(turnLed ? 'Acabar Turno' : 'Activar Turno')
        ))),
        Card(child: ListTile(title: Text('Cinta'), subtitle: Text(motor ? 'ENCENDIDO' : 'APAGADO'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(onPressed: () => post('/api/device_state', {'motor_on':true}), child: Text('Activar')),
          SizedBox(width:8),
          ElevatedButton(onPressed: () => post('/api/device_state', {'motor_on':false}), child: Text('Detener')),
        ]))),
        Card(child: Column(children: [
          Text('Almacenamiento: ${boxFull ? 'LLENO' : 'Disponible'}'),
          Text('Total: ${counts['total'] ?? 0}'),
          Text('Pequeños: ${counts['small'] ?? 0}'),
          Text('Medianos: ${counts['medium'] ?? 0}'),
          Text('Grandes: ${counts['large'] ?? 0}'),
        ])),
        Expanded(child: ListView.builder(itemCount: shifts.length, itemBuilder: (_,i){
          final s = shifts[i];
          return ListTile(title: Text("${s['name']} (${s['id']})"), subtitle: Text("Counts: ${s['counts']}"));
        }))
      ])),
    );
  }
}

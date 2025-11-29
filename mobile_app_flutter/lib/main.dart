import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:fl_chart/fl_chart.dart';

const String API_BASE = "https://iot-automatizacion-g9.onrender.com/api";
const String API_KEY = "patroclo";

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext ctx) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cinta Transportadora IoT',
      theme: ThemeData.dark(useMaterial3: false),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic> counts = {"small": 0, "medium": 0, "large": 0, "total": 0};

  bool motor = false;
  bool turnLed = false;
  bool boxFull = false;

  List<dynamic> shifts = [];

  final TextEditingController qController = TextEditingController();
  DateTimeRange? dateRange;

  List<dynamic> historyCache = [];

  List<String> chartLabels = [];
  List<int> chartTotals = [];

  int refreshIntervalSeconds = 3;
  bool loading = false;

  final DateFormat df = DateFormat("yyyy-MM-dd HH:mm:ss");
  final DateFormat dfShort = DateFormat("yyyy-MM-dd");

  @override
  void initState() {
    super.initState();
    fetchAll();

    Future.periodic(Duration(seconds: refreshIntervalSeconds))
        .listen((_) => fetchAll());
  }

  Map<String, String> _headersJson() => {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY,
      };

  String _buildFilterParams() {
    final p = <String, String>{};
    final q = qController.text.trim();
    if (q.isNotEmpty) p['q'] = q;

    if (dateRange != null) {
      p['start_date'] = dfShort.format(dateRange!.start);
      p['end_date'] = dfShort.format(dateRange!.end);
    }

    if (p.isEmpty) return '';
    final params = p.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '?$params';
  }

  Future<void> fetchAll() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      await Future.wait([
        _fetchDeviceState(),
        _fetchCounts(),
        _fetchHistory(),
        _fetchStats(),
      ]);
    } catch (_) {}

    if (mounted) setState(() => loading = false);
  }

  Future<void> _fetchDeviceState() async {
    try {
      final res = await http.get(
        Uri.parse('$API_BASE/device_state'),
        headers: {'x-api-key': API_KEY},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);

        if (mounted) {
          setState(() {
            motor = j['motor_on'] == true;
            turnLed = j['turn_led_on'] == true;
            boxFull = j['box_full'] == true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchCounts() async {
    try {
      final res = await http.get(
        Uri.parse('$API_BASE/counts/current'),
        headers: {'x-api-key': API_KEY},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);

        if (mounted) {
          setState(() {
            counts = Map<String, dynamic>.from(j['counts'] ?? counts);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchHistory() async {
    try {
      final params = _buildFilterParams();
      final res = await http.get(
        Uri.parse('$API_BASE/shift/history$params'),
        headers: {'x-api-key': API_KEY},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);
        if (mounted) {
          historyCache = j;
          shifts = List.from(j);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchStats() async {
    try {
      final params = _buildFilterParams();
      final res = await http.get(
        Uri.parse('$API_BASE/shift/stats$params'),
        headers: {'x-api-key': API_KEY},
      );
      if (res.statusCode == 200) {
        final j = json.decode(res.body);
        if (mounted) {
          chartLabels = List<String>.from(j['labels'] ?? []);
          chartTotals = List<int>.from(
              (j['totals'] ?? []).map<int>((x) => (x ?? 0).toInt()));
        }
      }
    } catch (_) {}
  }

  Future<void> postDeviceState(bool newMotorState) async {
    try {
      final res = await http.post(
        Uri.parse('$API_BASE/device_state'),
        headers: _headersJson(),
        body: json.encode({
          "motor_on": newMotorState,
          "turn_led_on": turnLed,
          "box_full": false
        }),
      );

      if (res.statusCode == 200) {
        await fetchAll();
        _showSnack(newMotorState ? 'Motor activado' : 'Motor desactivado');
      } else {
        _showSnack('Error actualizando motor', isError: true);
      }
    } catch (_) {
      _showSnack('Error de conexión', isError: true);
    }
  }

  Future<void> postStartShift(String name) async {
    try {
      final res = await http.post(
        Uri.parse('$API_BASE/shift/start'),
        headers: _headersJson(),
        body: json.encode({"name": name}),
      );

      if (res.statusCode == 200) {
        await fetchAll();
        _showSnack('Turno iniciado');
      } else {
        _showSnack('Error iniciando turno', isError: true);
      }
    } catch (_) {
      _showSnack('Error de conexión', isError: true);
    }
  }

  Future<void> postEndShift() async {
    try {
      final res = await http.post(
        Uri.parse('$API_BASE/shift/end'),
        headers: _headersJson(),
      );

      if (res.statusCode == 200) {
        await fetchAll();
        _showSnack('Turno terminado');
      } else {
        _showSnack('Error terminando turno', isError: true);
      }
    } catch (_) {
      _showSnack('Error de conexión', isError: true);
    }
  }

  Future<void> exportFile(String endpoint, String filename) async {
    try {
      final params = _buildFilterParams();
      final url = Uri.parse('$API_BASE/$endpoint$params');

      final res =
          await http.get(url, headers: {'x-api-key': API_KEY});

      if (res.statusCode != 200) {
        _showSnack('Error exportando archivo', isError: true);
        return;
      }

      final bytes = res.bodyBytes;
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');

      await file.writeAsBytes(bytes);

      _showSnack('Archivo guardado: ${file.path}');
      await OpenFile.open(file.path);
    } catch (_) {
      _showSnack('Error al guardar archivo', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<String?> _askForShiftName() async {
    final ctrl = TextEditingController();

    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del turno'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: 'Ingrese el nombre del turno'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Iniciar')),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 2);
    final last = DateTime(now.year + 1);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: dateRange,
    );

    if (picked != null) {
      setState(() => dateRange = picked);
    }
  }

  void _clearFilters() {
    qController.clear();
    setState(() => dateRange = null);
    fetchAll();
  }

  Widget _buildChartBar() {
    if (chartLabels.isEmpty || chartTotals.isEmpty) {
      return const Center(child: Text('No hay datos para el gráfico.'));
    }

    final labels = chartLabels.length > 8
        ? chartLabels.sublist(chartLabels.length - 8)
        : chartLabels;

    final totals = chartTotals.length > 8
        ? chartTotals.sublist(chartTotals.length - 8)
        : chartTotals;

    final maxVal = totals.isEmpty
        ? 1
        : totals.reduce((a, b) => (a > b ? a : b)).toDouble();

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.2,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(labels[idx].split(' ').first,
                      style: const TextStyle(fontSize: 10));
                },
                reservedSize: 40,
              ),
            ),
          ),
          barGroups: List.generate(
            totals.length,
            (i) => BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: totals[i].toDouble(),
                    width: 18,
                  )
                ]),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildDonut() {
    final s = counts;
    final total =
        (s['small'] ?? 0) + (s['medium'] ?? 0) + (s['large'] ?? 0);

    if (total == 0) {
      return const Center(child: Text('No hay datos de categorías.'));
    }

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 4,
          centerSpaceRadius: 30,
          sections: [
            PieChartSectionData(
                value: (s['small'] ?? 0).toDouble(),
                title: 'Peq\n${s['small']}'),
            PieChartSectionData(
                value: (s['medium'] ?? 0).toDouble(),
                title: 'Med\n${s['medium']}'),
            PieChartSectionData(
                value: (s['large'] ?? 0).toDouble(),
                title: 'Gra\n${s['large']}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cinta Transportadora IoT")),
      body: RefreshIndicator(
        onRefresh: fetchAll,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ===== ESTADO Y CONTROLES =====
            Card(
              child: ListTile(
                title: const Text('Estado actual'),
                subtitle: Text(
                    'Turno: ${turnLed ? "Activo" : "Inactivo"} • Motor: ${motor ? "ON" : "OFF"}'),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        if (!turnLed) {
                          final name = await _askForShiftName();
                          if (name != null && name.isNotEmpty) {
                            await postStartShift(name);
                          }
                        } else {
                          final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                    title: const Text('Confirmar'),
                                    content: const Text(
                                        '¿Terminar el turno actual?'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('No')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('Sí')),
                                    ],
                                  ));
                          if (ok == true) await postEndShift();
                        }
                      },
                      child: Text(
                          turnLed ? 'Terminar turno' : 'Iniciar turno'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: turnLed
                              ? () => postDeviceState(true)
                              : null,
                          child: const Text('Encender motor'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: turnLed
                              ? () => postDeviceState(false)
                              : null,
                          child: const Text('Detener motor'),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== CONTEOS + GRÁFICOS =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Conteos',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _countBox('Total', counts['total'].toString()),
                        _countBox('Peq', counts['small'].toString()),
                        _countBox('Med', counts['medium'].toString()),
                        _countBox('Gra', counts['large'].toString()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDonut(),
                    const Divider(),
                    const Text('Totales por turno',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildChartBar(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== FILTROS =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qController,
                            decoration: const InputDecoration(
                                labelText: 'Buscar por nombre',
                                hintText: 'Texto a buscar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                            onPressed: _pickDateRange,
                            child: const Text('Rango fechas')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                            onPressed: fetchAll, child: const Text('Filtrar')),
                        const SizedBox(width: 8),
                        TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Limpiar')),
                      ],
                    ),
                    if (dateRange != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            'Fechas: ${dfShort.format(dateRange!.start)} → ${dfShort.format(dateRange!.end)}'),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== EXPORTAR =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          exportFile('shift/export/excel', 'historial.xlsx'),
                      icon: const Icon(Icons.file_download),
                      label: const Text('Exportar XLSX'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () =>
                          exportFile('shift/export/pdf', 'historial.pdf'),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Exportar PDF'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ===== HISTORIAL =====
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Historial de turnos',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (shifts.isEmpty)
                      const Text('No hay turnos registrados'),
                    ...shifts.map((s) {
                      final start = s['start_at'] ?? '';
                      final end = s['end_at'] ?? '';
                      final total = s['counts']?['total'] ?? 0;
                      return ListTile(
                        title: Text(s['name']),
                        subtitle: Text(
                            'Inicio: $start • Fin: ${end.isEmpty ? "En curso" : end}'),
                        trailing: Text('Total: $total'),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _countBox(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.black45),
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 18,
                color: Colors.cyanAccent,
                fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

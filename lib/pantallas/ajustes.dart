import 'package:flutter/material.dart';

import '../almacen.dart';
import '../servicios/nube.dart';
import '../tema.dart';

class PantallaAjustes extends StatefulWidget {
  const PantallaAjustes({super.key});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> {
  final a = Almacen.instancia;
  late final _servidor = TextEditingController(text: a.servidor);
  late final _clave = TextEditingController(text: a.clave);
  String? _resultado;
  bool _probando = false;

  bool _bien = false;

  /// Acepta la dirección con o sin https:// y con / al final.
  static String _normalizar(String t) {
    var d = t.trim().replaceAll(RegExp(r'/+$'), '');
    if (d.isNotEmpty && !d.startsWith(RegExp(r'https?://'))) d = 'https://$d';
    return d;
  }

  Future<void> _guardarYProbar() async {
    FocusScope.of(context).unfocus();
    a.servidor = _normalizar(_servidor.text);
    a.clave = _clave.text.trim();
    _servidor.text = a.servidor;
    await a.guardar();
    if (!mounted) return;
    if (!a.nubeLista) {
      setState(() {
        _bien = false;
        _resultado = 'Escribe la dirección del servidor y la clave.';
      });
      return;
    }
    setState(() => _probando = true);
    final error = await Nube.instancia.probar();
    if (!mounted) return;
    setState(() {
      _probando = false;
      _bien = error == null;
      _resultado = error ?? 'Conexión correcta. Ya puedes entregar videos por QR.';
    });
    if (error == null) Nube.instancia.subirPendientes();
  }

  @override
  void dispose() {
    _servidor.dispose();
    _clave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Nube (Cloudflare)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Los datos te los da la guía de instalación.', style: TextStyle(color: Marles.tintaSuave)),
          const SizedBox(height: 12),
          TextField(
            controller: _servidor,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Dirección del servidor',
              hintText: 'https://marles360.tucuenta.workers.dev',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clave,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Clave de subida'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _probando ? null : _guardarYProbar,
            child: Text(_probando ? 'Probando…' : 'Guardar y probar'),
          ),
          if (_resultado != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_bien ? Icons.check_circle : Icons.error_outline,
                    color: _bien ? Marles.turquesaProfundo : Marles.rojo),
                const SizedBox(width: 8),
                Expanded(child: Text(_resultado!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

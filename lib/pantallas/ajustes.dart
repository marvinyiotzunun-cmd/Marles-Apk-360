import 'dart:async';

import 'package:flutter/material.dart';

import '../almacen.dart';
import '../servicios/nube.dart';
import '../tema.dart';
import '../utiles/medidas.dart';

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
  bool _verClave = false;

  @override
  void dispose() {
    _servidor.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _guardarYProbar() async {
    FocusScope.of(context).unfocus();
    a.servidor = normalizarServidor(_servidor.text);
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
    if (error == null) unawaited(Nube.instancia.subirPendientes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: margenes(context),
        children: [
          const Text('Nube (Cloudflare)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Los datos te los da la guía de instalación.', style: TextStyle(color: Marles.tintaSuave)),
          const SizedBox(height: 12),
          TextField(
            controller: _servidor,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Dirección del servidor',
              hintText: 'https://marles360.tucuenta.workers.dev',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clave,
            obscureText: !_verClave,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Clave de subida',
              suffixIcon: IconButton(
                tooltip: _verClave ? 'Ocultar clave' : 'Mostrar clave',
                icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _verClave = !_verClave),
              ),
            ),
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
                Icon(
                  _bien ? Icons.check_circle : Icons.error_outline,
                  color: _bien ? Marles.turquesaProfundo : Marles.rojo,
                ),
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

/// Deja solo el inicio de la dirección (https://servidor), aunque se pegue
/// sin https://, con / al final o con el enlace de un video. Siempre https:
/// Android no permite enviar la clave por una conexión sin cifrar.
String normalizarServidor(String texto) {
  var t = texto.trim();
  if (t.isEmpty) return '';
  if (!t.contains('://')) t = 'https://$t';
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty) return t;
  return Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : null).toString();
}

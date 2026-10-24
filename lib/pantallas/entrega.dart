import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';

/// Sube el video y muestra el QR que el invitado escanea.
class PantallaEntrega extends StatefulWidget {
  const PantallaEntrega({super.key, required this.video, required this.volverACamara});
  final VideoGrabado video;

  /// true cuando se llega desde la cámara: "Siguiente" vuelve a grabar.
  final bool volverACamara;

  @override
  State<PantallaEntrega> createState() => _PantallaEntregaState();
}

class _PantallaEntregaState extends State<PantallaEntrega> {
  double _avance = 0;
  String? _error;

  VideoGrabado get v => widget.video;

  @override
  void initState() {
    super.initState();
    if (v.estado != EstadoVideo.subido) _subir();
  }

  Future<void> _subir() async {
    if (!Almacen.instancia.nubeLista) {
      setState(() => _error = 'La nube no está configurada. El video quedó guardado en el celular.');
      return;
    }
    setState(() {
      _error = null;
      _avance = 0;
    });
    try {
      await Nube.instancia.subir(v, alAvanzar: (x) {
        if (mounted) setState(() => _avance = x);
      });
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Sin señal. El video quedó guardado y se subirá solo cuando vuelva el internet.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subido = v.estado == EstadoVideo.subido;
    final evento = Almacen.instancia.evento(v.eventoId);
    return Scaffold(
      appBar: AppBar(title: Text(evento?.nombre ?? 'Tu video')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(child: Center(child: subido ? _qr() : _estado())),
              if (!subido && _error != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Compartir por Bluetooth o Quick Share'),
                  onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(v.archivo)])),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar subida'),
                  onPressed: _subir,
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.volverACamara ? 'Listo, siguiente video' : 'Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qr() {
    final url = Nube.instancia.enlaceVideo(v);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Escanea para recibir tu video',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Descárgalo o envíalo por WhatsApp', style: TextStyle(color: Marles.tintaSuave)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: url, size: 280),
        ),
        const SizedBox(height: 16),
        const Text(Marles.lema, style: TextStyle(color: Marles.turquesaProfundo, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _estado() {
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 64, color: Marles.rojo),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Subiendo video…', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 16),
        SizedBox(
          width: 240,
          child: LinearProgressIndicator(value: _avance == 0 ? null : _avance, color: Marles.turquesaProfundo),
        ),
        const SizedBox(height: 8),
        Text('${(_avance * 100).round()}%'),
      ],
    );
  }
}

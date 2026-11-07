import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';
import '../utiles/medidas.dart';

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
    if (v.estado != EstadoVideo.subido) unawaited(_subir());
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
      await Nube.instancia.subir(
        v,
        alAvanzar: (x) {
          if (mounted) setState(() => _avance = x);
        },
      );
      if (mounted) setState(() {});
    } catch (err) {
      if (!mounted) return;
      setState(
        () => _error = switch (err) {
          ErrorServidor(codigo: 401) =>
            'La clave de la nube no coincide con la del servidor. Revísala en Ajustes. El video quedó guardado.',
          ErrorServidor() => 'El servidor tuvo un problema. El video quedó guardado y se subirá más tarde.',
          StateError(:final message) => '$message.',
          _ => 'Sin señal. El video quedó guardado y se subirá solo cuando vuelva el internet.',
        },
      );
    }
  }

  Future<void> _compartir() async {
    if (!File(v.archivo).existsSync()) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(v.archivo, mimeType: 'video/mp4')]));
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar este video?'),
        content: const Text('Se borra del celular y de la nube. El QR dejará de funcionar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final mensajero = ScaffoldMessenger.of(context);
    var enNube = true;
    if (v.estado == EstadoVideo.subido) {
      try {
        await Nube.instancia.borrar(v);
      } catch (_) {
        enNube = false;
      }
    }
    await Almacen.instancia.borrarVideo(v);
    mensajero.showSnackBar(
      SnackBar(
        content: Text(
          enNube
              ? 'Video borrado.'
              : 'Video borrado del celular. Sin señal no se pudo borrar de la nube; allá se borra solo a los 30 días.',
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final subido = v.estado == EstadoVideo.subido;
    final evento = Almacen.instancia.evento(v.eventoId);
    return Scaffold(
      appBar: AppBar(
        title: Text(evento?.nombre ?? 'Tu video', overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (op) => unawaited(op == 'compartir' ? _compartir() : _borrar()),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'compartir', child: Text('Compartir el archivo')),
              PopupMenuItem(value: 'borrar', child: Text('Borrar video')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        // Todo va en una sola columna que se desplaza solo si no cabe. Antes los
        // botones quedaban fijos abajo y, con letra grande en un celular chico,
        // el mensaje quedaba apretado en una franja de una línea.
        child: LayoutBuilder(
          builder: (context, caja) => SingleChildScrollView(
            padding: margenes(context, lado: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: max(0, caja.maxHeight - 32)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox.shrink(),
                  Center(child: subido ? _qr(caja) : _estado()),
                  Padding(padding: const EdgeInsets.only(top: 24), child: _botones(subido)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botones(bool subido) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!subido && _error != null) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Compartir por Bluetooth o Quick Share'),
            onPressed: File(v.archivo).existsSync() ? _compartir : null,
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
    );
  }

  /// El QR ocupa lo que sobra a lo ancho y a lo alto después de los textos y
  /// del botón de abajo, sin pasarse de 440 (en tableta se escanea de más lejos).
  Widget _qr(BoxConstraints caja) {
    // Estos textos los lee el invitado: crecen con la letra del sistema solo
    // hasta 1.5 veces, para que el QR siga cabiendo completo.
    final escala = min(escalaLetra(context), 1.5);
    final textos = 130 * escala;
    final boton = 24 + 56 + 16 * escala;
    final ancho = min(caja.maxWidth, anchoMaximo) - 48 - 32;
    final alto = caja.maxHeight - 32 - 32 - textos - boton;
    final lado = max(min(min(ancho, alto), 440.0), 160.0);
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.5, child: _contenidoQr(lado));
  }

  Widget _contenidoQr(double lado) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Escanea para recibir tu video',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Descárgalo o envíalo por WhatsApp',
          textAlign: TextAlign.center,
          style: TextStyle(color: Marles.tintaSuave),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: QrImageView(data: Nube.instancia.enlaceVideo(v), size: lado, semanticsLabel: 'Código QR del video'),
        ),
        const SizedBox(height: 16),
        const Text(
          Marles.lema,
          textAlign: TextAlign.center,
          style: TextStyle(color: Marles.turquesaProfundo, fontWeight: FontWeight.w500),
        ),
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

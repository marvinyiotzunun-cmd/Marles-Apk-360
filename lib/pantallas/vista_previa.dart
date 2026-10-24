import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/procesador.dart';
import '../tema.dart';
import 'entrega.dart';

/// Procesa el video (marco y canción) y deja aceptarlo o repetirlo.
class PantallaVistaPrevia extends StatefulWidget {
  const PantallaVistaPrevia({super.key, required this.evento, required this.grabado});
  final Evento evento;
  final String grabado;

  @override
  State<PantallaVistaPrevia> createState() => _PantallaVistaPreviaState();
}

class _PantallaVistaPreviaState extends State<PantallaVistaPrevia> {
  final _id = nuevoId();
  late final _salida = '${Almacen.instancia.dirVideos.path}/${widget.evento.id}_$_id.mp4';
  double _avance = 0;
  VideoPlayerController? _video;
  String? _error;

  @override
  void initState() {
    super.initState();
    _procesar();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _procesar() async {
    try {
      final f = await Procesador.procesar(
        grabado: widget.grabado,
        evento: widget.evento,
        salida: _salida,
        alAvanzar: (x) {
          if (mounted) setState(() => _avance = x);
        },
      );
      final v = VideoPlayerController.file(f);
      await v.initialize();
      await v.setLooping(true);
      await v.play();
      if (!mounted) {
        await v.dispose();
        return;
      }
      setState(() => _video = v);
    } on ErrorProcesando catch (err) {
      debugPrint(err.detalle);
      if (mounted) setState(() => _error = 'No se pudo procesar el video.');
    }
  }

  Future<void> _borrar(String ruta) async {
    final f = File(ruta);
    if (await f.exists()) await f.delete();
  }

  Future<void> _repetir() async {
    await _video?.pause();
    await _borrar(widget.grabado);
    await _borrar(_salida);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _aceptar() async {
    await _video?.pause();
    await _borrar(widget.grabado);
    final a = Almacen.instancia;
    final v = VideoGrabado(id: _id, eventoId: widget.evento.id, archivo: _salida, creado: DateTime.now());
    a.videos.add(v);
    await a.guardar();
    if (!mounted) return;
    // Se espera la entrega aquí para que la cámara no se rearme antes de tiempo.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaEntrega(video: v, volverACamara: true)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: v != null
                    ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
                    : _error != null
                        ? Text(_error!, style: const TextStyle(color: Colors.white, fontSize: 18))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Preparando el video…',
                                  style: TextStyle(color: Colors.white, fontSize: 20)),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: 220,
                                child: LinearProgressIndicator(
                                  value: _avance == 0 ? null : _avance,
                                  color: Marles.turquesa,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('${(_avance * 100).round()}%',
                                  style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 52),
                        side: const BorderSide(color: Colors.white54),
                      ),
                      icon: const Icon(Icons.replay),
                      label: const Text('Repetir'),
                      onPressed: _repetir,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Aceptar'),
                      onPressed: v == null ? null : _aceptar,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

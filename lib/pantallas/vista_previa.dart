import 'dart:async';
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

  /// Ruta de la grabación tal como salió de la cámara.
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

  /// true en cuanto se toca Repetir o Aceptar: evita dobles toques.
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_procesar());
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    super.dispose();
  }

  Future<void> _procesar() async {
    try {
      final f = await Procesador.instancia.procesar(
        grabado: widget.grabado,
        evento: widget.evento,
        salida: _salida,
        alAvanzar: (x) {
          if (mounted) setState(() => _avance = x);
        },
      );
      if (!mounted || _cerrando) return;
      final v = VideoPlayerController.file(f);
      await v.initialize();
      await v.setLooping(true);
      await v.play();
      if (!mounted || _cerrando) {
        await v.dispose();
        return;
      }
      setState(() => _video = v);
    } on ErrorProcesando catch (err) {
      debugPrint(err.detalle);
      _mostrarError('No se pudo procesar el video. Toca Repetir para grabar otra vez.');
    } catch (err) {
      debugPrint('$err');
      _mostrarError('No se pudo mostrar el video. Toca Repetir para grabar otra vez.');
    }
  }

  void _mostrarError(String texto) {
    if (mounted && !_cerrando) setState(() => _error = texto);
  }

  Future<void> _borrar(String ruta) async {
    final f = File(ruta);
    if (await f.exists()) await f.delete();
  }

  Future<void> _repetir() async {
    if (_cerrando) return;
    _cerrando = true;
    await Procesador.instancia.cancelar();
    await _video?.pause();
    await _borrar(widget.grabado);
    await _borrar(_salida);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _aceptar() async {
    if (_cerrando) return;
    _cerrando = true;
    await _video?.pause();
    await _borrar(widget.grabado);
    final v = VideoGrabado(id: _id, eventoId: widget.evento.id, archivo: _salida, creado: DateTime.now());
    await Almacen.instancia.agregarVideo(v);
    if (!mounted) return;
    // Se espera la entrega aquí para que la cámara no se rearme antes de tiempo.
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => PantallaEntrega(video: v, volverACamara: true)));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    // El botón atrás del teléfono hace lo mismo que Repetir (no deja archivos sueltos).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) unawaited(_repetir());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: v != null
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: AspectRatio(
                            aspectRatio: v.value.aspectRatio,
                            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: VideoPlayer(v)),
                          ),
                        )
                      : _error != null
                      ? _Mensaje(icono: Icons.error_outline, texto: _error!)
                      : _Procesando(avance: _avance),
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
                        label: const _Etiqueta('Repetir'),
                        onPressed: _repetir,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        // Mientras se prepara el video se ve apagado, pero visible sobre el negro.
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor: Colors.white12,
                          disabledForegroundColor: Colors.white38,
                        ),
                        icon: const Icon(Icons.check),
                        label: const _Etiqueta('Aceptar'),
                        onPressed: v == null ? null : _aceptar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Procesando extends StatelessWidget {
  const _Procesando({required this.avance});
  final double avance;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Preparando el video…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 4),
          const Text(
            'Poniendo el marco y la canción',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              value: avance == 0 ? null : avance,
              color: Marles.turquesa,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 8),
          Text('${(avance * 100).round()}%', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: Colors.white70, size: 56),
          const SizedBox(height: 12),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

/// Texto de los botones de abajo: con letra muy grande se achica para caber
/// entero, en vez de partirse ("Acepta / r").
class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => FittedBox(fit: BoxFit.scaleDown, child: Text(texto));
}

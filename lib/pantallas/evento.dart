import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';
import '../utiles/formato.dart';
import '../utiles/medidas.dart';
import 'camara.dart';
import 'entrega.dart';
import 'evento_form.dart';

class PantallaEvento extends StatelessWidget {
  const PantallaEvento({super.key, required this.evento});
  final Evento evento;

  @override
  Widget build(BuildContext context) {
    final a = Almacen.instancia;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final videos = a.videosDe(evento.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(evento.nombre, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Configurar evento',
                icon: const Icon(Icons.tune),
                onPressed: () => _ir(context, PantallaEventoForm(evento: evento)),
              ),
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (op) async {
                  if (op == 'qr') _qrEvento(context);
                  if (op == 'borrar' && await _confirmar(context)) {
                    await a.borrarEvento(evento);
                    if (context.mounted) Navigator.of(context).pop();
                  }
                },
                itemBuilder: (_) => [
                  if (a.nubeLista) const PopupMenuItem(value: 'qr', child: Text('QR de la galería del evento')),
                  const PopupMenuItem(value: 'borrar', child: Text('Borrar evento')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: margenes(context),
            children: [
              _Resumen(evento: evento),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('Abrir cámara'),
                onPressed: () => _ir(context, PantallaCamara(evento: evento)),
              ),
              const SizedBox(height: 24),
              Text('Videos (${videos.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (videos.isEmpty) const Text('Aún no hay videos.', style: TextStyle(color: Marles.tintaSuave)),
              for (final (i, v) in videos.indexed)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      v.estado == EstadoVideo.subido ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                      color: v.estado == EstadoVideo.subido ? Marles.turquesaProfundo : Marles.rojo,
                    ),
                    title: Text('Video ${videos.length - i}'),
                    subtitle: Text(
                      '${horaCorta(v.creado)} · ${v.estado == EstadoVideo.subido ? 'en línea' : 'pendiente de subir'}',
                    ),
                    trailing: const Icon(Icons.qr_code),
                    onTap: () => _ir(context, PantallaEntrega(video: v, volverACamara: false)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _ir(BuildContext context, Widget p) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => p)));

  void _qrEvento(BuildContext context) {
    final url = Nube.instancia.enlaceEvento(evento.id);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (c) {
          final lado = (MediaQuery.sizeOf(c).width - 128).clamp(120.0, 260.0);
          return AlertDialog(
            title: const Text('Galería del evento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // El QR se ajusta al ancho del diálogo (en celulares chicos no cabían 240):
                  // pantalla menos los márgenes del diálogo (40 + 40) y de su contenido (24 + 24).
                  // El SizedBox fija su tamaño: el diálogo mide su contenido antes de
                  // dibujarlo y QrImageView no se deja medir así.
                  SizedBox.square(
                    dimension: lado,
                    child: QrImageView(data: url, size: lado, semanticsLabel: 'Código QR de la galería'),
                  ),
                  const SizedBox(height: 8),
                  // Espacios invisibles después de "/" y "." para que, si no cabe en una
                  // línea, el enlace se corte ahí y no a mitad de una palabra.
                  Text(
                    url.replaceAllMapped(RegExp('[/.]'), (m) => '${m[0]}\u200B'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Muestra todos los videos ya subidos de este evento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Marles.tintaSuave),
                  ),
                ],
              ),
            ),
            actions: [
              // Para mandarle el enlace a los novios por WhatsApp.
              TextButton.icon(
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartir enlace'),
                onPressed: () => unawaited(SharePlus.instance.share(ShareParams(text: url))),
              ),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmar(BuildContext context) async {
    final sinSubir = Almacen.instancia.videosDe(evento.id).where((v) => v.estado != EstadoVideo.subido).length;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('¿Borrar este evento?'),
            content: Text(
              'Se borran también sus videos guardados en este celular.'
              '${sinSubir == 0 ? '' : ' ${sinSubir == 1 ? 'Un video aún no se ha subido y se perderá.' : '$sinSubir videos aún no se han subido y se perderán.'}'}',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
            ],
          ),
        ) ??
        false;
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.evento});
  final Evento evento;

  @override
  Widget build(BuildContext context) {
    final a = Almacen.instancia;
    // Si el marco o la canción se borraron de la biblioteca, se avisa aquí
    // antes de grabar (si no, el video saldría sin ellos sin decir nada).
    (IconData, String, bool) fila(IconData icono, String? nombre, String? ruta, String vacio) {
      if (nombre == null) return (icono, vacio, false);
      final falta = a.falta(ruta);
      return (icono, falta ? '$nombre (ya no está en la biblioteca)' : nombre, falta);
    }

    final filas = <(IconData, String, bool)>[
      (Icons.event, fechaCorta(evento.fecha), false),
      fila(Icons.filter_frames_outlined, evento.marco, a.rutaMarco(evento.marco), 'Sin marco'),
      fila(Icons.music_note_outlined, evento.cancion, a.rutaCancion(evento.cancion), 'Sin canción'),
      (
        Icons.timer_outlined,
        '${duracionTexto(evento.duracion)} · ${evento.modo == ModoInicio.boton ? 'botón' : 'temporizador'} · '
            '${evento.cuentaRegresiva == 0 ? 'sin cuenta regresiva' : 'cuenta de ${evento.cuentaRegresiva} s'}',
        false,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (icono, texto, aviso) in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      aviso ? Icons.warning_amber_rounded : icono,
                      size: 20,
                      color: aviso ? Marles.rojo : Marles.turquesaProfundo,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(texto, style: aviso ? const TextStyle(color: Marles.rojo) : null),
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

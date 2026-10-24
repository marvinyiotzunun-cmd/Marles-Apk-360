import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';
import 'camara.dart';
import 'entrega.dart';
import 'evento_form.dart';
import 'inicio.dart';

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
            title: Text(evento.nombre),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.tune),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PantallaEventoForm(evento: evento)),
                ),
              ),
              PopupMenuButton<String>(
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
            padding: const EdgeInsets.all(16),
            children: [
              _Resumen(evento: evento),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('Abrir cámara'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PantallaCamara(evento: evento)),
                ),
              ),
              const SizedBox(height: 24),
              Text('Videos (${videos.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (videos.isEmpty)
                const Text('Aún no hay videos.', style: TextStyle(color: Marles.tintaSuave)),
              for (final v in videos)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      v.estado == EstadoVideo.subido ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                      color: v.estado == EstadoVideo.subido ? Marles.turquesaProfundo : Marles.rojo,
                    ),
                    title: Text('Video ${v.id}'),
                    subtitle: Text(
                      '${horaCorta(v.creado)} · '
                      '${v.estado == EstadoVideo.subido ? 'en línea' : 'pendiente de subir'}',
                    ),
                    trailing: const Icon(Icons.qr_code),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PantallaEntrega(video: v, volverACamara: false)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _qrEvento(BuildContext context) {
    final url = Nube.instancia.enlaceEvento(evento.id);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Galería del evento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 240, height: 240, child: QrImageView(data: url)),
            const SizedBox(height: 8),
            SelectableText(url, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<bool> _confirmar(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('¿Borrar este evento?'),
            content: const Text('Se borran también sus videos guardados en este celular.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
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
    final filas = <(IconData, String)>[
      (Icons.event, fechaCorta(evento.fecha)),
      (Icons.filter_frames_outlined, evento.marco ?? 'Sin marco'),
      (Icons.music_note_outlined, evento.cancion ?? 'Sin canción'),
      (Icons.timer_outlined,
          '${evento.duracion} s · ${evento.modo == ModoInicio.boton ? 'botón' : 'temporizador'} · '
              'cuenta ${evento.cuentaRegresiva} s'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (icono, texto) in filas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(icono, size: 20, color: Marles.turquesaProfundo),
                  const SizedBox(width: 12),
                  Expanded(child: Text(texto, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

String horaCorta(DateTime f) =>
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

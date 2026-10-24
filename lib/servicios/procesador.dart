import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import '../almacen.dart';
import '../modelos.dart';

class ErrorProcesando implements Exception {
  ErrorProcesando(this.detalle);
  final String detalle;
  @override
  String toString() => 'No se pudo procesar el video';
}

/// Une el video grabado con el marco y la canción del evento.
/// Entrega un MP4 vertical 1080 x 1920 listo para WhatsApp.
class Procesador {
  static const ancho = 1080, alto = 1920;

  static Future<File> procesar({
    required String grabado,
    required Evento evento,
    required String salida,
    void Function(double avance)? alAvanzar,
  }) async {
    final almacen = Almacen.instancia;
    final info = await _info(grabado);
    final duracion = info.duracion.clamp(1.0, evento.duracion.toDouble());

    final args = <String>['-y', '-i', grabado];
    var siguiente = 1;

    final marco = almacen.rutaMarco(evento.marco);
    int? iMarco;
    if (marco != null && File(marco).existsSync()) {
      args.addAll(['-loop', '1', '-i', marco]);
      iMarco = siguiente++;
    }

    final cancion = almacen.rutaCancion(evento.cancion);
    int? iCancion;
    if (cancion != null && File(cancion).existsSync()) {
      args.addAll(['-ss', '${evento.cancionInicio}', '-stream_loop', '-1', '-i', cancion]);
      iCancion = siguiente++;
    }

    final filtros = <String>[
      '[0:v]scale=$ancho:$alto:force_original_aspect_ratio=increase,'
          'crop=$ancho:$alto,setsar=1,fps=30[base]',
    ];
    if (iMarco != null) {
      filtros.add('[$iMarco:v]scale=$ancho:$alto,format=rgba[marco]');
      filtros.add('[base][marco]overlay=0:0:shortest=1[v]');
    } else {
      filtros.add('[base]null[v]');
    }

    String? audio;
    if (iCancion != null) {
      final inicioFade = (duracion - 1.5).clamp(0, duracion);
      filtros.add('[$iCancion:a]afade=t=out:st=${inicioFade.toStringAsFixed(2)}:d=1.5[musica]');
      if (info.tieneAudio && evento.volumenOriginal > 0) {
        final vol = (evento.volumenOriginal / 100).toStringAsFixed(2);
        filtros.add('[0:a]volume=$vol[original]');
        filtros.add('[musica][original]amix=inputs=2:duration=first:normalize=0[a]');
      } else {
        filtros.add('[musica]anull[a]');
      }
      audio = '[a]';
    } else if (info.tieneAudio) {
      audio = '0:a';
    }

    args.addAll(['-filter_complex', filtros.join(';'), '-map', '[v]']);
    if (audio != null) args.addAll(['-map', audio, '-c:a', 'aac', '-b:a', '160k']);
    args.addAll([
      '-t', duracion.toStringAsFixed(2),
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22',
      '-maxrate', '6M', '-bufsize', '12M', '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      salida,
    ]);

    final listo = Completer<void>();
    final sesion = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (_) => listo.complete(),
      null,
      (estadistica) {
        final ms = estadistica.getTime();
        if (ms > 0) alAvanzar?.call((ms / 1000 / duracion).clamp(0, 1));
      },
    );
    await listo.future;
    final codigo = await sesion.getReturnCode();
    if (!ReturnCode.isSuccess(codigo)) {
      throw ErrorProcesando(await sesion.getAllLogsAsString() ?? 'sin registro');
    }
    return File(salida);
  }

  static Future<({double duracion, bool tieneAudio})> _info(String ruta) async {
    final sesion = await FFprobeKit.getMediaInformation(ruta);
    final info = sesion.getMediaInformation();
    final duracion = double.tryParse(info?.getDuration() ?? '') ?? 0;
    final tieneAudio = info?.getStreams().any((s) => s.getType() == 'audio') ?? false;
    return (duracion: duracion, tieneAudio: tieneAudio);
  }
}

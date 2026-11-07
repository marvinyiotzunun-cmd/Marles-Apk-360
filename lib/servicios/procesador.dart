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
  /// El que usa la app. Las pruebas lo cambian por uno falso.
  static Procesador instancia = Procesador();

  static const ancho = 1080, alto = 1920;

  /// Segundos que tarda la canción en apagarse al final.
  static const fundido = 1.5;

  Future<File> procesar({
    required String grabado,
    required Evento evento,
    required String salida,
    void Function(double avance)? alAvanzar,
  }) async {
    final almacen = Almacen.instancia;
    final info = await _info(grabado);
    // Si no se pudo leer la duración, se usa la del evento (antes salía 1 s).
    final medida = info.duracion > 0 ? info.duracion : evento.duracion.toDouble();
    final duracion = medida.clamp(1.0, evento.duracion.toDouble());
    final marco = almacen.rutaMarco(evento.marco);
    final cancion = almacen.rutaCancion(evento.cancion);

    final args = argumentos(
      grabado: grabado,
      salida: salida,
      duracion: duracion,
      tieneAudio: info.tieneAudio,
      marco: marco != null && File(marco).existsSync() ? marco : null,
      cancion: cancion != null && File(cancion).existsSync() ? cancion : null,
      cancionInicio: evento.cancionInicio,
      volumenOriginal: evento.volumenOriginal,
    );

    final listo = Completer<void>();
    final sesion = await FFmpegKit.executeWithArgumentsAsync(args, (_) => listo.complete(), null, (estadistica) {
      final ms = estadistica.getTime();
      if (ms > 0) alAvanzar?.call((ms / 1000 / duracion).clamp(0, 1));
    });
    await listo.future;
    final codigo = await sesion.getReturnCode();
    if (!ReturnCode.isSuccess(codigo)) {
      throw ErrorProcesando(await sesion.getAllLogsAsString() ?? 'sin registro');
    }
    return File(salida);
  }

  /// Arma la orden para ffmpeg. Está separada para poder probarla con el
  /// ffmpeg de una computadora: es la misma que corre en el celular.
  static List<String> argumentos({
    required String grabado,
    required String salida,
    required double duracion,
    required bool tieneAudio,
    String? marco,
    String? cancion,
    int cancionInicio = 0,
    int volumenOriginal = 0,
  }) {
    final args = <String>['-y', '-i', grabado];
    var siguiente = 1;

    int? iMarco;
    if (marco != null) {
      args.addAll(['-loop', '1', '-i', marco]);
      iMarco = siguiente++;
    }

    int? iCancion;
    if (cancion != null) {
      // La canción se repite si es más corta que el video.
      args.addAll(['-stream_loop', '-1', '-ss', '${cancionInicio.clamp(0, 3600)}', '-i', cancion]);
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
      final inicioFade = (duracion - fundido).clamp(0, duracion);
      filtros.add('[$iCancion:a]afade=t=out:st=${inicioFade.toStringAsFixed(2)}:d=$fundido[musica]');
      if (tieneAudio && volumenOriginal > 0) {
        final vol = (volumenOriginal.clamp(0, 100) / 100).toStringAsFixed(2);
        filtros.add('[0:a]volume=$vol[original]');
        filtros.add('[musica][original]amix=inputs=2:duration=first:normalize=0[a]');
      } else {
        filtros.add('[musica]anull[a]');
      }
      audio = '[a]';
    } else if (tieneAudio) {
      audio = '0:a';
    }

    args.addAll(['-filter_complex', filtros.join(';'), '-map', '[v]']);
    if (audio != null) args.addAll(['-map', audio, '-c:a', 'aac', '-b:a', '160k']);
    args.addAll([
      ...['-t', duracion.toStringAsFixed(2)],
      ...['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22'],
      ...['-maxrate', '6M', '-bufsize', '12M', '-pix_fmt', 'yuv420p'],
      ...['-movflags', '+faststart'],
      salida,
    ]);
    return args;
  }

  /// Detiene el procesado en curso (por ejemplo al tocar Repetir).
  Future<void> cancelar() => FFmpegKit.cancel();

  static Future<({double duracion, bool tieneAudio})> _info(String ruta) async {
    final sesion = await FFprobeKit.getMediaInformation(ruta);
    final info = sesion.getMediaInformation();
    final duracion = double.tryParse(info?.getDuration() ?? '') ?? 0;
    final tieneAudio = info?.getStreams().any((s) => s.getType() == 'audio') ?? false;
    return (duracion: duracion, tieneAudio: tieneAudio);
  }
}

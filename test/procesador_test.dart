// Corre la misma orden de ffmpeg que usa la app (en el celular la ejecuta
// ffmpeg-kit, que es ffmpeg) con el ffmpeg de la computadora, y revisa el
// video que sale. Si la computadora no tiene ffmpeg, se salta.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/servicios/procesador.dart';

final bool _hayFfmpeg = () {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0 &&
        Process.runSync('ffprobe', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

late Directory _dir;
String _ruta(String nombre) => '${_dir.path}/$nombre';

Future<String> _ffmpeg(List<String> args) async {
  final r = await Process.run('ffmpeg', ['-hide_banner', '-nostdin', ...args]);
  if (r.exitCode != 0) fail('ffmpeg falló (${r.exitCode}):\n${r.stderr}');
  return r.stderr as String;
}

/// Lo que dice ffprobe del archivo: pistas y duración.
Future<({Map<String, dynamic>? video, Map<String, dynamic>? audio, double duracion})> _sondear(String ruta) async {
  final r = await Process.run('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', ruta]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  final pistas = (j['streams'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic>? de(String tipo) => pistas.where((p) => p['codec_type'] == tipo).firstOrNull;
  return (video: de('video'), audio: de('audio'), duracion: double.parse(j['format']['duration'] as String));
}

/// Volumen medio (dB) de un tramo del audio, opcionalmente solo de una nota.
Future<double> _volumen(String ruta, {required double desde, double largo = 0.3, int? nota}) async {
  final filtro = [if (nota != null) 'bandpass=f=$nota:width_type=h:width=60', 'volumedetect'].join(',');
  final log = await _ffmpeg(['-ss', '$desde', '-t', '$largo', '-i', ruta, '-map', '0:a', '-af', filtro, '-f', 'null', '-']);
  final m = RegExp(r'mean_volume: (-?[\d.]+|-inf) dB').firstMatch(log);
  expect(m, isNotNull, reason: log);
  return m!.group(1) == '-inf' ? -200 : double.parse(m.group(1)!);
}

/// Un cuadro del video, achicado a 54 x 96, en gris o en color (r, g, b).
Future<Uint8List> _cuadro(String ruta, {required double en, bool color = false}) async {
  final salida = _ruta('cuadro_${DateTime.now().microsecondsSinceEpoch}.raw');
  await _ffmpeg([
    ...['-ss', '$en', '-i', ruta, '-frames:v', '1', '-vf', 'scale=54:96'],
    ...['-pix_fmt', color ? 'rgb24' : 'gray', '-f', 'rawvideo', '-y', salida],
  ]);
  return File(salida).readAsBytes();
}

double _promedio(Uint8List gris, {required bool Function(int x, int y) donde}) {
  var suma = 0, n = 0;
  for (var y = 0; y < 96; y++) {
    for (var x = 0; x < 54; x++) {
      if (donde(x, y)) {
        suma += gris[y * 54 + x];
        n++;
      }
    }
  }
  return suma / n;
}

/// Las cajas de primer nivel del MP4, en orden (ftyp, moov, mdat...).
List<String> _cajas(String ruta) {
  final f = File(ruta).openSync();
  final cajas = <String>[];
  try {
    var pos = 0;
    final largo = f.lengthSync();
    while (pos + 8 <= largo) {
      f.setPositionSync(pos);
      final cab = ByteData.sublistView(f.readSync(16));
      var tam = cab.getUint32(0);
      cajas.add(String.fromCharCodes(cab.buffer.asUint8List(cab.offsetInBytes + 4, 4)));
      if (tam == 1) tam = cab.getUint64(8);
      if (tam < 8) break;
      pos += tam;
    }
  } finally {
    f.closeSync();
  }
  return cajas;
}

/// Procesa con la misma orden que arma la app y devuelve la ruta del resultado.
Future<String> _procesar(
  String grabado, {
  required double duracion,
  required bool tieneAudio,
  String? marco,
  String? cancion,
  int cancionInicio = 0,
  int volumenOriginal = 0,
}) async {
  final salida = _ruta('final_${DateTime.now().microsecondsSinceEpoch}.mp4');
  final args = Procesador.argumentos(
    grabado: grabado,
    salida: salida,
    duracion: duracion,
    tieneAudio: tieneAudio,
    marco: marco,
    cancion: cancion,
    cancionInicio: cancionInicio,
    volumenOriginal: volumenOriginal,
  );
  await _ffmpeg(['-loglevel', 'error', ...args]);
  return salida;
}

/// Revisa lo que necesita WhatsApp y la página de descarga.
Future<void> _esVideoFinal(String ruta, {required double duracion, required bool conAudio}) async {
  final s = await _sondear(ruta);
  expect(s.video, isNotNull);
  expect(s.video!['codec_name'], 'h264');
  expect(s.video!['width'], Procesador.ancho);
  expect(s.video!['height'], Procesador.alto);
  expect(s.video!['pix_fmt'], 'yuv420p');
  expect(s.video!['r_frame_rate'], '30/1');
  // Sin giro guardado aparte: el video ya sale derecho.
  expect(s.video!['side_data_list'], isNull);
  expect(s.duracion, closeTo(duracion, 0.15));
  if (conAudio) {
    expect(s.audio, isNotNull);
    expect(s.audio!['codec_name'], 'aac');
    expect(double.parse(s.audio!['duration'] as String), closeTo(duracion, 0.15));
  } else {
    expect(s.audio, isNull);
  }
  // +faststart: el índice va antes del video, así el invitado lo ve sin
  // esperar a que se descargue entero.
  final cajas = _cajas(ruta);
  expect(cajas.indexOf('moov'), lessThan(cajas.indexOf('mdat')), reason: '$cajas');
}

void main() {
  final saltar = _hayFfmpeg ? null : 'Esta computadora no tiene ffmpeg';

  // Grabaciones de prueba, como las que deja la cámara.
  late String acostado, conMicrofono, sinMicrofono, deCelular, cancion, marco;

  setUpAll(() async {
    if (!_hayFfmpeg) return;
    _dir = await Directory.systemTemp.createTemp('marles_ffmpeg');
    const q = ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p'];
    // Mitad izquierda blanca y derecha negra, para notar si sale girado.
    const mitades = 'color=c=white:s=1920x1080:r=30,drawbox=x=960:y=0:w=960:h=1080:color=black:t=fill';
    acostado = _ruta('acostado.mp4');
    await _ffmpeg(['-loglevel', 'error', '-f', 'lavfi', '-i', mitades, '-t', '3', ...q, acostado]);
    // Así graba el celular de pie: el cuadro va acostado y el giro va aparte.
    deCelular = _ruta('de_celular.mp4');
    await _ffmpeg(['-loglevel', 'error', '-display_rotation', '90', '-i', acostado, '-c', 'copy', deCelular]);

    conMicrofono = _ruta('con_microfono.mp4');
    await _ffmpeg([
      ...['-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=0x2060C0:s=1080x1920:r=30'],
      ...['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000', '-t', '5', ...q, '-c:a', 'aac', conMicrofono],
    ]);
    sinMicrofono = _ruta('sin_microfono.mp4');
    await _ffmpeg(['-loglevel', 'error', '-i', conMicrofono, '-an', '-c', 'copy', sinMicrofono]);

    // Canción de 2 segundos (más corta que los videos) en MP3.
    cancion = _ruta('cancion.mp3');
    await _ffmpeg(['-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=44100', '-t', '2', cancion]);

    // Marco PNG con borde rojo y el centro transparente.
    marco = _ruta('marco.png');
    await _ffmpeg([
      ...['-loglevel', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=1080x1920,format=rgba'],
      ...['-vf', "geq=r=255:g=0:b=0:a='if(lt(X,60)+gt(X,1019)+lt(Y,60)+gt(Y,1859),255,0)'"],
      ...['-frames:v', '1', marco],
    ]);
  });

  tearDownAll(() async {
    if (_hayFfmpeg) await _dir.delete(recursive: true);
  });

  test('sin marco ni canción: vertical, recortado al tiempo del evento y con su sonido', skip: saltar, () async {
    final v = await _procesar(conMicrofono, duracion: 3, tieneAudio: true);
    await _esVideoFinal(v, duracion: 3, conAudio: true);
    expect(await _volumen(v, desde: 1, nota: 440), greaterThan(-30));
  });

  test('un video acostado se recorta al centro sin deformarse', skip: saltar, () async {
    final v = await _procesar(acostado, duracion: 2, tieneAudio: false);
    await _esVideoFinal(v, duracion: 2, conAudio: false);
    // Del centro del cuadro acostado: mitad blanca a la izquierda, negra a la derecha.
    final gris = await _cuadro(v, en: 1);
    expect(_promedio(gris, donde: (x, y) => x < 20), greaterThan(200));
    expect(_promedio(gris, donde: (x, y) => x > 34), lessThan(50));
  });

  test('un video del celular de pie sale derecho (aplica el giro que guarda la cámara)', skip: saltar, () async {
    final s = await _sondear(deCelular);
    expect(s.video!['side_data_list'], isNotNull, reason: 'la grabación de prueba debe traer el giro');

    final v = await _procesar(deCelular, duracion: 2, tieneAudio: false);
    await _esVideoFinal(v, duracion: 2, conAudio: false);
    // Girado, lo que era izquierda/derecha queda arriba/abajo, y no a los lados.
    final gris = await _cuadro(v, en: 1);
    final arriba = _promedio(gris, donde: (x, y) => y < 40);
    final abajo = _promedio(gris, donde: (x, y) => y > 56);
    expect((arriba - abajo).abs(), greaterThan(150));
    expect((_promedio(gris, donde: (x, y) => x < 27) - _promedio(gris, donde: (x, y) => x >= 27)).abs(), lessThan(30));
  });

  test('con marco y canción corta: el marco encima, la canción se repite y se apaga al final', skip: saltar, () async {
    final v = await _procesar(conMicrofono, duracion: 4.5, tieneAudio: true, marco: marco, cancion: cancion);
    await _esVideoFinal(v, duracion: 4.5, conAudio: true);

    final rgb = await _cuadro(v, en: 2, color: true);
    List<int> pixel(int x, int y) => rgb.sublist((y * 54 + x) * 3, (y * 54 + x) * 3 + 3);
    final borde = pixel(1, 1), centro = pixel(27, 48);
    expect(borde[0], greaterThan(200), reason: 'borde $borde');
    expect(borde[1] + borde[2], lessThan(80), reason: 'borde $borde');
    // El centro deja ver el video (azul), el marco ahí es transparente.
    expect(centro[2], greaterThan(150), reason: 'centro $centro');
    expect(centro[0], lessThan(80), reason: 'centro $centro');

    // La canción (2 s) sigue sonando después de terminar una vez.
    final medio = await _volumen(v, desde: 2.3, nota: 660);
    expect(medio, greaterThan(-30));
    expect(await _volumen(v, desde: 0.5, nota: 660), closeTo(medio, 3));
    // Se apaga en el último segundo y medio.
    expect(await _volumen(v, desde: 4.15, nota: 660), lessThan(medio - 10));
    // Volumen original en 0: el sonido de la cámara (440 Hz) no se oye.
    expect(await _volumen(v, desde: 1, nota: 440), lessThan(medio - 10));
  });

  test('con volumen original, se oyen la canción y la cámara', skip: saltar, () async {
    final sin = await _procesar(conMicrofono, duracion: 3, tieneAudio: true, cancion: cancion);
    final con = await _procesar(conMicrofono, duracion: 3, tieneAudio: true, cancion: cancion, volumenOriginal: 100);
    await _esVideoFinal(con, duracion: 3, conAudio: true);
    expect(await _volumen(con, desde: 1, nota: 440), greaterThan(await _volumen(sin, desde: 1, nota: 440) + 8));
    expect(await _volumen(con, desde: 1, nota: 660), closeTo(await _volumen(sin, desde: 1, nota: 660), 3));
  });

  test('una grabación sin sonido funciona con y sin canción', skip: saltar, () async {
    final mudo = await _procesar(sinMicrofono, duracion: 3, tieneAudio: false);
    await _esVideoFinal(mudo, duracion: 3, conAudio: false);

    // Aunque el evento pida mezclar el sonido original, no hay cuál: solo la canción.
    final conCancion = await _procesar(sinMicrofono, duracion: 3, tieneAudio: false, cancion: cancion, volumenOriginal: 60);
    await _esVideoFinal(conCancion, duracion: 3, conAudio: true);
    expect(await _volumen(conCancion, desde: 1, nota: 660), greaterThan(-30));
  });

  test('si la canción empieza después de su final, igual suena', skip: saltar, () async {
    final v = await _procesar(conMicrofono, duracion: 3, tieneAudio: true, cancion: cancion, cancionInicio: 300);
    await _esVideoFinal(v, duracion: 3, conAudio: true);
    expect(await _volumen(v, desde: 0.5, nota: 660), greaterThan(-30));
  });

  test('los números raros no rompen la orden', () {
    final args = Procesador.argumentos(
      grabado: '/g.mp4',
      salida: '/s.mp4',
      duracion: 1.23456,
      tieneAudio: true,
      cancion: '/c.mp3',
      cancionInicio: -5,
      volumenOriginal: 250,
    );
    expect(args.sublist(args.indexOf('-ss'), args.indexOf('-ss') + 2), ['-ss', '0']);
    expect(args.sublist(args.indexOf('-t'), args.indexOf('-t') + 2), ['-t', '1.23']);
    final filtros = args[args.indexOf('-filter_complex') + 1];
    expect(filtros, contains('volume=1.00'));
    // El fundido nunca empieza antes del inicio.
    expect(filtros, contains('afade=t=out:st=0.00:'));
    expect(args.last, '/s.mp4');
  });
}

// La app subiendo de verdad al servidor (el mismo código que corre en
// Cloudflare, levantado en la computadora con Miniflare). Solo corre si se
// le dice dónde está el servidor:
//
//   cd servidor && node herramientas/servir.mjs &
//   MARLES_E2E_URL=http://127.0.0.1:8787 MARLES_E2E_CLAVE=clave-de-prueba-local \
//     flutter test test/nube_e2e_test.dart
//
// GitHub Actions la corre en cada compilación.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marles360/almacen.dart';
import 'package:marles360/modelos.dart';
import 'package:marles360/servicios/nube.dart';

final _url = Platform.environment['MARLES_E2E_URL'];
final _clave = Platform.environment['MARLES_E2E_CLAVE'];

void main() {
  final saltar = _url == null || _clave == null ? 'Falta MARLES_E2E_URL y MARLES_E2E_CLAVE' : null;
  final a = Almacen.instancia;
  late Directory carpeta;
  late Evento evento;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('marles_e2e');
    await a.cargar(carpeta: carpeta);
    a.servidor = _url ?? '';
    a.clave = _clave ?? '';
    evento = Evento(id: nuevoId(), nombre: 'Boda de Ana & Luis <3', fecha: DateTime(2026, 11, 14));
    a.eventos.add(evento);
  });

  tearDown(() async {
    await a.guardar();
    await carpeta.delete(recursive: true);
  });

  /// Un "video" con bytes al azar, para notar si algo se corta o se mezcla.
  Future<VideoGrabado> video(int tam) async {
    final bytes = Uint8List(tam);
    final r = Random(tam);
    for (var i = 0; i < tam; i++) {
      bytes[i] = r.nextInt(256);
    }
    final id = nuevoId();
    final f = File('${a.dirVideos.path}/$id.mp4')..writeAsBytesSync(bytes);
    final v = VideoGrabado(id: id, eventoId: evento.id, archivo: f.path, creado: DateTime.now());
    await a.agregarVideo(v);
    return v;
  }

  Future<Uint8List> bajar(VideoGrabado v) async {
    final r = await http.get(Uri.parse('$_url/f/${v.eventoId}/${v.id}.mp4'));
    expect(r.statusCode, 200);
    return r.bodyBytes;
  }

  test('sube un video y el invitado lo ve y lo descarga', skip: saltar, () async {
    final nube = Nube();
    final v = await video(300 * 1024);
    final avances = <double>[];
    await nube.subir(v, alAvanzar: avances.add);

    expect(v.estado, EstadoVideo.subido);
    expect(avances, isNotEmpty);
    expect(avances.last, closeTo(1, 1e-9));
    for (var i = 1; i < avances.length; i++) {
      expect(avances[i], greaterThanOrEqualTo(avances[i - 1]));
    }
    expect(a.pendientes, isEmpty);

    final pagina = await http.get(Uri.parse(nube.enlaceVideo(v)));
    expect(pagina.statusCode, 200);
    expect(pagina.body, contains('Enviar por WhatsApp'));
    // El nombre del evento llega escapado, sin abrir etiquetas.
    expect(pagina.body, contains('Boda de Ana &amp; Luis &lt;3'));
    expect(pagina.body, isNot(contains('Luis <3')));

    expect(await bajar(v), await File(v.archivo).readAsBytes());

    final galeria = await http.get(Uri.parse(nube.enlaceEvento(evento.id)));
    expect(galeria.statusCode, 200);
    expect(galeria.body, contains('Boda de Ana &amp; Luis &lt;3'));
    expect(galeria.body, contains(v.id));
  });

  test('un video grande se sube por partes y llega entero', skip: saltar, () async {
    // Igual que en el celular con un video de más de 90 MB, pero en pequeño:
    // 11 MB en partes de 5 MB (R2 pide al menos 5 MB por parte, menos la última).
    final nube = Nube(limiteDirecto: 1024 * 1024, tamParte: 5 * 1024 * 1024);
    final v = await video(11 * 1024 * 1024);
    final avances = <double>[];
    await nube.subir(v, alAvanzar: avances.add);

    expect(v.estado, EstadoVideo.subido);
    expect(avances.last, closeTo(1, 1e-9));
    expect(await bajar(v), await File(v.archivo).readAsBytes());
  });

  test('dos subidas del mismo video al mismo tiempo son una sola', skip: saltar, () async {
    final nube = Nube();
    final v = await video(64 * 1024);
    final primera = nube.subir(v);
    final segunda = nube.subir(v);
    expect(identical(primera, segunda), isTrue);
    await Future.wait([primera, segunda]);
    expect(v.estado, EstadoVideo.subido);
  });

  test('subirPendientes sube lo que quedó sin señal', skip: saltar, () async {
    final nube = Nube();
    final v1 = await video(10 * 1024);
    final v2 = await video(20 * 1024);
    expect(a.pendientes, hasLength(2));
    expect(await nube.subirPendientes(), 2);
    expect(a.pendientes, isEmpty);
    expect(await bajar(v1), await File(v1.archivo).readAsBytes());
    expect(await bajar(v2), await File(v2.archivo).readAsBytes());

    // Lo subido queda guardado: al abrir la app de nuevo no se vuelve a subir.
    await a.guardar();
    await a.cargar(carpeta: carpeta);
    expect(a.pendientes, isEmpty);
  });

  test('con la clave equivocada no sube y el video queda pendiente', skip: saltar, () async {
    final nube = Nube();
    final v = await video(10 * 1024);
    a.clave = 'otra-clave-que-no-es';
    expect(await nube.probar(), 'La clave no coincide con la del servidor.');
    await expectLater(nube.subir(v), throwsA(isA<ErrorServidor>().having((e) => e.codigo, 'código', 401)));
    expect(v.estado, EstadoVideo.pendiente);
    expect(a.pendientes, [v]);
    expect(await nube.subirPendientes(), 0);
  });

  test('Guardar y probar avisa claro qué pasa', skip: saltar, () async {
    final nube = Nube();
    expect(await nube.probar(), isNull);

    // Un servidor que no es el de Marles 360.
    a.servidor = '$_url/f';
    expect(await nube.probar(), contains('no es el servidor de Marles 360'));

    // Nadie escuchando en ese puerto.
    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final puerto = libre.port;
    await libre.close();
    a.servidor = 'http://127.0.0.1:$puerto';
    expect(await nube.probar(), 'No se pudo conectar. Revisa la dirección y que haya internet.');
  });

  test('borrar quita el video de la nube', skip: saltar, () async {
    final nube = Nube();
    final v = await video(10 * 1024);
    await nube.subir(v);
    expect((await http.get(Uri.parse(nube.enlaceVideo(v)))).statusCode, 200);

    await nube.borrar(v);
    expect((await http.get(Uri.parse(nube.enlaceVideo(v)))).statusCode, 404);
    expect((await http.get(Uri.parse('$_url/f/${v.eventoId}/${v.id}.mp4'))).statusCode, 404);
    // Borrar dos veces no es un error (el invitado tocó dos veces).
    await nube.borrar(v);
  });
}

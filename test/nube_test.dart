// Cómo reacciona la subida de pendientes a un servidor que falla, con un
// servidor de mentira en la computadora (no hace falta el de Cloudflare).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/almacen.dart';
import 'package:marles360/modelos.dart';
import 'package:marles360/servicios/nube.dart';

void main() {
  final a = Almacen.instancia;
  late Directory carpeta;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('marles_nube');
    await a.cargar(carpeta: carpeta);
    a.clave = 'una-clave-larga';
    a.eventos.add(Evento(id: 'abc234', nombre: 'Boda', fecha: DateTime(2026, 11, 14)));
  });

  tearDown(() async {
    await a.guardar();
    await carpeta.delete(recursive: true);
  });

  /// Tres videos pendientes con su archivo.
  Future<List<VideoGrabado>> pendientes() async {
    final lista = <VideoGrabado>[];
    for (final id in ['uno22222', 'dos22222', 'tres2222']) {
      final f = File('${a.dirVideos.path}/abc234_$id.mp4')..writeAsBytesSync(List.filled(2048, 1));
      final v = VideoGrabado(id: id, eventoId: 'abc234', archivo: f.path, creado: DateTime.now());
      await a.agregarVideo(v);
      lista.add(v);
    }
    return lista;
  }

  /// Servidor que responde [codigo] a todo y cuenta los pedidos.
  Future<(HttpServer, List<String>)> servidor(int codigo) async {
    final pedidos = <String>[];
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) async {
      pedidos.add('${r.method} ${r.uri.path}');
      await r.drain<void>();
      r.response
        ..statusCode = codigo
        ..write(codigo == 200 ? '{"ok":true}' : 'Clave incorrecta');
      await r.response.close();
    });
    a.servidor = 'http://127.0.0.1:${s.port}';
    addTearDown(() => s.close(force: true));
    return (s, pedidos);
  }

  test('sin señal deja de intentar al primer video (no espera uno por uno)', () async {
    await pendientes();
    // Acepta la conexión y la corta, como una red que se cae.
    var conexiones = 0;
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((c) {
      conexiones++;
      c.destroy();
    });
    addTearDown(s.close);
    a.servidor = 'http://127.0.0.1:${s.port}';

    expect(await Nube().subirPendientes(), 0);
    expect(conexiones, 1);
    expect(a.pendientes, hasLength(3));
  });

  test('con la clave equivocada deja de intentar al primer video', () async {
    await pendientes();
    final (_, pedidos) = await servidor(401);
    expect(await Nube().subirPendientes(), 0);
    expect(pedidos, ['PUT /api/evento/abc234']);
    expect(a.pendientes.every((v) => v.estado == EstadoVideo.pendiente), isTrue);
  });

  test('un video sin archivo no frena a los demás', () async {
    final videos = await pendientes();
    File(videos.first.archivo).deleteSync();
    final (_, pedidos) = await servidor(200);
    expect(await Nube().subirPendientes(), 2);
    expect(pedidos, [
      'PUT /api/evento/abc234',
      'PUT /api/subir/abc234/dos22222',
      'PUT /api/evento/abc234',
      'PUT /api/subir/abc234/tres2222',
    ]);
    expect(a.pendientes.single.id, 'uno22222');
  });

  test('sin nube configurada no intenta nada', () async {
    await pendientes();
    a.servidor = '';
    expect(await Nube().subirPendientes(), 0);
    await expectLater(Nube().subir(a.pendientes.first), throwsStateError);
  });

  test('los enlaces no llevan / doble aunque la dirección termine en /', () {
    a.servidor = 'https://marles360.ejemplo.workers.dev//';
    final v = VideoGrabado(id: 'uno22222', eventoId: 'abc234', archivo: '/x.mp4', creado: DateTime(2026));
    expect(Nube().enlaceVideo(v), 'https://marles360.ejemplo.workers.dev/v/abc234/uno22222');
    expect(Nube().enlaceEvento('abc234'), 'https://marles360.ejemplo.workers.dev/e/abc234');
  });
}

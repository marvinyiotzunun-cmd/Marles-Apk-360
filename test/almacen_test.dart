// Lo que la app guarda en el celular: que no se pierda nada al cerrarla, que
// un archivo dañado no la deje sin abrir y que la limpieza de 30 días borre
// solo lo que debe.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/almacen.dart';
import 'package:marles360/modelos.dart';

void main() {
  // Para FileImage.evict al eliminar un marco.
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = Almacen.instancia;
  late Directory carpeta;
  final ahora = DateTime.now();

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('marles_almacen');
    await a.cargar(carpeta: carpeta);
  });

  tearDown(() async {
    await a.guardar();
    await carpeta.delete(recursive: true);
  });

  File datos() => File('${carpeta.path}/datos.json');

  /// Un video con su archivo en la carpeta de videos.
  VideoGrabado video(String id, {required DateTime creado, EstadoVideo estado = EstadoVideo.pendiente}) {
    final f = File('${a.dirVideos.path}/abc234_$id.mp4')..writeAsBytesSync([1, 2, 3]);
    f.setLastModifiedSync(creado);
    return VideoGrabado(id: id, eventoId: 'abc234', archivo: f.path, creado: creado, estado: estado);
  }

  test('todo se guarda y se lee igual al abrir la app de nuevo', () async {
    a.servidor = 'https://marles360.ejemplo.workers.dev';
    a.clave = 'una-clave-muy-larga';
    final e = Evento(id: 'abc234', nombre: 'XV de Sofía', fecha: DateTime(2026, 12, 5), marco: 'xv.png', duracion: 20);
    a.eventos.add(e);
    await a.agregarVideo(video('v1v1v1v1', creado: ahora, estado: EstadoVideo.subido));
    await a.agregarVideo(video('v2v2v2v2', creado: ahora));

    await a.cargar(carpeta: carpeta);
    expect(a.servidor, 'https://marles360.ejemplo.workers.dev');
    expect(a.clave, 'una-clave-muy-larga');
    expect(a.eventos.single.toJson(), e.toJson());
    expect(a.videos.map((v) => v.id), ['v1v1v1v1', 'v2v2v2v2']);
    expect(a.pendientes.single.id, 'v2v2v2v2');
    // No queda el archivo temporal del guardado.
    expect(File('${datos().path}.tmp').existsSync(), isFalse);
  });

  test('un video que se estaba subiendo al cerrar la app queda pendiente', () async {
    final v = video('v1v1v1v1', creado: ahora, estado: EstadoVideo.subiendo);
    await a.agregarVideo(v);
    await a.cargar(carpeta: carpeta);
    expect(a.pendientes.single.estado, EstadoVideo.pendiente);
  });

  test('muchos guardados seguidos no se pisan', () async {
    final esperas = <Future<void>>[];
    for (var i = 0; i < 25; i++) {
      a.eventos.add(Evento(id: 'ev${i}xyz', nombre: 'Evento $i', fecha: ahora));
      esperas.add(a.guardar());
    }
    await Future.wait(esperas);
    await a.cargar(carpeta: carpeta);
    expect(a.eventos, hasLength(25));
  });

  test('si datos.json se daña, la app abre igual y guarda una copia', () async {
    datos().writeAsStringSync('{"servidor": "https://x", "eventos": [');
    final suelto = video('v9v9v9v9', creado: ahora.subtract(const Duration(days: 3)));

    await a.cargar(carpeta: carpeta);
    expect(a.eventos, isEmpty);
    expect(a.videos, isEmpty);
    expect(File('${datos().path}.danado').readAsStringSync(), startsWith('{"servidor"'));
    // El video de un invitado que no alcanzó a subirse no se borra por eso.
    expect(File(suelto.archivo).existsSync(), isTrue);

    // Y se puede seguir trabajando.
    a.eventos.add(Evento(id: 'nuevo234', nombre: 'Nuevo', fecha: ahora));
    await a.guardar();
    await a.cargar(carpeta: carpeta);
    expect(a.eventos.single.nombre, 'Nuevo');
    expect(File(suelto.archivo).existsSync(), isTrue);
  });

  test('a los 30 días se borran los subidos, nunca los pendientes', () async {
    final hace = ahora.subtract(const Duration(days: diasGuardado + 1));
    final viejoSubido = video('aaaa2222', creado: hace, estado: EstadoVideo.subido);
    final viejoPendiente = video('bbbb2222', creado: hace.subtract(const Duration(days: 20)));
    final recienSubido = video('cccc2222', creado: ahora.subtract(const Duration(days: 29)), estado: EstadoVideo.subido);
    a.videos.addAll([viejoSubido, viejoPendiente, recienSubido]);
    await a.guardar();

    await a.cargar(carpeta: carpeta);
    expect(a.videos.map((v) => v.id), ['bbbb2222', 'cccc2222']);
    expect(File(viejoSubido.archivo).existsSync(), isFalse);
    expect(File(viejoPendiente.archivo).existsSync(), isTrue);
    expect(File(recienSubido.archivo).existsSync(), isTrue);
    // La lista ya limpia queda guardada.
    final guardado = jsonDecode(datos().readAsStringSync()) as Map<String, dynamic>;
    expect((guardado['videos'] as List).map((v) => v['id']), ['bbbb2222', 'cccc2222']);
  });

  test('los archivos sueltos se limpian sin tocar lo que se está grabando', () async {
    File suelto(String nombre, Duration edad) =>
        File('${a.dirVideos.path}/$nombre')
          ..writeAsBytesSync([0])
          ..setLastModifiedSync(ahora.subtract(edad));
    final crudoViejo = suelto('crudo_aaaa2222.mp4', const Duration(days: 2));
    final crudoNuevo = suelto('crudo_bbbb2222.mp4', const Duration(minutes: 5));
    final terminadoViejo = suelto('abc234_cccc2222.mp4', const Duration(days: diasGuardado + 2));
    final terminadoReciente = suelto('abc234_dddd2222.mp4', const Duration(days: 3));

    await a.cargar(carpeta: carpeta);
    expect(crudoViejo.existsSync(), isFalse);
    expect(crudoNuevo.existsSync(), isTrue);
    expect(terminadoViejo.existsSync(), isFalse);
    expect(terminadoReciente.existsSync(), isTrue);
  });

  test('si la carpeta de la app cambió de lugar, encuentra los videos por nombre', () async {
    final v = video('v1v1v1v1', creado: ahora);
    datos().writeAsStringSync(
      jsonEncode({
        'servidor': '',
        'clave': '',
        'eventos': [],
        'videos': [
          {...v.toJson(), 'archivo': '/var/mobile/Containers/Data/Application/VIEJA/videos/abc234_v1v1v1v1.mp4'},
        ],
      }),
    );
    await a.cargar(carpeta: carpeta);
    expect(a.videos.single.archivo, v.archivo);
  });

  test('borrar un evento borra sus videos y deja los de otros eventos', () async {
    final e1 = Evento(id: 'abc234', nombre: 'Uno', fecha: ahora);
    final e2 = Evento(id: 'otro234', nombre: 'Dos', fecha: ahora);
    a.eventos.addAll([e1, e2]);
    final propio = video('v1v1v1v1', creado: ahora);
    final f = File('${a.dirVideos.path}/otro234_v2v2v2v2.mp4')..writeAsBytesSync([1]);
    final ajeno = VideoGrabado(id: 'v2v2v2v2', eventoId: 'otro234', archivo: f.path, creado: ahora);
    a.videos.addAll([propio, ajeno]);

    await a.borrarEvento(e1);
    expect(a.eventos, [e2]);
    expect(a.videos, [ajeno]);
    expect(File(propio.archivo).existsSync(), isFalse);
    expect(f.existsSync(), isTrue);
  });

  test('importar con el mismo nombre agrega (2), (3)...', () async {
    final origen = Directory('${carpeta.path}/descargas')..createSync();
    File('${origen.path}/marco.boda.png').writeAsBytesSync([1]);
    File('${origen.path}/sin_extension').writeAsBytesSync([2]);

    expect(await a.importar('${origen.path}/marco.boda.png', a.dirMarcos), 'marco.boda.png');
    expect(await a.importar('${origen.path}/marco.boda.png', a.dirMarcos), 'marco.boda (2).png');
    expect(await a.importar('${origen.path}/marco.boda.png', a.dirMarcos), 'marco.boda (3).png');
    expect(await a.importar('${origen.path}/sin_extension', a.dirMusica), 'sin_extension');
    expect(await a.importar('${origen.path}/sin_extension', a.dirMusica), 'sin_extension (2)');
    expect(a.marcos.map((f) => nombreDe(f.path)), ['marco.boda (2).png', 'marco.boda (3).png', 'marco.boda.png']);

    await a.eliminar(a.marcos.first);
    expect(a.marcos, hasLength(2));
    // Si se vuelve a importar, toma el nombre que quedó libre.
    expect(await a.importar('${origen.path}/marco.boda.png', a.dirMarcos), 'marco.boda (2).png');
  });

  test('avisa cuando un evento usa un marco o canción que ya no está', () async {
    File('${a.dirMarcos.path}/boda.png').writeAsBytesSync([1]);
    expect(a.falta(a.rutaMarco('boda.png')), isFalse);
    expect(a.falta(a.rutaMarco('borrado.png')), isTrue);
    expect(a.falta(a.rutaCancion(null)), isFalse);
  });
}

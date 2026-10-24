import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'modelos.dart';

/// Guarda eventos, videos, bibliotecas y ajustes en el celular.
class Almacen extends ChangeNotifier {
  Almacen._();
  static final instancia = Almacen._();

  late Directory raiz;
  Directory get dirMarcos => Directory('${raiz.path}/marcos');
  Directory get dirMusica => Directory('${raiz.path}/musica');
  Directory get dirVideos => Directory('${raiz.path}/videos');
  File get _datos => File('${raiz.path}/datos.json');

  final List<Evento> eventos = [];
  final List<VideoGrabado> videos = [];

  /// Dirección del servidor de Cloudflare, por ejemplo
  /// https://marles360.tucuenta.workers.dev
  String servidor = '';
  String clave = '';

  bool get nubeLista => servidor.isNotEmpty && clave.isNotEmpty;

  Future<void> cargar() async {
    raiz = await getApplicationDocumentsDirectory();
    for (final d in [dirMarcos, dirMusica, dirVideos]) {
      await d.create(recursive: true);
    }
    if (await _datos.exists()) {
      final j = jsonDecode(await _datos.readAsString()) as Map<String, dynamic>;
      servidor = j['servidor'] ?? '';
      clave = j['clave'] ?? '';
      eventos.addAll([for (final e in j['eventos'] ?? []) Evento.fromJson(e)]);
      videos.addAll([for (final v in j['videos'] ?? []) VideoGrabado.fromJson(v)]);
    }
  }

  Future<void> guardar() async {
    final tmp = File('${_datos.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'servidor': servidor,
      'clave': clave,
      'eventos': [for (final e in eventos) e.toJson()],
      'videos': [for (final v in videos) v.toJson()],
    }));
    await tmp.rename(_datos.path);
    notifyListeners();
  }

  Evento? evento(String id) {
    for (final e in eventos) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<VideoGrabado> videosDe(String eventoId) =>
      videos.where((v) => v.eventoId == eventoId).toList()
        ..sort((a, b) => b.creado.compareTo(a.creado));

  List<VideoGrabado> get pendientes =>
      videos.where((v) => v.estado != EstadoVideo.subido).toList();

  Future<void> borrarEvento(Evento e) async {
    for (final v in videosDe(e.id)) {
      final f = File(v.archivo);
      if (await f.exists()) await f.delete();
      videos.remove(v);
    }
    eventos.remove(e);
    await guardar();
  }

  // Bibliotecas de marcos y música

  List<File> archivosDe(Directory d) {
    final lista = d.listSync().whereType<File>().toList()
      ..sort((a, b) => nombreDe(a.path).toLowerCase().compareTo(nombreDe(b.path).toLowerCase()));
    return lista;
  }

  List<File> get marcos => archivosDe(dirMarcos);
  List<File> get canciones => archivosDe(dirMusica);

  /// Copia un archivo elegido por el usuario a la biblioteca y devuelve su nombre.
  Future<String> importar(String origen, Directory destino) async {
    var nombre = nombreDe(origen);
    var f = File('${destino.path}/$nombre');
    var n = 2;
    while (await f.exists()) {
      final punto = nombre.lastIndexOf('.');
      final base = punto > 0 ? nombre.substring(0, punto) : nombre;
      final ext = punto > 0 ? nombre.substring(punto) : '';
      f = File('${destino.path}/$base ($n)$ext');
      n++;
    }
    await File(origen).copy(f.path);
    notifyListeners();
    return nombreDe(f.path);
  }

  Future<void> eliminar(File f) async {
    await f.delete();
    notifyListeners();
  }

  String? rutaMarco(String? nombre) => nombre == null ? null : '${dirMarcos.path}/$nombre';
  String? rutaCancion(String? nombre) => nombre == null ? null : '${dirMusica.path}/$nombre';
}

String nombreDe(String ruta) => ruta.split(Platform.pathSeparator).last;

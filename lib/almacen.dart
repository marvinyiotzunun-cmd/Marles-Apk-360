import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'modelos.dart';

/// Días que se guardan los videos (en la nube y en el celular).
const diasGuardado = 30;

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

  /// Lee todo lo guardado. [carpeta] solo se pasa en las pruebas.
  Future<void> cargar({Directory? carpeta}) async {
    raiz = carpeta ?? await getApplicationDocumentsDirectory();
    eventos.clear();
    videos.clear();
    servidor = '';
    clave = '';
    _guardando = Future.value();
    for (final d in [dirMarcos, dirMusica, dirVideos]) {
      await d.create(recursive: true);
    }
    if (await _datos.exists()) {
      try {
        final j = jsonDecode(await _datos.readAsString()) as Map<String, dynamic>;
        servidor = j['servidor'] ?? '';
        clave = j['clave'] ?? '';
        eventos.addAll([for (final e in j['eventos'] ?? []) Evento.fromJson(e)]);
        videos.addAll([for (final v in j['videos'] ?? []) _ubicar(VideoGrabado.fromJson(v))]);
      } catch (err) {
        // Un archivo dañado no debe impedir que la app abra: se guarda aparte.
        debugPrint('datos.json dañado: $err');
        eventos.clear();
        videos.clear();
        await _datos.copy('${_datos.path}.danado');
      }
    }
    await _limpiarViejos();
  }

  /// Si la carpeta de la app cambió de ruta (pasa en iPhone al actualizar),
  /// busca el video por su nombre dentro de la carpeta actual.
  VideoGrabado _ubicar(VideoGrabado v) {
    if (File(v.archivo).existsSync()) return v;
    final aqui = '${dirVideos.path}/${nombreDe(v.archivo)}';
    if (!File(aqui).existsSync()) return v;
    return VideoGrabado(id: v.id, eventoId: v.eventoId, archivo: aqui, creado: v.creado, estado: v.estado);
  }

  /// Los videos ya subidos se borran del celular a los 30 días, igual que en
  /// la nube, para no llenar la memoria. Los pendientes nunca se borran.
  /// También se borran las grabaciones sin procesar que quedaron sueltas.
  Future<void> _limpiarViejos() async {
    final ahora = DateTime.now();
    final limite = ahora.subtract(const Duration(days: diasGuardado));
    final viejos = videos.where((v) => v.estado == EstadoVideo.subido && v.creado.isBefore(limite)).toList();
    for (final v in viejos) {
      await _borrarArchivo(v.archivo);
      videos.remove(v);
    }
    final enUso = {for (final v in videos) v.archivo};
    final ayer = ahora.subtract(const Duration(days: 1));
    for (final f in dirVideos.listSync().whereType<File>()) {
      if (!enUso.contains(f.path) && f.statSync().modified.isBefore(ayer)) await f.delete();
    }
    if (viejos.isNotEmpty) await guardar();
  }

  Future<void> _guardando = Future.value();

  /// Guarda en orden: dos guardados al mismo tiempo (por ejemplo una subida
  /// que termina mientras se acepta otro video) no deben pisarse.
  Future<void> guardar() {
    final siguiente = _guardando.catchError((_) {}).then((_) => _escribir());
    _guardando = siguiente;
    return siguiente;
  }

  Future<void> _escribir() async {
    final tmp = File('${_datos.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'servidor': servidor,
        'clave': clave,
        'eventos': [for (final e in eventos) e.toJson()],
        'videos': [for (final v in videos) v.toJson()],
      }),
    );
    await tmp.rename(_datos.path);
    notifyListeners();
  }

  // Eventos y videos

  Evento? evento(String id) {
    for (final e in eventos) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Videos del evento, del más nuevo al más viejo.
  List<VideoGrabado> videosDe(String eventoId) =>
      videos.where((v) => v.eventoId == eventoId).toList()..sort((a, b) => b.creado.compareTo(a.creado));

  List<VideoGrabado> get pendientes => videos.where((v) => v.estado != EstadoVideo.subido).toList();

  Future<void> agregarVideo(VideoGrabado v) {
    videos.add(v);
    return guardar();
  }

  Future<void> borrarVideo(VideoGrabado v) async {
    await _borrarArchivo(v.archivo);
    videos.remove(v);
    await guardar();
  }

  Future<void> borrarEvento(Evento e) async {
    for (final v in videosDe(e.id)) {
      await _borrarArchivo(v.archivo);
      videos.remove(v);
    }
    eventos.remove(e);
    await guardar();
  }

  Future<void> _borrarArchivo(String ruta) async {
    final f = File(ruta);
    if (await f.exists()) await f.delete();
  }

  // Bibliotecas de marcos y música

  List<File> archivosDe(Directory d) =>
      d.listSync().whereType<File>().toList()
        ..sort((a, b) => nombreDe(a.path).toLowerCase().compareTo(nombreDe(b.path).toLowerCase()));

  List<File> get marcos => archivosDe(dirMarcos);
  List<File> get canciones => archivosDe(dirMusica);

  /// Copia un archivo elegido por el usuario a la biblioteca y devuelve su
  /// nombre. Si ya hay uno con el mismo nombre, agrega (2), (3)...
  Future<String> importar(String origen, Directory destino) async {
    final nombre = nombreDe(origen);
    final punto = nombre.lastIndexOf('.');
    final base = punto > 0 ? nombre.substring(0, punto) : nombre;
    final ext = punto > 0 ? nombre.substring(punto) : '';
    var f = File('${destino.path}/$nombre');
    for (var n = 2; await f.exists(); n++) {
      f = File('${destino.path}/$base ($n)$ext');
    }
    await File(origen).copy(f.path);
    notifyListeners();
    return nombreDe(f.path);
  }

  Future<void> eliminar(File f) async {
    await f.delete();
    // Si luego se importa otro archivo con el mismo nombre, que no salga la imagen vieja.
    await FileImage(f).evict();
    notifyListeners();
  }

  String? rutaMarco(String? nombre) => nombre == null ? null : '${dirMarcos.path}/$nombre';
  String? rutaCancion(String? nombre) => nombre == null ? null : '${dirMusica.path}/$nombre';

  /// true si el evento usa un marco o canción que ya no está en la biblioteca.
  bool falta(String? ruta) => ruta != null && !File(ruta).existsSync();
}

String nombreDe(String ruta) => ruta.split(Platform.pathSeparator).last;

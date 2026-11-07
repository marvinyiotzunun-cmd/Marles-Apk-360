import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../almacen.dart';
import '../modelos.dart';

/// El servidor respondió con un error (por ejemplo 401 si la clave no coincide).
class ErrorServidor implements Exception {
  ErrorServidor(this.codigo, this.detalle);
  final int codigo;
  final String detalle;

  @override
  String toString() => 'Servidor respondió $codigo: $detalle';
}

/// Sube los videos al servidor de Cloudflare y arma sus enlaces.
class Nube {
  /// [limiteDirecto] y [tamParte] solo cambian en las pruebas.
  Nube({this.limiteDirecto = 90 * 1024 * 1024, this.tamParte = 50 * 1024 * 1024});

  /// La que usa la app. Las pruebas la cambian por una falsa.
  static Nube instancia = Nube();

  /// Archivos más grandes que esto se suben por partes
  /// (Cloudflare acepta como máximo 100 MB por envío).
  final int limiteDirecto;
  final int tamParte;

  /// Tiempo máximo para los pedidos cortos; con mala señal no se queda colgado.
  static const _espera = Duration(seconds: 30);

  final _enCurso = <String, Future<void>>{};

  Almacen get _a => Almacen.instancia;
  String get _base => _a.servidor.replaceAll(RegExp(r'/+$'), '');
  Map<String, String> get _auth => {'Authorization': 'Bearer ${_a.clave}'};

  String enlaceVideo(VideoGrabado v) => '$_base/v/${v.eventoId}/${v.id}';
  String enlaceEvento(String eventoId) => '$_base/e/$eventoId';

  /// Sube un video; si ya se está subiendo, espera esa misma subida.
  Future<void> subir(VideoGrabado v, {void Function(double)? alAvanzar}) {
    return _enCurso.putIfAbsent(v.id, () async {
      try {
        await _subir(v, alAvanzar);
      } finally {
        // Quien llamó ya espera este mismo Future; aquí solo se saca de la lista.
        unawaited(_enCurso.remove(v.id));
      }
    });
  }

  /// Intenta subir todo lo pendiente. Devuelve cuántos se subieron.
  Future<int> subirPendientes() async {
    if (!_a.nubeLista) return 0;
    var subidos = 0;
    for (final v in _a.pendientes) {
      try {
        await subir(v);
        subidos++;
      } on StateError {
        // Este no se puede subir (por ejemplo, ya no está su archivo): se sigue con los demás.
      } on ErrorServidor catch (e) {
        // Con la clave equivocada fallarían todos.
        if (e.codigo == 401) break;
      } catch (_) {
        // Sin señal: los demás también fallarían (y cada uno esperaría su
        // tiempo límite). Se reintenta en la próxima pasada.
        break;
      }
    }
    return subidos;
  }

  /// Borra el video de la nube (si un invitado pide que no quede publicado).
  Future<void> borrar(VideoGrabado v) async {
    if (!_a.nubeLista) return;
    final r = await http.delete(Uri.parse('$_base/api/video/${v.eventoId}/${v.id}'), headers: _auth).timeout(_espera);
    if (r.statusCode != 404) _revisar(r);
  }

  Future<void> _subir(VideoGrabado v, void Function(double)? alAvanzar) async {
    if (!_a.nubeLista) throw StateError('Falta configurar la nube en Ajustes');
    final archivo = File(v.archivo);
    if (!await archivo.exists()) throw StateError('El archivo del video ya no está en el celular');
    final tam = await archivo.length();
    v.estado = EstadoVideo.subiendo;

    try {
      final evento = _a.evento(v.eventoId);
      if (evento != null) {
        _revisar(
          await http
              .put(
                Uri.parse('$_base/api/evento/${v.eventoId}'),
                headers: {..._auth, 'Content-Type': 'application/json'},
                body: jsonEncode({'nombre': evento.nombre, 'fecha': evento.fecha.toIso8601String()}),
              )
              .timeout(_espera),
        );
      }

      final ruta = '${v.eventoId}/${v.id}';
      if (tam <= limiteDirecto) {
        await _enviar('PUT', Uri.parse('$_base/api/subir/$ruta'), archivo, 0, tam, (n) => alAvanzar?.call(n / tam));
      } else {
        await _subirPorPartes(ruta, archivo, tam, alAvanzar);
      }
      v.estado = EstadoVideo.subido;
    } catch (_) {
      v.estado = EstadoVideo.pendiente;
      rethrow;
    } finally {
      await _a.guardar();
    }
  }

  Future<void> _subirPorPartes(String ruta, File archivo, int tam, void Function(double)? alAvanzar) async {
    final crear = await http.post(Uri.parse('$_base/api/mpu/crear/$ruta'), headers: _auth).timeout(_espera);
    final uploadId = jsonDecode(_revisar(crear))['uploadId'] as String;
    final partes = <Map<String, dynamic>>[];
    for (var inicio = 0, n = 1; inicio < tam; inicio += tamParte, n++) {
      final fin = (inicio + tamParte).clamp(0, tam);
      final uri = Uri.parse('$_base/api/mpu/parte/$ruta').replace(queryParameters: {'uploadId': uploadId, 'n': '$n'});
      final desde = inicio;
      final r = await _enviar('PUT', uri, archivo, inicio, fin, (b) => alAvanzar?.call((desde + b) / tam));
      partes.add(jsonDecode(r) as Map<String, dynamic>);
    }
    _revisar(
      await http
          .post(
            Uri.parse('$_base/api/mpu/completar/$ruta').replace(queryParameters: {'uploadId': uploadId}),
            headers: {..._auth, 'Content-Type': 'application/json'},
            body: jsonEncode({'partes': partes}),
          )
          .timeout(_espera),
    );
  }

  Future<String> _enviar(
    String metodo,
    Uri uri,
    File archivo,
    int inicio,
    int fin,
    void Function(int enviados) alAvanzar,
  ) async {
    var enviados = 0;
    // El archivo se lee a medida que la red lo va enviando, así el avance que
    // ve el invitado es real y no se carga el video entero en memoria.
    final datos = archivo.openRead(inicio, fin).map((trozo) {
      enviados += trozo.length;
      alAvanzar(enviados);
      return trozo;
    });
    final req = _SubidaArchivo(metodo, uri, datos)
      ..headers.addAll({..._auth, 'Content-Type': 'video/mp4'})
      ..contentLength = fin - inicio;
    final cliente = http.Client();
    try {
      final respuesta = await cliente.send(req).timeout(const Duration(minutes: 20));
      return _revisar(await http.Response.fromStream(respuesta).timeout(_espera));
    } finally {
      cliente.close();
    }
  }

  String _revisar(http.Response r) {
    if (r.statusCode >= 300) throw ErrorServidor(r.statusCode, r.body);
    return r.body;
  }

  /// Comprueba que el servidor y la clave funcionan. Devuelve null si todo
  /// está bien, o el problema explicado para mostrarlo en Ajustes.
  Future<String?> probar() async {
    try {
      final r = await http.get(Uri.parse('$_base/api/ping'), headers: _auth).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.body.contains('"ok"')) return null;
      if (r.statusCode == 401) return 'La clave no coincide con la del servidor.';
      return 'Esa dirección responde (${r.statusCode}), pero no es el servidor de Marles 360. Revisa la dirección.';
    } on HandshakeException {
      return 'No se pudo abrir una conexión segura con el servidor.';
    } on TimeoutException {
      return 'El servidor no respondió a tiempo. Revisa el internet e intenta de nuevo.';
    } on SocketException {
      return 'No se pudo conectar. Revisa la dirección y que haya internet.';
    } on http.ClientException {
      return 'No se pudo conectar. Revisa la dirección y que haya internet.';
    } on FormatException {
      return 'La dirección no es válida.';
    } on ArgumentError {
      return 'La dirección no es válida.';
    }
  }
}

/// Pedido cuyo cuerpo sale directamente de un archivo.
class _SubidaArchivo extends http.BaseRequest {
  _SubidaArchivo(super.method, super.url, this._datos);
  final Stream<List<int>> _datos;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_datos);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../almacen.dart';
import '../modelos.dart';

/// Sube los videos al servidor de Cloudflare y arma sus enlaces.
class Nube {
  Nube._();
  static final instancia = Nube._();

  /// Archivos más grandes que esto se suben por partes
  /// (Cloudflare acepta como máximo 100 MB por envío).
  static const _limiteDirecto = 90 * 1024 * 1024;
  static const _tamParte = 50 * 1024 * 1024;

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
        _enCurso.remove(v.id);
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
      } catch (_) {
        // Sin señal o error: se reintenta en la próxima pasada.
      }
    }
    return subidos;
  }

  Future<void> _subir(VideoGrabado v, void Function(double)? alAvanzar) async {
    if (!_a.nubeLista) throw StateError('Falta configurar la nube en Ajustes');
    final archivo = File(v.archivo);
    final tam = await archivo.length();
    v.estado = EstadoVideo.subiendo;

    try {
      final evento = _a.evento(v.eventoId);
      if (evento != null) {
        _revisar(await http.put(
          Uri.parse('$_base/api/evento/${v.eventoId}'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({'nombre': evento.nombre, 'fecha': evento.fecha.toIso8601String()}),
        ));
      }

      final ruta = '${v.eventoId}/${v.id}';
      if (tam <= _limiteDirecto) {
        await _enviar('PUT', Uri.parse('$_base/api/subir/$ruta'), archivo, 0, tam,
            (n) => alAvanzar?.call(n / tam));
      } else {
        final crear = await http.post(Uri.parse('$_base/api/mpu/crear/$ruta'), headers: _auth);
        final uploadId = jsonDecode(_revisar(crear))['uploadId'] as String;
        final partes = <Map<String, dynamic>>[];
        var enviado = 0;
        for (var inicio = 0, n = 1; inicio < tam; inicio += _tamParte, n++) {
          final fin = (inicio + _tamParte).clamp(0, tam);
          final uri = Uri.parse('$_base/api/mpu/parte/$ruta')
              .replace(queryParameters: {'uploadId': uploadId, 'n': '$n'});
          final r = await _enviar('PUT', uri, archivo, inicio, fin,
              (b) => alAvanzar?.call((enviado + b) / tam));
          partes.add(jsonDecode(r) as Map<String, dynamic>);
          enviado = fin;
        }
        _revisar(await http.post(
          Uri.parse('$_base/api/mpu/completar/$ruta').replace(queryParameters: {'uploadId': uploadId}),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({'partes': partes}),
        ));
      }
      v.estado = EstadoVideo.subido;
    } catch (_) {
      v.estado = EstadoVideo.pendiente;
      rethrow;
    } finally {
      await _a.guardar();
    }
  }

  Future<String> _enviar(String metodo, Uri uri, File archivo, int inicio, int fin,
      void Function(int enviados) alAvanzar) async {
    final req = http.StreamedRequest(metodo, uri)
      ..headers.addAll({..._auth, 'Content-Type': 'video/mp4'})
      ..contentLength = fin - inicio;
    final cliente = http.Client();
    try {
      final respuesta = cliente.send(req);
      var enviados = 0;
      await for (final trozo in archivo.openRead(inicio, fin)) {
        req.sink.add(trozo);
        enviados += trozo.length;
        alAvanzar(enviados);
      }
      await req.sink.close();
      final r = await http.Response.fromStream(await respuesta.timeout(const Duration(minutes: 5)));
      return _revisar(r);
    } finally {
      cliente.close();
    }
  }

  String _revisar(http.Response r) {
    if (r.statusCode >= 300) {
      throw HttpException('Servidor respondió ${r.statusCode}: ${r.body}');
    }
    return r.body;
  }

  /// Comprueba que el servidor y la clave funcionan.
  Future<String?> probar() async {
    try {
      final r = await http
          .get(Uri.parse('$_base/api/ping'), headers: _auth)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) return null;
      if (r.statusCode == 401) return 'La clave no coincide con la del servidor';
      return 'El servidor respondió ${r.statusCode}';
    } catch (e) {
      return 'No se pudo conectar: $e';
    }
  }
}

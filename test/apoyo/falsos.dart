// Reemplazos de la cámara, el reproductor, el procesado y la nube para probar
// las pantallas sin un celular.
import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marles360/modelos.dart';
import 'package:marles360/servicios/nube.dart';
import 'package:marles360/servicios/procesador.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Cámara falsa: abre al instante y "graba" un archivo de prueba.
class CamaraFalsa extends CameraPlatform {
  CamaraFalsa({this.carpeta, this.fallarAlAbrir = false});

  /// Donde se escriben las grabaciones falsas.
  final Directory? carpeta;
  final bool fallarAlAbrir;

  final _inicializada = StreamController<CameraInitializedEvent>.broadcast();

  // Una cámara real no cierra estos avisos: CameraController espera el primero
  // con .first, y un Stream vacío o cerrado lo haría fallar con "No element".
  // ignore: close_sinks
  final _errores = StreamController<CameraErrorEvent>.broadcast();
  // ignore: close_sinks
  final _cerrando = StreamController<CameraClosingEvent>.broadcast();
  // ignore: close_sinks
  final _orientacion = StreamController<DeviceOrientationChangedEvent>.broadcast();
  var grabaciones = 0;
  var grabando = false;
  var abiertas = 0;
  var cerradas = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(name: 'trasera', lensDirection: CameraLensDirection.back, sensorOrientation: 90),
    CameraDescription(name: 'frontal', lensDirection: CameraLensDirection.front, sensorOrientation: 270),
  ];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async {
    if (fallarAlAbrir) throw PlatformException(code: 'CameraAccessDenied', message: 'sin permiso');
    return ++abiertas;
  }

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    scheduleMicrotask(
      () => _inicializada.add(
        CameraInitializedEvent(cameraId, 1920, 1080, ExposureMode.auto, true, FocusMode.auto, true),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _inicializada.stream.where((e) => e.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errores.stream.where((e) => e.cameraId == cameraId);

  /// Simula que la cámara se cae (por ejemplo, otra app la tomó).
  void fallar(int cameraId, String detalle) => _errores.add(CameraErrorEvent(cameraId, detalle));

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) => _cerrando.stream.where((e) => e.cameraId == cameraId);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => _orientacion.stream;

  @override
  Future<void> lockCaptureOrientation(int cameraId, DeviceOrientation orientation) async {}

  @override
  Future<void> prepareForVideoRecording() async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    grabando = true;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    grabando = false;
    grabaciones++;
    final dir = carpeta ?? Directory.systemTemp;
    final f = File('${dir.path}/grabacion_$grabaciones.mp4')..writeAsBytesSync(List.filled(1000, 7));
    return XFile(f.path);
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Color(0xFF335577));

  @override
  Future<void> dispose(int cameraId) async {
    cerradas++;
  }
}

/// Reproductor falso: el video "carga" al instante.
class ReproductorFalso extends VideoPlayerPlatform {
  final _eventos = <int, StreamController<VideoEvent>>{};
  var _siguiente = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _siguiente++;
    _eventos[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // ignore: close_sinks, se cierra en dispose().
    final c = _eventos[playerId]!;
    scheduleMicrotask(
      () => c.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 15),
          size: const Size(1080, 1920),
        ),
      ),
    );
    return c.stream;
  }

  @override
  Future<void> dispose(int playerId) async => _eventos.remove(playerId)?.close();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Color(0xFF775533));

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

/// Procesado falso: copia la grabación como si fuera el video final.
/// Con [completar] se controla cuándo termina.
class ProcesadorFalso extends Procesador {
  ProcesadorFalso({this.fallar = false});
  final bool fallar;
  Completer<void>? completar;
  var procesados = 0;
  var cancelados = 0;

  @override
  Future<File> procesar({
    required String grabado,
    required Evento evento,
    required String salida,
    void Function(double avance)? alAvanzar,
  }) async {
    alAvanzar?.call(0.5);
    await completar?.future;
    if (fallar) throw ErrorProcesando('falla de prueba');
    procesados++;
    // Copia sin esperar al disco: dentro de las pruebas de pantallas la
    // lectura asíncrona de archivos no avanza sola.
    File(grabado).copySync(salida);
    return File(salida);
  }

  @override
  Future<void> cancelar() async => cancelados++;
}

/// Nube falsa: sube al instante (o falla, si se pide).
class NubeFalsa extends Nube {
  NubeFalsa({this.error, this.resultadoPrueba});

  /// Si no es null, cada subida falla con este error.
  final Object? error;

  /// Lo que responde "Guardar y probar" (null = conexión correcta).
  final String? resultadoPrueba;

  /// Si no es null, la subida espera a que se complete (para ver "Subiendo…").
  Completer<void>? esperar;
  final subidos = <String>[];
  final borrados = <String>[];

  @override
  Future<void> subir(VideoGrabado v, {void Function(double)? alAvanzar}) async {
    alAvanzar?.call(0.4);
    await esperar?.future;
    if (error != null) throw error!;
    v.estado = EstadoVideo.subido;
    subidos.add(v.id);
  }

  @override
  Future<void> borrar(VideoGrabado v) async => borrados.add(v.id);

  @override
  Future<String?> probar() async => resultadoPrueba;
}

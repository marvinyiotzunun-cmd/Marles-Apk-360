import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../tema.dart';
import 'vista_previa.dart';

enum _Fase { preparando, listo, esperando, cuenta, grabando, guardando }

/// Vista de cámara en 9:16 con el marco encima, tal como saldrá el video.
class PantallaCamara extends StatefulWidget {
  const PantallaCamara({super.key, required this.evento});
  final Evento evento;

  @override
  State<PantallaCamara> createState() => _PantallaCamaraState();
}

class _PantallaCamaraState extends State<PantallaCamara> with WidgetsBindingObserver {
  CameraController? _cam;
  _Fase _fase = _Fase.preparando;
  int _segundos = 0;
  Timer? _reloj;
  String? _error;

  Evento get e => widget.evento;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _iniciarCamara();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _cam?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    if (estado == AppLifecycleState.inactive) {
      _reloj?.cancel();
      _cam = null;
      cam.dispose();
      setState(() => _fase = _Fase.preparando);
    } else if (estado == AppLifecycleState.resumed) {
      _iniciarCamara();
    }
  }

  Future<void> _iniciarCamara() async {
    try {
      final camaras = await availableCameras();
      final lado = e.camaraFrontal ? CameraLensDirection.front : CameraLensDirection.back;
      final desc = camaras.firstWhere((c) => c.lensDirection == lado, orElse: () => camaras.first);
      final cam = CameraController(desc, ResolutionPreset.veryHigh, enableAudio: true, fps: 30);
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() {
        _cam = cam;
        _fase = _Fase.listo;
      });
      if (e.modo == ModoInicio.temporizador) _esperar();
    } catch (err) {
      setState(() => _error = 'No se pudo abrir la cámara: $err');
    }
  }

  void _esperar() {
    _contar(_Fase.esperando, e.retrasoTemporizador, _empezarCuenta);
  }

  void _empezarCuenta() {
    if (e.cuentaRegresiva == 0) {
      _grabar();
    } else {
      _contar(_Fase.cuenta, e.cuentaRegresiva, _grabar);
    }
  }

  void _contar(_Fase fase, int desde, VoidCallback alTerminar) {
    _reloj?.cancel();
    setState(() {
      _fase = fase;
      _segundos = desde;
    });
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_segundos <= 1) {
        t.cancel();
        alTerminar();
      } else {
        setState(() => _segundos--);
      }
    });
  }

  Future<void> _grabar() async {
    final cam = _cam;
    if (cam == null) return;
    await cam.startVideoRecording();
    _contar(_Fase.grabando, e.duracion, _detener);
  }

  Future<void> _detener() async {
    final cam = _cam;
    if (cam == null || _fase != _Fase.grabando) return;
    _reloj?.cancel();
    setState(() => _fase = _Fase.guardando);
    final archivo = await cam.stopVideoRecording();
    final destino = '${Almacen.instancia.dirVideos.path}/crudo_${nuevoId()}.mp4';
    await File(archivo.path).rename(destino).catchError((_) => File(archivo.path).copy(destino));
    if (!mounted) return;
    setState(() => _fase = _Fase.listo);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaVistaPrevia(evento: e, grabado: destino)),
    );
    if (mounted && _cam != null && e.modo == ModoInicio.temporizador) _esperar();
  }

  /// Botón en pantalla, control Bluetooth o botones de volumen.
  void _accion() {
    switch (_fase) {
      case _Fase.listo:
        _empezarCuenta();
      case _Fase.esperando:
        _reloj?.cancel();
        _empezarCuenta();
      case _Fase.cuenta:
        _reloj?.cancel();
        setState(() => _fase = _Fase.listo);
      case _Fase.grabando:
        _detener();
      case _Fase.preparando:
      case _Fase.guardando:
        break;
    }
  }

  static final _teclasDisparo = {
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.camera,
    LogicalKeyboardKey.mediaPlayPause,
  };

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final marco = Almacen.instancia.rutaMarco(e.marco);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, evento) {
        if (!_teclasDisparo.contains(evento.logicalKey)) return KeyEventResult.ignored;
        if (evento is KeyDownEvent) _accion();
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cam != null && cam.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: cam.value.previewSize!.height,
                              height: cam.value.previewSize!.width,
                              child: CameraPreview(cam),
                            ),
                          ),
                        if (marco != null && File(marco).existsSync()) Image.file(File(marco), fit: BoxFit.fill),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Center(child: Text(_error!, style: const TextStyle(color: Colors.white))),
              if (_fase == _Fase.cuenta || _fase == _Fase.esperando)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_fase == _Fase.esperando)
                        const Text('Empieza en', style: TextStyle(color: Colors.white, fontSize: 24)),
                      Text('$_segundos',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: _fase == _Fase.cuenta ? 180 : 96,
                            fontWeight: FontWeight.w700,
                            shadows: const [Shadow(blurRadius: 16)],
                          )),
                    ],
                  ),
                ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: _fase == _Fase.grabando ? null : () => Navigator.of(context).pop(),
                ),
              ),
              if (_fase == _Fase.grabando)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Marles.rojo, borderRadius: BorderRadius.circular(20)),
                    child: Text('● ${_reloj2(_segundos)}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(child: _boton()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boton() {
    if (_fase == _Fase.guardando || _fase == _Fase.preparando) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    final grabando = _fase == _Fase.grabando;
    return GestureDetector(
      onTap: _accion,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: grabando ? 32 : 64,
            height: grabando ? 32 : 64,
            decoration: BoxDecoration(
              color: Marles.rojo,
              borderRadius: BorderRadius.circular(grabando ? 6 : 32),
            ),
          ),
        ),
      ),
    );
  }
}

String _reloj2(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

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
    // Solo se suelta la cámara cuando la app pasa a segundo plano. Bajar la
    // barra de notificaciones o un aviso del control Bluetooth ("inactive")
    // no debe cortar la grabación.
    if (estado == AppLifecycleState.paused || estado == AppLifecycleState.hidden) {
      final cam = _cam;
      if (cam == null) return;
      _reloj?.cancel();
      _cam = null;
      cam.dispose();
      if (mounted) setState(() => _fase = _Fase.preparando);
    } else if (estado == AppLifecycleState.resumed && _cam == null && !_abriendo) {
      _iniciarCamara();
    }
  }

  bool _abriendo = false;

  /// true mientras se ve la vista previa o el QR: la cámara no debe arrancar sola.
  bool _fuera = false;

  Future<void> _iniciarCamara() async {
    _abriendo = true;
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) throw StateError('no hay cámaras');
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
        _error = null;
        _fase = _Fase.listo;
      });
      if (e.modo == ModoInicio.temporizador && !_fuera) _esperar();
    } on CameraException catch (err) {
      if (!mounted) return;
      final permiso = err.code.contains('AccessDenied') || err.code.contains('Permission');
      setState(() => _error = permiso
          ? 'La app no tiene permiso para usar la cámara o el micrófono. '
              'Actívalo en Ajustes del teléfono > Apps > Marles 360 > Permisos.'
          : 'No se pudo abrir la cámara (${err.description ?? err.code}).');
    } catch (err) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara: $err');
    } finally {
      _abriendo = false;
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
      if (!mounted) {
        t.cancel();
      } else if (_segundos <= 1) {
        t.cancel();
        alTerminar();
      } else {
        setState(() => _segundos--);
      }
    });
  }

  Future<void> _grabar() async {
    final cam = _cam;
    if (cam == null || !mounted) return;
    // Mientras arranca la grabación se ignoran más toques.
    setState(() => _fase = _Fase.guardando);
    try {
      await cam.startVideoRecording();
    } catch (_) {
      if (mounted) {
        setState(() => _fase = _Fase.listo);
        _avisar('No se pudo empezar a grabar. Intenta de nuevo.');
      }
      return;
    }
    if (!mounted || _cam != cam) return;
    _contar(_Fase.grabando, e.duracion, _detener);
  }

  Future<void> _detener() async {
    final cam = _cam;
    if (cam == null || _fase != _Fase.grabando) return;
    _reloj?.cancel();
    setState(() => _fase = _Fase.guardando);
    final String destino;
    try {
      final archivo = await cam.stopVideoRecording();
      destino = '${Almacen.instancia.dirVideos.path}/crudo_${nuevoId()}.mp4';
      try {
        await File(archivo.path).rename(destino);
      } on FileSystemException {
        await File(archivo.path).copy(destino);
        await File(archivo.path).delete();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _fase = _Fase.listo);
        _avisar('No se pudo guardar la grabación. Intenta de nuevo.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _fase = _Fase.listo);
    _fuera = true;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaVistaPrevia(evento: e, grabado: destino)),
    );
    _fuera = false;
    if (mounted && _cam != null && _fase == _Fase.listo && e.modo == ModoInicio.temporizador) _esperar();
  }

  void _avisar(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
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
      child: PopScope(
        // El botón atrás no corta una grabación a medias.
        canPop: _fase != _Fase.grabando && _fase != _Fase.guardando,
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
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 56),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () {
                            setState(() => _error = null);
                            _iniciarCamara();
                          },
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  onPressed: _fase == _Fase.grabando || _fase == _Fase.guardando ? null : () => Navigator.of(context).pop(),
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
      ),
    );
  }

  Widget _boton() {
    if (_error != null) return const SizedBox.shrink();
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

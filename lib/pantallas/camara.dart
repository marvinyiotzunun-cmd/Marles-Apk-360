import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../tema.dart';
import '../utiles/formato.dart';
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
  bool _abriendo = false;

  /// true mientras se ve la vista previa o el QR: la cámara no debe arrancar sola.
  bool _fuera = false;

  Evento get e => widget.evento;

  /// Botones del control Bluetooth, de volumen o de un teclado que disparan.
  static final _teclasDisparo = {
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.camera,
    LogicalKeyboardKey.mediaPlayPause,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // La pantalla no se apaga mientras la cámara está abierta.
    unawaited(WakelockPlus.enable().catchError((_) {}));
    unawaited(_iniciarCamara());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    unawaited(_cam?.dispose());
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Solo se suelta la cámara cuando la app pasa a segundo plano. Bajar la
    // barra de notificaciones o un aviso del control Bluetooth ("inactive")
    // no debe cortar la grabación.
    if (estado == AppLifecycleState.paused || estado == AppLifecycleState.hidden) {
      _soltarCamara();
    } else if (estado == AppLifecycleState.resumed && _cam == null && !_abriendo) {
      // También al volver de Ajustes del teléfono tras dar el permiso.
      _reintentar();
    }
  }

  void _soltarCamara() {
    final cam = _cam;
    if (cam == null) return;
    _reloj?.cancel();
    _cam = null;
    // Se cierra apenas termine lo que está corriendo: aquí se puede llegar desde
    // un aviso de la misma cámara (_revisarCamara), y cerrarla mientras avisa
    // es un error.
    scheduleMicrotask(() => unawaited(cam.dispose()));
    if (mounted) setState(() => _fase = _Fase.preparando);
  }

  Future<void> _iniciarCamara() async {
    _abriendo = true;
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) throw CameraException('SinCamara', 'el teléfono no reporta cámaras');
      final lado = e.camaraFrontal ? CameraLensDirection.front : CameraLensDirection.back;
      final desc = camaras.firstWhere((c) => c.lensDirection == lado, orElse: () => camaras.first);
      final cam = CameraController(desc, ResolutionPreset.veryHigh, enableAudio: true, fps: 30);
      await cam.initialize();
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      final estado = WidgetsBinding.instance.lifecycleState;
      final enSegundoPlano = estado == AppLifecycleState.paused || estado == AppLifecycleState.hidden;
      if (!mounted || enSegundoPlano) {
        // Se salió de la pantalla o de la app mientras la cámara abría.
        await cam.dispose();
        return;
      }
      cam.addListener(() => _revisarCamara(cam));
      setState(() {
        _cam = cam;
        _error = null;
        _fase = _Fase.listo;
      });
      if (e.modo == ModoInicio.temporizador && !_fuera) _esperar();
    } on CameraException catch (err) {
      if (!mounted) return;
      final permiso = err.code.contains('AccessDenied') || err.code.contains('Permission');
      setState(
        () => _error = permiso
            ? 'La app no tiene permiso para usar la cámara o el micrófono. '
                  'Actívalo en Ajustes del teléfono > Apps > Marles 360 > Permisos.'
            : 'No se pudo abrir la cámara (${err.description ?? err.code}).',
      );
    } catch (err) {
      if (mounted) setState(() => _error = 'No se pudo abrir la cámara: $err');
    } finally {
      _abriendo = false;
    }
  }

  /// Si otra app toma la cámara o falla, se muestra el aviso con Reintentar.
  void _revisarCamara(CameraController cam) {
    if (!cam.value.hasError || _cam != cam || !mounted) return;
    final detalle = cam.value.errorDescription;
    _soltarCamara();
    setState(() => _error = 'La cámara se detuvo ($detalle). Cierra otras apps que usen la cámara.');
  }

  void _esperar() => _contar(_Fase.esperando, e.retrasoTemporizador, _empezarCuenta);

  void _empezarCuenta() {
    if (e.cuentaRegresiva == 0) {
      unawaited(_grabar());
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
      MaterialPageRoute<void>(
        builder: (_) => PantallaVistaPrevia(evento: e, grabado: destino),
      ),
    );
    _fuera = false;
    if (mounted && _cam != null && _fase == _Fase.listo && e.modo == ModoInicio.temporizador) _esperar();
  }

  void _avisar(String texto) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

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
        unawaited(_detener());
      case _Fase.preparando:
      case _Fase.guardando:
        break;
    }
  }

  void _reintentar() {
    if (_abriendo) return;
    if (mounted) setState(() => _error = null);
    unawaited(_iniciarCamara());
  }

  @override
  Widget build(BuildContext context) {
    final ocupada = _fase == _Fase.grabando || _fase == _Fase.guardando;
    return Focus(
      autofocus: true,
      // Este Focus solo escucha el control Bluetooth; para TalkBack no es un botón.
      includeSemantics: false,
      onKeyEvent: (_, evento) {
        if (!_teclasDisparo.contains(evento.logicalKey)) return KeyEventResult.ignored;
        if (evento is KeyDownEvent) _accion();
        return KeyEventResult.handled;
      },
      child: PopScope(
        // El botón atrás no corta una grabación a medias.
        canPop: !ocupada,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: _Visor(cam: _cam, marco: Almacen.instancia.rutaMarco(e.marco)),
                ),
                if (_error != null) _AvisoError(texto: _error!, alReintentar: _reintentar),
                if (_fase == _Fase.cuenta || _fase == _Fase.esperando)
                  _Cuenta(segundos: _segundos, esperando: _fase == _Fase.esperando),
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton.filled(
                    tooltip: 'Cerrar cámara',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black26,
                      disabledForegroundColor: Colors.white38,
                    ),
                    icon: const Icon(Icons.close),
                    onPressed: ocupada ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                if (_fase == _Fase.grabando) Positioned(top: 12, right: 12, child: _Grabando(restante: _segundos)),
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: _error != null ? const SizedBox.shrink() : _controles(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controles() {
    final pista = switch (_fase) {
      _Fase.listo => e.modo == ModoInicio.boton ? 'Toca el botón o usa el control' : 'Toca el botón para empezar ya',
      _Fase.esperando => 'Toca el botón para empezar ya',
      _Fase.cuenta => 'Toca el botón para cancelar',
      _Fase.grabando => 'Toca el botón para terminar antes',
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pista != null)
          // El aviso puede crecer con la letra del sistema, pero sin tapar la cámara.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.4,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text(
                pista,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        if (_fase == _Fase.guardando || _fase == _Fase.preparando)
          const SizedBox(
            width: 84,
            height: 84,
            child: Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else
          _BotonGrabar(grabando: _fase == _Fase.grabando, alTocar: _accion),
      ],
    );
  }
}

/// Cámara en 9:16 con el marco encima, recortada igual que el video final.
class _Visor extends StatelessWidget {
  const _Visor({required this.cam, required this.marco});
  final CameraController? cam;
  final String? marco;

  @override
  Widget build(BuildContext context) {
    final cam = this.cam;
    final marco = this.marco;
    return AspectRatio(
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
    );
  }
}

class _AvisoError extends StatelessWidget {
  const _AvisoError({required this.texto, required this.alReintentar});
  final String texto;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 12),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: alReintentar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Números grandes de la cuenta regresiva o de la espera del temporizador.
class _Cuenta extends StatelessWidget {
  const _Cuenta({required this.segundos, required this.esperando});
  final int segundos;
  final bool esperando;

  @override
  Widget build(BuildContext context) {
    const sombra = [Shadow(blurRadius: 16)];
    // Los números ya son enormes: la letra grande del sistema no los agranda más
    // (con ella el 10 tapaba el aviso de abajo en celulares chicos).
    return MediaQuery.withNoTextScaling(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          // FittedBox: con letra grande del sistema los números no se salen.
          child: FittedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (esperando)
                  const Text(
                    'Empieza en',
                    style: TextStyle(color: Colors.white, fontSize: 24, shadows: sombra),
                  ),
                Text(
                  '$segundos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: esperando ? 96 : 180,
                    fontWeight: FontWeight.w700,
                    shadows: sombra,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Grabando extends StatelessWidget {
  const _Grabando({required this.restante});
  final int restante;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Grabando, faltan $restante segundos',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Marles.rojo, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Punto dibujado (no el carácter ●, que no existe en todas las fuentes).
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              reloj(restante),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonGrabar extends StatelessWidget {
  const _BotonGrabar({required this.grabando, required this.alTocar});
  final bool grabando;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: grabando ? 'Detener grabación' : 'Grabar',
      child: GestureDetector(
        onTap: alTocar,
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
              decoration: BoxDecoration(color: Marles.rojo, borderRadius: BorderRadius.circular(grabando ? 6 : 32)),
            ),
          ),
        ),
      ),
    );
  }
}

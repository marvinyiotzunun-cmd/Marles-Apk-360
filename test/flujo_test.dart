// El recorrido completo de la cabina, como en un evento: cámara, cuenta
// regresiva, grabación, vista previa, entrega por QR y de vuelta a la cámara.
// También lo que pasa en un evento real: atrás a media grabación, el control
// Bluetooth, la cámara que se cae, la app que se va a segundo plano y la
// falta de señal.
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/almacen.dart';
import 'package:marles360/modelos.dart';
import 'package:marles360/pantallas/camara.dart';
import 'package:marles360/pantallas/entrega.dart';
import 'package:marles360/pantallas/vista_previa.dart';
import 'package:marles360/servicios/nube.dart';
import 'package:marles360/servicios/procesador.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'apoyo/entorno.dart';
import 'apoyo/falsos.dart';

/// Lo que cada prueba necesita a mano.
class _Cabina {
  _Cabina(this.dir, this.camara, this.procesador, this.nube);
  final Directory dir;
  final CamaraFalsa camara;
  final ProcesadorFalso procesador;
  NubeFalsa nube;

  List<String> get archivosVideos => [for (final f in Almacen.instancia.dirVideos.listSync()) nombreDe(f.path)]..sort();
}

Future<_Cabina> _preparar(WidgetTester tester, {bool nube = true}) async {
  ponerPantalla(tester, pantallas[1], 1);
  late Directory dir;
  await tester.runAsync(() async => dir = await almacenNuevo());
  if (nube) {
    Almacen.instancia
      ..servidor = 'https://marles360.marles.workers.dev'
      ..clave = 'una-clave-larga';
  }
  final s = _Cabina(dir, CamaraFalsa(carpeta: dir), ProcesadorFalso(), NubeFalsa());
  CameraPlatform.instance = s.camara;
  VideoPlayerPlatform.instance = ReproductorFalso();
  Procesador.instancia = s.procesador;
  Nube.instancia = s.nube;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await asentar(tester, vueltas: 4);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  return s;
}

Evento _evento({ModoInicio modo = ModoInicio.boton, int cuenta = 3, int duracion = 5, int espera = 10}) {
  final e = Evento(
    id: 'abc234',
    nombre: 'Boda de Ana y Luis',
    fecha: DateTime(2026, 11, 14),
    duracion: duracion,
    cuentaRegresiva: cuenta,
    modo: modo,
    retrasoTemporizador: espera,
  );
  Almacen.instancia.eventos.add(e);
  return e;
}

/// Abre la cámara desde otra pantalla (como desde el evento), para que el
/// botón atrás tenga a dónde volver.
Future<void> _abrirCamara(WidgetTester tester, Evento e) async {
  await tester.pumpWidget(
    app(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PantallaCamara(evento: e))),
              child: const Text('Abrir cámara'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir cámara'));
  await _hastaQue(tester, () => find.bySemanticsLabel('Grabar').evaluate().isNotEmpty, 'la cámara lista');
}

/// Deja correr el disco y las animaciones hasta que se cumpla [condicion].
/// Avanza el reloj de a poco (16 ms), así no se adelantan las cuentas regresivas.
Future<void> _hastaQue(WidgetTester tester, bool Function() condicion, String que, {int vueltas = 150}) async {
  for (var i = 0; i < vueltas && !condicion(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(condicion(), isTrue, reason: 'No se llegó a: $que');
}

bool _hay(Finder f) => f.evaluate().isNotEmpty;

/// Deja terminar la animación de cambio de pantalla (la nueva entra deslizándose).
Future<void> _quieto(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _boton(String texto) => find.ancestor(of: find.text(texto), matching: find.bySubtype<ButtonStyleButton>());

bool _habilitado(WidgetTester tester, String texto) =>
    _hay(_boton(texto)) && tester.widget<ButtonStyleButton>(_boton(texto)).onPressed != null;

/// Avanza [n] segundos, uno por uno, como el reloj de la cámara.
Future<void> _segundos(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  // Lo que arranca al terminar la cuenta (empezar o detener la grabación).
  await tester.pump();
  await tester.pump();
}

/// Aceptar el video y esperar el QR (o el aviso de que no se pudo subir).
Future<void> _aceptar(WidgetTester tester) async {
  await _hastaQue(tester, () => _habilitado(tester, 'Aceptar'), 'el video listo para aceptar');
  await tester.tap(_boton('Aceptar'));
  await _hastaQue(tester, () => _hay(find.byType(PantallaEntrega)), 'la pantalla de entrega');
}

Future<void> _siguiente(WidgetTester tester) async {
  await tester.tap(_boton('Listo, siguiente video'));
  await _hastaQue(
    tester,
    () => !_hay(find.byType(PantallaEntrega)) && !_hay(find.byType(PantallaVistaPrevia)),
    'de vuelta en la cámara',
  );
}

void main() {
  setUpAll(cargarFuentes);

  testWidgets('graba, entrega por QR y vuelve a la cámara lista para el siguiente', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento(cuenta: 3, duracion: 5));
    expect(find.text('Toca el botón o usa el control'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Grabar'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Toca el botón para cancelar'), findsOneWidget);
    await _segundos(tester, 1);
    expect(find.text('2'), findsOneWidget);
    await _segundos(tester, 1);
    expect(find.text('1'), findsOneWidget);
    expect(s.camara.grabando, isFalse);

    await _segundos(tester, 1);
    expect(s.camara.grabando, isTrue);
    expect(find.bySemanticsLabel('Grabando, faltan 5 segundos'), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
    await _segundos(tester, 2);
    expect(find.text('0:03'), findsOneWidget);

    // Al cumplirse el tiempo del evento se detiene sola.
    await _segundos(tester, 3);
    expect(s.camara.grabando, isFalse);
    await _hastaQue(tester, () => _hay(find.byType(PantallaVistaPrevia)), 'la vista previa');
    expect(s.camara.grabaciones, 1);

    await _aceptar(tester);
    await _hastaQue(tester, () => _hay(find.text('Escanea para recibir tu video')), 'el QR');
    final v = Almacen.instancia.videos.single;
    expect(s.nube.subidos, [v.id]);
    expect(v.estado, EstadoVideo.subido);
    // Queda solo el video terminado; la grabación sin procesar se borró.
    expect(s.archivosVideos, ['abc234_${v.id}.mp4']);
    expect(File('${s.dir.path}/grabacion_1.mp4').existsSync(), isFalse);

    await _siguiente(tester);
    expect(find.bySemanticsLabel('Grabar'), findsOneWidget);
    // La cámara siguió abierta todo el tiempo: el siguiente invitado no espera.
    expect(s.camara.abiertas, 1);
    expect(s.camara.cerradas, 0);

    // Segundo invitado: termina antes con el botón.
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await _segundos(tester, 3);
    await _segundos(tester, 2);
    await tester.tap(find.bySemanticsLabel('Detener grabación'));
    await _hastaQue(tester, () => _hay(find.byType(PantallaVistaPrevia)), 'la segunda vista previa');
    await _aceptar(tester);
    await _hastaQue(tester, () => s.nube.subidos.length == 2, 'el segundo video subido');
    await _siguiente(tester);
    expect(Almacen.instancia.videos, hasLength(2));
    expect(Almacen.instancia.pendientes, isEmpty);
    semantica.dispose();
  });

  testWidgets('con temporizador espera, cuenta y graba sola; Repetir no deja archivos', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento(modo: ModoInicio.temporizador, espera: 3, cuenta: 2, duracion: 5));
    expect(find.text('Empieza en'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await _segundos(tester, 3);
    expect(find.text('Empieza en'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    await _segundos(tester, 2);
    expect(s.camara.grabando, isTrue);
    await _segundos(tester, 5);
    await _hastaQue(tester, () => _habilitado(tester, 'Aceptar'), 'el video listo');

    await tester.tap(_boton('Repetir'));
    await _hastaQue(tester, () => !_hay(find.byType(PantallaVistaPrevia)), 'de vuelta en la cámara');
    expect(s.procesador.cancelados, 1);
    expect(s.archivosVideos, isEmpty);
    expect(Almacen.instancia.videos, isEmpty);
    // Y vuelve a esperar sola al siguiente invitado.
    expect(find.text('Empieza en'), findsOneWidget);

    // Tocar el botón durante la espera empieza ya la cuenta.
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await tester.pump();
    expect(find.text('Empieza en'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('a media grabación, atrás no cierra la cámara', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester, nube: false);
    await _abrirCamara(tester, _evento(cuenta: 0, duracion: 30));

    // Sin cuenta regresiva empieza de inmediato.
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await tester.pump();
    await tester.pump();
    expect(s.camara.grabando, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PantallaCamara), findsOneWidget);
    expect(s.camara.grabando, isTrue);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close)).onPressed, isNull);

    await _segundos(tester, 2);
    expect(find.text('0:28'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Detener grabación'));
    await _hastaQue(tester, () => _hay(find.byType(PantallaVistaPrevia)), 'la vista previa');
    expect(s.camara.grabando, isFalse);

    // Sin nube configurada el video se guarda y se puede seguir con el siguiente.
    await _aceptar(tester);
    await _hastaQue(tester, () => _hay(find.textContaining('La nube no está configurada')), 'el aviso sin nube');
    expect(find.text('Compartir por Bluetooth o Quick Share'), findsOneWidget);
    expect(Almacen.instancia.pendientes, hasLength(1));
    await _siguiente(tester);

    // Sin grabar, atrás sí cierra la cámara (y la suelta).
    await tester.binding.handlePopRoute();
    await _hastaQue(tester, () => !_hay(find.byType(PantallaCamara)), 'la cámara cerrada');
    expect(find.text('Abrir cámara'), findsOneWidget);
    expect(s.camara.cerradas, 1);
    semantica.dispose();
  });

  testWidgets('el control Bluetooth y los botones de volumen disparan', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento(cuenta: 3, duracion: 5));

    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    // Otra vez durante la cuenta: la cancela.
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeDown);
    await tester.pump();
    expect(find.text('3'), findsNothing);
    expect(find.text('Toca el botón o usa el control'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _segundos(tester, 3);
    expect(s.camara.grabando, isTrue);
    await _segundos(tester, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _hastaQue(tester, () => _hay(find.byType(PantallaVistaPrevia)), 'la vista previa');
    expect(s.camara.grabaciones, 1);

    // En la vista previa el control ya no graba.
    await tester.sendKeyEvent(LogicalKeyboardKey.audioVolumeUp);
    await _segundos(tester, 4);
    expect(s.camara.grabando, isFalse);
    expect(s.camara.grabaciones, 1);
    semantica.dispose();
  });

  testWidgets('si otra app toma la cámara, avisa y Reintentar la abre de nuevo', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento());

    s.camara.fallar(s.camara.abiertas, 'otra app la tomó');
    await tester.pump();
    await tester.pump();
    expect(find.text('La cámara se detuvo (otra app la tomó). Cierra otras apps que usen la cámara.'), findsOneWidget);
    expect(s.camara.cerradas, 1);
    expect(find.bySemanticsLabel('Grabar'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await _hastaQue(tester, () => _hay(find.bySemanticsLabel('Grabar')), 'la cámara abierta otra vez');
    expect(s.camara.abiertas, 2);
    expect(find.textContaining('La cámara se detuvo'), findsNothing);
    semantica.dispose();
  });

  testWidgets('al salir de la app suelta la cámara y al volver la abre', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento(cuenta: 0, duracion: 30));
    final b = tester.binding;

    // Bajar la barra de notificaciones (inactive) no corta nada.
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await tester.pump();
    await tester.pump();
    b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(s.camara.grabando, isTrue);
    expect(s.camara.cerradas, 0);
    b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // Salir a otra app sí la suelta (Android se la daría a la otra app).
    for (final estado in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      b.handleAppLifecycleStateChanged(estado);
    }
    await tester.pump();
    expect(s.camara.cerradas, 1);
    expect(find.bySemanticsLabel('Detener grabación'), findsNothing);

    for (final estado in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      b.handleAppLifecycleStateChanged(estado);
    }
    await _hastaQue(tester, () => _hay(find.bySemanticsLabel('Grabar')), 'la cámara abierta otra vez');
    expect(s.camara.abiertas, 2);
    // Se puede grabar de nuevo normalmente.
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Detener grabación'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('sin señal el video queda guardado; Reintentar lo sube', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    Nube.instancia = s.nube = NubeFalsa(error: const SocketException('sin red'));
    await _abrirCamara(tester, _evento(cuenta: 0, duracion: 5));
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await _segundos(tester, 5);
    await _aceptar(tester);
    await _hastaQue(tester, () => _hay(find.textContaining('Sin señal')), 'el aviso sin señal');
    expect(Almacen.instancia.pendientes, hasLength(1));

    // Vuelve la señal.
    Nube.instancia = s.nube = NubeFalsa();
    await tester.tap(_boton('Reintentar subida'));
    await _hastaQue(tester, () => _hay(find.text('Escanea para recibir tu video')), 'el QR');
    expect(Almacen.instancia.pendientes, isEmpty);
    semantica.dispose();
  });

  testWidgets('un invitado pide borrar su video: se borra del celular y de la nube', (tester) async {
    final semantica = tester.ensureSemantics();
    final s = await _preparar(tester);
    await _abrirCamara(tester, _evento(cuenta: 0, duracion: 5));
    await tester.tap(find.bySemanticsLabel('Grabar'));
    await _segundos(tester, 5);
    await _aceptar(tester);
    await _hastaQue(tester, () => _hay(find.text('Escanea para recibir tu video')), 'el QR');
    final v = Almacen.instancia.videos.single;
    await _quieto(tester);

    await tester.tap(find.byTooltip('Más opciones'));
    await _quieto(tester);
    await tester.tap(find.text('Borrar video'));
    await _quieto(tester);
    expect(find.text('¿Borrar este video?'), findsOneWidget);
    await tester.tap(_boton('Borrar'));
    await _hastaQue(tester, () => _hay(find.text('Video borrado.')), 'el aviso de borrado');

    expect(s.nube.borrados, [v.id]);
    expect(Almacen.instancia.videos, isEmpty);
    expect(s.archivosVideos, isEmpty);
    await _hastaQue(tester, () => _hay(find.bySemanticsLabel('Grabar')), 'de vuelta en la cámara');
    semantica.dispose();
  });
}

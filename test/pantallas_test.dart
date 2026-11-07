// Cada pantalla se dibuja en un celular chico, en el Xiaomi 13 Ultra y en una
// tableta, con letra normal, grande y la más grande de Android. Si algo no
// cabe (texto cortado, botones encimados, "overflow"), la prueba falla.
//
// Para ver cómo se ven: CAPTURAS=/carpeta flutter test test/pantallas_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/almacen.dart';
import 'package:marles360/modelos.dart';
import 'package:marles360/pantallas/ajustes.dart';
import 'package:marles360/pantallas/bibliotecas.dart';
import 'package:marles360/pantallas/camara.dart';
import 'package:marles360/pantallas/entrega.dart';
import 'package:marles360/pantallas/evento.dart';
import 'package:marles360/pantallas/evento_form.dart';
import 'package:marles360/pantallas/inicio.dart';
import 'package:marles360/pantallas/vista_previa.dart';
import 'package:marles360/servicios/nube.dart';
import 'package:marles360/servicios/procesador.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'apoyo/entorno.dart';
import 'apoyo/falsos.dart';

late Uint8List _marco;

/// Un evento completo con marco, canción y videos, como en una boda real.
Evento _evento({String id = 'abc234', String nombre = 'Boda de Ana Lucía y José Fernando en Antigua Guatemala'}) {
  final a = Almacen.instancia;
  File('${a.dirMarcos.path}/boda dorada.png').writeAsBytesSync(_marco);
  File('${a.dirMarcos.path}/xv años rosa.png').writeAsBytesSync(_marco);
  File('${a.dirMusica.path}/Perfect - Ed Sheeran (versión vals).mp3').writeAsBytesSync([0]);
  final e = Evento(
    id: id,
    nombre: nombre,
    fecha: DateTime(2026, 11, 14),
    marco: 'boda dorada.png',
    cancion: 'Perfect - Ed Sheeran (versión vals).mp3',
    duracion: 30,
    modo: ModoInicio.temporizador,
    cuentaRegresiva: 3,
  );
  a.eventos.add(e);
  for (var i = 0; i < 4; i++) {
    final f = File('${a.dirVideos.path}/${e.id}_v$i.mp4')..writeAsBytesSync([1, 2, 3]);
    a.videos.add(
      VideoGrabado(
        id: 'v$i$id',
        eventoId: e.id,
        archivo: f.path,
        creado: DateTime(2026, 11, 14, 20, 10 + i),
        estado: i.isEven ? EstadoVideo.subido : EstadoVideo.pendiente,
      ),
    );
  }
  return e;
}

void _nubeLista() {
  Almacen.instancia
    ..servidor = 'https://marles360.marles.workers.dev'
    ..clave = 'una-clave-larga';
}

/// Una pantalla en un estado: cómo se prepara, qué se toca y qué debe verse.
class _Caso {
  const _Caso(this.nombre, this.preparar, {this.accion, this.revisar});
  final String nombre;
  final Widget Function() preparar;
  final Future<void> Function(WidgetTester tester)? accion;
  final void Function(WidgetTester tester)? revisar;
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _boton(String texto) => find.ancestor(of: find.text(texto), matching: find.bySubtype<ButtonStyleButton>());

final _casos = <_Caso>[
  _Caso(
    'inicio_vacio',
    () => const PantallaInicio(),
    revisar: (_) {
      expect(find.text('Crea tu primer evento'), findsOneWidget);
      expect(find.text('Configurar'), findsOneWidget);
    },
  ),
  _Caso(
    'inicio_eventos',
    () {
      _nubeLista();
      _evento();
      _evento(id: 'xv2026', nombre: 'XV años de Sofía');
      return const PantallaInicio();
    },
    revisar: (_) {
      expect(find.text('4 videos esperando señal para subir.'), findsOneWidget);
      expect(find.textContaining('14 nov 2026 · 4 videos'), findsWidgets);
    },
  ),
  _Caso(
    'ajustes_error',
    () {
      Nube.instancia = NubeFalsa(resultadoPrueba: 'No se pudo conectar. Revisa la dirección y que haya internet.');
      return const PantallaAjustes();
    },
    accion: (tester) async {
      await tester.enterText(find.byType(TextField).first, 'marles360.marles.workers.dev');
      await tester.enterText(find.byType(TextField).last, 'clave');
      await _tocar(tester, find.text('Guardar y probar'));
      await esperarA(tester, find.textContaining('No se pudo conectar'));
    },
    revisar: (_) {
      expect(find.textContaining('No se pudo conectar'), findsOneWidget);
      // La dirección sin https:// se corrige sola.
      expect(Almacen.instancia.servidor, 'https://marles360.marles.workers.dev');
    },
  ),
  _Caso('evento_nuevo', () {
    _evento();
    return const PantallaEventoForm();
  }, revisar: (_) => expect(find.bySemanticsLabel('Marco boda dorada.png'), findsOneWidget)),
  _Caso(
    'evento_editar',
    () => PantallaEventoForm(evento: _evento()),
    revisar: (tester) => expect(
      tester.getSemantics(find.bySemanticsLabel('Marco boda dorada.png')),
      isSemantics(isSelected: true, isButton: true),
    ),
  ),
  _Caso('evento', () {
    _nubeLista();
    return PantallaEvento(evento: _evento());
  }, revisar: (_) => expect(find.text('Videos (4)'), findsOneWidget)),
  _Caso(
    'evento_qr_galeria',
    () {
      _nubeLista();
      return PantallaEvento(evento: _evento());
    },
    accion: (tester) async {
      await _tocar(tester, find.byTooltip('Más opciones'));
      await _tocar(tester, find.text('QR de la galería del evento'));
    },
    revisar: (_) {
      expect(find.text('Galería del evento'), findsOneWidget);
      expect(find.text('Compartir enlace'), findsOneWidget);
    },
  ),
  _Caso(
    'evento_borrar',
    () => PantallaEvento(evento: _evento()),
    accion: (tester) async {
      await _tocar(tester, find.byTooltip('Más opciones'));
      await _tocar(tester, find.text('Borrar evento'));
    },
    revisar: (_) => expect(find.text('¿Borrar este evento?'), findsOneWidget),
  ),
  _Caso('bibliotecas_marcos', () {
    _evento();
    return const PantallaBibliotecas();
  }, revisar: (_) => expect(find.text('Lo usa 1 evento'), findsOneWidget)),
  _Caso(
    'bibliotecas_musica',
    () {
      _evento();
      return const PantallaBibliotecas();
    },
    accion: (tester) => _tocar(tester, find.text('Música')),
    revisar: (_) => expect(find.text('Perfect - Ed Sheeran (versión vals).mp3'), findsOneWidget),
  ),
  _Caso('entrega_qr', () {
    _nubeLista();
    final e = _evento();
    final v = Almacen.instancia.videosDe(e.id).firstWhere((v) => v.estado == EstadoVideo.subido);
    return PantallaEntrega(video: v, volverACamara: true);
  }, revisar: (_) => expect(find.text('Escanea para recibir tu video'), findsOneWidget)),
  _Caso('entrega_subiendo', () {
    _nubeLista();
    Nube.instancia = NubeFalsa()..esperar = Completer<void>();
    final e = _evento();
    final v = Almacen.instancia.videosDe(e.id).firstWhere((v) => v.estado == EstadoVideo.pendiente);
    return PantallaEntrega(video: v, volverACamara: true);
  }, revisar: (_) => expect(find.text('Subiendo video…'), findsOneWidget)),
  _Caso(
    'entrega_sin_senal',
    () {
      _nubeLista();
      Nube.instancia = NubeFalsa(error: const SocketException('sin red'));
      final e = _evento();
      final v = Almacen.instancia.videosDe(e.id).firstWhere((v) => v.estado == EstadoVideo.pendiente);
      return PantallaEntrega(video: v, volverACamara: true);
    },
    revisar: (_) {
      expect(find.textContaining('Sin señal. El video quedó guardado'), findsOneWidget);
      expect(find.text('Reintentar subida'), findsOneWidget);
    },
  ),
  _Caso(
    'camara_lista',
    () => PantallaCamara(evento: _evento()..modo = ModoInicio.boton),
    revisar: (_) => expect(find.bySemanticsLabel('Grabar'), findsOneWidget),
  ),
  _Caso(
    'camara_cuenta',
    () => PantallaCamara(evento: _evento()..modo = ModoInicio.boton),
    accion: (tester) => _tocar(tester, find.bySemanticsLabel('Grabar')),
    revisar: (_) => expect(find.text('3'), findsOneWidget),
  ),
  _Caso(
    'camara_espera',
    () => PantallaCamara(evento: _evento()..retrasoTemporizador = 10),
    revisar: (_) => expect(find.text('Empieza en'), findsOneWidget),
  ),
  _Caso(
    'camara_grabando',
    () => PantallaCamara(evento: _evento()..modo = ModoInicio.boton),
    accion: (tester) async {
      await _tocar(tester, find.bySemanticsLabel('Grabar'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 100));
    },
    revisar: (_) {
      expect(find.bySemanticsLabel('Detener grabación'), findsOneWidget);
      expect((CameraPlatform.instance as CamaraFalsa).grabando, isTrue);
    },
  ),
  _Caso('camara_sin_permiso', () {
    CameraPlatform.instance = CamaraFalsa(fallarAlAbrir: true);
    return PantallaCamara(evento: _evento());
  }, revisar: (_) => expect(find.textContaining('no tiene permiso'), findsOneWidget)),
  _Caso('vista_previa_procesando', () {
    Procesador.instancia = ProcesadorFalso()..completar = Completer<void>();
    return PantallaVistaPrevia(evento: _evento(), grabado: _grabacion());
  }, revisar: (tester) => expect(tester.widget<ButtonStyleButton>(_boton('Aceptar')).onPressed, isNull)),
  _Caso(
    'vista_previa_lista',
    () => PantallaVistaPrevia(evento: _evento(), grabado: _grabacion()),
    revisar: (tester) => expect(tester.widget<ButtonStyleButton>(_boton('Aceptar')).onPressed, isNotNull),
  ),
  _Caso('vista_previa_error', () {
    Procesador.instancia = ProcesadorFalso(fallar: true);
    return PantallaVistaPrevia(evento: _evento(), grabado: _grabacion());
  }, revisar: (_) => expect(find.textContaining('No se pudo procesar'), findsOneWidget)),
];

String _grabacion() =>
    (File('${Almacen.instancia.dirVideos.path}/crudo_prueba.mp4')..writeAsBytesSync(List.filled(100, 1))).path;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await cargarFuentes();
    _marco = await pngMarco();
  });

  for (final caso in _casos) {
    for (final p in pantallas) {
      for (final escala in escalasLetra) {
        final nombre = '${caso.nombre}_${p.nombre}_x$escala';
        testWidgets(nombre, (tester) async {
          final semantica = tester.ensureSemantics();
          // Las pruebas de Flutter dibujan las sombras como una raya negra; en las
          // capturas se dibujan de verdad para ver la app como en el celular.
          if (hayCapturas) debugDisableShadows = false;
          ponerPantalla(tester, p, escala);
          late Directory dir;
          await tester.runAsync(() async => dir = await almacenNuevo());
          CameraPlatform.instance = CamaraFalsa(carpeta: dir);
          VideoPlayerPlatform.instance = ReproductorFalso();
          Procesador.instancia = ProcesadorFalso();
          Nube.instancia = NubeFalsa();

          await tester.pumpWidget(app(caso.preparar()));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await caso.accion?.call(tester);
          await cargarImagenes(tester);
          await capturar(tester, nombre);
          caso.revisar?.call(tester);
          expect(palabrasPartidas(tester), isEmpty, reason: 'Hay palabras partidas entre dos líneas');

          // Accesibilidad: todo lo que se toca mide al menos 48 x 48 y dice qué es
          // (lo que lee TalkBack y lo que piden las guías de Android).
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          // Se cierra todo para que no queden relojes ni cámaras abiertas, y se
          // espera a que termine de guardarse lo pendiente antes de borrar la carpeta.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await asentar(tester, vueltas: 4);
          await tester.runAsync(() => dir.delete(recursive: true));
          semantica.dispose();
          debugDisableShadows = true;
        });
      }
    }
  }
}

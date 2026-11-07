// Utilidades comunes de las pruebas de pantallas.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/almacen.dart';
import 'package:marles360/tema.dart';

/// Tamaños de pantalla en los que debe verse bien cada pantalla.
class Pantalla {
  const Pantalla(this.nombre, this.ancho, this.alto, this.densidad);
  final String nombre;
  final double ancho, alto, densidad;
  Size get tamano => Size(ancho, alto);
}

const pantallas = [
  Pantalla('chico', 320, 568, 2), // celular pequeño
  Pantalla('xiaomi', 411, 914, 3.5), // Xiaomi 13 Ultra (1440 x 3200)
  Pantalla('tableta', 800, 1280, 2),
];

/// Tamaños de letra del sistema: normal, grande (MIUI) y el máximo de Android.
const escalasLetra = [1.0, 1.35, 2.0];

/// Carpeta del SDK de Flutter, para usar sus fuentes reales (Roboto e iconos).
String _raizFlutter() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // .../flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester
  var d = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    d = d.parent;
  }
  return d.path;
}

/// Con las fuentes reales los textos miden lo mismo que en el celular; con la
/// fuente de prueba de Flutter cada letra es un cuadro y todo mide de más.
Future<void> cargarFuentes() async {
  final dir = '${_raizFlutter()}/bin/cache/artifacts/material_fonts';
  Future<ByteData> leer(String nombre) async => ByteData.view(File('$dir/$nombre').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(leer('Roboto-Regular.ttf'))
    ..addFont(leer('Roboto-Medium.ttf'))
    ..addFont(leer('Roboto-Bold.ttf'));
  await roboto.load();
  final iconos = FontLoader('MaterialIcons')..addFont(leer('MaterialIcons-Regular.otf'));
  await iconos.load();
}

/// Deja el almacén vacío en una carpeta temporal nueva.
Future<Directory> almacenNuevo() async {
  final dir = await Directory.systemTemp.createTemp('marles_prueba_');
  await Almacen.instancia.cargar(carpeta: dir);
  return dir;
}

/// PNG vertical 1080 x 1920 con borde de color y centro transparente, como un marco real.
Future<Uint8List> pngMarco({int ancho = 1080, int alto = 1920}) async {
  final grabadora = ui.PictureRecorder();
  final lienzo = Canvas(grabadora);
  final pintura = Paint()..color = const Color(0xFFD03A3B);
  lienzo.drawRect(Rect.fromLTWH(0, 0, ancho.toDouble(), 160), pintura);
  lienzo.drawRect(Rect.fromLTWH(0, alto - 220.0, ancho.toDouble(), 220), pintura..color = const Color(0xFF1F7A75));
  final imagen = await grabadora.endRecording().toImage(ancho, alto);
  final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
  return datos!.buffer.asUint8List();
}

/// Pone el tamaño de pantalla y de letra. Se restablece solo al terminar.
void ponerPantalla(WidgetTester tester, Pantalla p, double escala) {
  tester.view.physicalSize = p.tamano * p.densidad;
  tester.view.devicePixelRatio = p.densidad;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

final claveCaptura = GlobalKey();

/// La app con su tema, abierta en [inicio].
Widget app(Widget inicio) => RepaintBoundary(
  key: claveCaptura,
  child: MaterialApp(debugShowCheckedModeBanner: false, theme: temaMarles(), home: inicio),
);

/// Carpeta donde guardar capturas (variable CAPTURAS), o null si no se piden.
final carpetaCapturas = Platform.environment['CAPTURAS'];
bool get hayCapturas => carpetaCapturas != null;

/// Si existe la variable CAPTURAS, guarda una imagen de la pantalla en esa carpeta.
Future<void> capturar(WidgetTester tester, String nombre) async {
  final carpeta = carpetaCapturas;
  if (carpeta == null) return;
  final caja = tester.renderObject<RenderRepaintBoundary>(find.byKey(claveCaptura));
  await tester.runAsync(() async {
    final imagen = await caja.toImage(pixelRatio: tester.view.devicePixelRatio);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    await Directory(carpeta).create(recursive: true);
    await File('$carpeta/$nombre.png').writeAsBytes(datos!.buffer.asUint8List());
  });
}

/// Deja avanzar lo que espera al disco (leer un marco, guardar datos.json).
///
/// La lectura y escritura de archivos es real pero el reloj de la prueba es
/// falso: lo que empezó dentro de la prueba solo avanza con pump(). Por eso se
/// alternan esperas reales cortas con pump() (con precacheImage dentro de
/// runAsync la prueba se quedaba esperando para siempre).
Future<void> asentar(WidgetTester tester, {int vueltas = 8}) async {
  for (var i = 0; i < vueltas; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump();
  }
}

/// Palabras partidas entre dos líneas ("Acepta / r"). Pasa cuando una palabra
/// no cabe en el ancho que le toca; se ve mal aunque no sea un "overflow".
List<String> palabrasPartidas(WidgetTester tester) {
  final letras = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{3,}');
  final partidas = <String>[];
  for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (!p.hasSize) continue;
    final texto = p.text.toPlainText(includeSemanticsLabels: false);
    for (final m in letras.allMatches(texto)) {
      final cajas = p.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
      if (cajas.map((c) => c.top.round()).toSet().length > 1) partidas.add(m.group(0)!);
    }
  }
  return partidas;
}

/// Deja avanzar el disco hasta que aparezca [buscado] (o se acaben las vueltas).
Future<void> esperarA(WidgetTester tester, Finder buscado, {int vueltas = 60}) async {
  for (var i = 0; i < vueltas && buscado.evaluate().isEmpty; i++) {
    await asentar(tester, vueltas: 1);
  }
}

/// Espera a que carguen las imágenes de archivo (marcos) para que salgan en la
/// captura y midan lo que miden de verdad.
Future<void> cargarImagenes(WidgetTester tester) async {
  if (find.byType(Image).evaluate().isNotEmpty) await asentar(tester);
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../almacen.dart';

/// Formatos de audio que se pueden importar a la biblioteca de música.
const extensionesMusica = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'];

/// Abre el selector de archivos y copia el marco PNG elegido a la biblioteca.
/// Devuelve su nombre, o null si no se eligió nada o no se pudo.
Future<String?> importarMarco(BuildContext context) async {
  final nombre = await _importar(context, ['png'], Almacen.instancia.dirMarcos);
  if (nombre == null || !context.mounted) return nombre;
  // Un marco que no es vertical 9:16 sale estirado: se avisa al importarlo.
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(Almacen.instancia.rutaMarco(nombre)!);
    final imagen = await ui.ImageDescriptor.encoded(buffer);
    final proporcion = imagen.width / imagen.height;
    imagen.dispose();
    buffer.dispose();
    if ((proporcion - 9 / 16).abs() > 0.03 && context.mounted) {
      _avisar(
        context,
        'Este marco mide ${imagen.width} x ${imagen.height}. Lo ideal es vertical 1080 x 1920; '
        'si no, se verá estirado.',
      );
    }
  } catch (_) {
    if (context.mounted) _avisar(context, 'No se pudo leer el marco. Revisa que sea un PNG válido.');
  }
  return nombre;
}

/// Igual que [importarMarco], para canciones.
Future<String?> importarCancion(BuildContext context) =>
    _importar(context, extensionesMusica, Almacen.instancia.dirMusica);

Future<String?> _importar(BuildContext context, List<String> extensiones, Directory destino) async {
  try {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensiones);
    final ruta = f?.path;
    if (ruta == null) return null;
    final ext = ruta.split('.').last.toLowerCase();
    if (!extensiones.contains(ext)) {
      if (context.mounted) _avisar(context, 'Ese archivo no es ${extensiones.join(', ').toUpperCase()}.');
      return null;
    }
    return await Almacen.instancia.importar(ruta, destino);
  } catch (_) {
    if (context.mounted) _avisar(context, 'No se pudo importar el archivo.');
    return null;
  } finally {
    // El selector deja una copia de cada archivo elegido; ya está en la biblioteca.
    await FilePicker.clearTemporaryFiles().catchError((_) {});
  }
}

void _avisar(BuildContext context, String texto) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

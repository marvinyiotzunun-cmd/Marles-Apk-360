import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../almacen.dart';
import '../tema.dart';
import '../utiles/medidas.dart';
import 'importar.dart';

/// Marcos y canciones guardados en el celular.
class PantallaBibliotecas extends StatelessWidget {
  const PantallaBibliotecas({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Almacen.instancia;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliotecas'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Marcos'),
              Tab(text: 'Música'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: a,
          builder: (context, _) => TabBarView(
            children: [
              _Lista(
                archivos: a.marcos,
                vacio: 'Importa marcos PNG verticales (1080 x 1920) con el centro transparente.',
                textoBoton: 'Importar marco',
                importar: importarMarco,
                enUso: (nombre) => a.eventos.where((e) => e.marco == nombre).length,
                miniatura: (f) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 36,
                    height: 64,
                    color: Marles.turquesaPalido,
                    child: Image.file(f, fit: BoxFit.cover, cacheWidth: 108),
                  ),
                ),
              ),
              _Lista(
                archivos: a.canciones,
                vacio: 'Importa canciones MP3, M4A, WAV u OGG.',
                textoBoton: 'Importar canción',
                importar: importarCancion,
                enUso: (nombre) => a.eventos.where((e) => e.cancion == nombre).length,
                miniatura: (_) =>
                    const SizedBox(width: 36, child: Icon(Icons.music_note, color: Marles.turquesaProfundo)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.archivos,
    required this.vacio,
    required this.textoBoton,
    required this.importar,
    required this.enUso,
    required this.miniatura,
  });
  final List<File> archivos;
  final String vacio;
  final String textoBoton;
  final Future<String?> Function(BuildContext) importar;

  /// Cuántos eventos usan el archivo, para avisar antes de borrarlo.
  final int Function(String nombre) enUso;
  final Widget Function(File) miniatura;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: textoBoton,
        backgroundColor: Marles.rojo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(textoBoton),
        onPressed: () => unawaited(importar(context)),
      ),
      body: archivos.isEmpty
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Text(
                  vacio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Marles.tintaSuave),
                ),
              ),
            )
          : ListView(
              // Abajo queda espacio para que el botón de importar no tape el último archivo.
              padding: margenes(context, lado: 0, arriba: 8, abajo: 88 + 28 * escalaLetra(context)),
              children: [
                for (final f in archivos)
                  ListTile(
                    leading: miniatura(f),
                    title: Text(nombreDe(f.path), overflow: TextOverflow.ellipsis, maxLines: 2),
                    subtitle: _subtitulo(nombreDe(f.path)),
                    trailing: IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => unawaited(_eliminar(context, f)),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget? _subtitulo(String nombre) {
    final n = enUso(nombre);
    if (n == 0) return null;
    return Text(n == 1 ? 'Lo usa 1 evento' : 'Lo usan $n eventos');
  }

  Future<void> _eliminar(BuildContext context, File f) async {
    final nombre = nombreDe(f.path);
    final n = enUso(nombre);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Eliminar $nombre?'),
        content: n == 0
            ? null
            : Text(
                n == 1
                    ? 'Un evento lo usa. Sus próximos videos saldrán sin él.'
                    : '$n eventos lo usan. Sus próximos videos saldrán sin él.',
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) await Almacen.instancia.eliminar(f);
  }
}

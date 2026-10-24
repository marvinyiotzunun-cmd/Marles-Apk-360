import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../almacen.dart';
import '../tema.dart';
import 'evento_form.dart';

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
          bottom: const TabBar(tabs: [Tab(text: 'Marcos'), Tab(text: 'Música')]),
        ),
        body: ListenableBuilder(
          listenable: a,
          builder: (context, _) => TabBarView(
            children: [
              _Lista(
                archivos: a.marcos,
                vacio: 'Importa marcos PNG verticales (1080 x 1920) con el centro transparente.',
                importar: () async {
                  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['png']);
                  if (f?.path != null) await a.importar(f!.path!, a.dirMarcos);
                },
                miniatura: (f) => Image.file(f, width: 48, height: 85, fit: BoxFit.cover),
              ),
              _Lista(
                archivos: a.canciones,
                vacio: 'Importa canciones MP3, M4A, WAV u OGG.',
                importar: () async {
                  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensionesMusica);
                  if (f?.path != null) await a.importar(f!.path!, a.dirMusica);
                },
                miniatura: (_) => const Icon(Icons.music_note, color: Marles.turquesaProfundo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.archivos, required this.vacio, required this.importar, required this.miniatura});
  final List<File> archivos;
  final String vacio;
  final Future<void> Function() importar;
  final Widget Function(File) miniatura;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Marles.rojo,
        foregroundColor: Colors.white,
        onPressed: importar,
        child: const Icon(Icons.add),
      ),
      body: archivos.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(vacio, textAlign: TextAlign.center, style: const TextStyle(color: Marles.tintaSuave)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final f in archivos)
                  ListTile(
                    leading: miniatura(f),
                    title: Text(nombreDe(f.path)),
                    trailing: IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text('¿Eliminar ${nombreDe(f.path)}?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
                            ],
                          ),
                        );
                        if (ok == true) await Almacen.instancia.eliminar(f);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';
import '../utiles/formato.dart';
import '../utiles/medidas.dart';
import 'ajustes.dart';
import 'bibliotecas.dart';
import 'evento.dart';
import 'evento_form.dart';

class PantallaInicio extends StatelessWidget {
  const PantallaInicio({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Almacen.instancia;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        // Primero los más recientes; con la misma fecha, por nombre (orden fijo).
        final eventos = [...a.eventos]
          ..sort((x, y) {
            final porFecha = y.fecha.compareTo(x.fecha);
            return porFecha != 0 ? porFecha : x.nombre.compareTo(y.nombre);
          });
        final pendientes = a.pendientes.length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Marles 360', style: TextStyle(fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Marcos y música',
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: () => _ir(context, const PantallaBibliotecas()),
              ),
              IconButton(
                tooltip: 'Ajustes',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _ir(context, const PantallaAjustes()),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Marles.rojo,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo evento'),
            onPressed: () async {
              final e = await Navigator.of(context)
                  .push<Evento>(MaterialPageRoute(builder: (_) => const PantallaEventoForm()));
              if (e != null && context.mounted) _ir(context, PantallaEvento(evento: e));
            },
          ),
          body: ListView(
            // Abajo queda espacio para que el botón "Nuevo evento" no tape el último evento.
            padding: margenes(context, arriba: 8, abajo: 88 + 28 * escalaLetra(context)),
            children: [
              if (!a.nubeLista)
                _Aviso(
                  color: Marles.amarillo,
                  texto: 'Falta conectar la nube para entregar videos por QR.',
                  boton: 'Configurar',
                  alTocar: () => _ir(context, const PantallaAjustes()),
                ),
              if (a.nubeLista && pendientes > 0)
                _Aviso(
                  color: Marles.turquesaPalido,
                  texto: '${cantidad(pendientes, 'video')} esperando señal para subir.',
                  boton: 'Subir ahora',
                  alTocar: () => unawaited(_subirAhora(context)),
                ),
              if (eventos.isEmpty) const _SinEventos(),
              for (final e in eventos)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: const CircleAvatar(
                      backgroundColor: Marles.turquesaPalido,
                      foregroundColor: Marles.turquesaProfundo,
                      child: Icon(Icons.celebration_outlined),
                    ),
                    title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${fechaCorta(e.fecha)} · ${cantidad(a.videosDe(e.id).length, 'video')}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ir(context, PantallaEvento(evento: e)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _subirAhora(BuildContext context) async {
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.showSnackBar(const SnackBar(content: Text('Subiendo videos pendientes…')));
    final n = await Nube.instancia.subirPendientes();
    mensajero
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(n > 0 ? 'Se ${n == 1 ? 'subió' : 'subieron'} ${cantidad(n, 'video')}.' : 'Aún sin señal.'),
        ),
      );
  }

  void _ir(BuildContext context, Widget p) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => p)));
}

class _SinEventos extends StatelessWidget {
  const _SinEventos();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.08),
      child: const Column(
        children: [
          Icon(Icons.threesixty, size: 72, color: Marles.turquesaProfundo),
          SizedBox(height: 12),
          Text(
            'Crea tu primer evento',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            Marles.lema,
            textAlign: TextAlign.center,
            style: TextStyle(color: Marles.tintaSuave),
          ),
          SizedBox(height: 4),
          Text(
            'Toca "Nuevo evento" para elegir marco, canción y duración.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Marles.tintaSuave),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.texto, required this.boton, required this.alTocar});
  final Color color;
  final String texto;
  final String boton;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final escala = escalaLetra(context);
    final accion = TextButton(onPressed: alTocar, child: Text(boton));
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: LayoutBuilder(
          builder: (context, caja) {
            // Si al lado del botón el texto quedaría en una columna delgada (con
            // letra grande partía "esperando" en "espera-ndo"), el botón va abajo.
            final anchoBoton = 24 + boton.length * 8.0 * escala;
            if (caja.maxWidth - anchoBoton >= 140 * escala) {
              return Row(
                children: [
                  Expanded(child: Text(texto)),
                  const SizedBox(width: 8),
                  accion,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: const EdgeInsets.only(top: 4, right: 8), child: Text(texto)),
                Align(alignment: Alignment.centerRight, child: accion),
              ],
            );
          },
        ),
      ),
    );
  }
}

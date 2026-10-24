import 'package:flutter/material.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../servicios/nube.dart';
import '../tema.dart';
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
        final eventos = [...a.eventos]..sort((x, y) => y.fecha.compareTo(x.fecha));
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
              final e = await Navigator.of(context).push<Evento>(
                MaterialPageRoute(builder: (_) => const PantallaEventoForm()),
              );
              if (e != null && context.mounted) _ir(context, PantallaEvento(evento: e));
            },
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
                  texto: '$pendientes video(s) esperando señal para subir.',
                  boton: 'Subir ahora',
                  alTocar: () async {
                    final n = await Nube.instancia.subirPendientes();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(n > 0 ? 'Se subieron $n video(s)' : 'Aún sin señal')),
                      );
                    }
                  },
                ),
              if (eventos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Column(
                    children: [
                      Icon(Icons.threesixty, size: 72, color: Marles.turquesa),
                      SizedBox(height: 12),
                      Text('Crea tu primer evento', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text(Marles.lema, style: TextStyle(color: Marles.tintaSuave)),
                    ],
                  ),
                ),
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
                    subtitle: Text('${fechaCorta(e.fecha)} · ${a.videosDe(e.id).length} videos'),
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

  void _ir(BuildContext context, Widget p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => p));
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.texto, required this.boton, required this.alTocar});
  final Color color;
  final String texto;
  final String boton;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(child: Text(texto)),
            TextButton(onPressed: alTocar, child: Text(boton)),
          ],
        ),
      ),
    );
  }
}

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
String fechaCorta(DateTime f) => '${f.day} ${_meses[f.month - 1]} ${f.year}';

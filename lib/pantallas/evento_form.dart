import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../tema.dart';
import 'inicio.dart';

const extensionesMusica = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'];

/// Crear o editar un evento. Al crear, devuelve el evento nuevo.
class PantallaEventoForm extends StatefulWidget {
  const PantallaEventoForm({super.key, this.evento});
  final Evento? evento;

  @override
  State<PantallaEventoForm> createState() => _PantallaEventoFormState();
}

class _PantallaEventoFormState extends State<PantallaEventoForm> {
  final a = Almacen.instancia;
  late final Evento e = widget.evento == null
      ? Evento(id: nuevoId(6), nombre: '', fecha: DateTime.now())
      : Evento.fromJson(widget.evento!.toJson());
  late final _nombre = TextEditingController(text: e.nombre);
  late final _inicio = TextEditingController(text: '${e.cancionInicio}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.evento == null ? 'Nuevo evento' : 'Configurar evento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre del evento', hintText: 'Boda de Ana y Luis'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(fechaCorta(e.fecha)),
            trailing: const Text('Cambiar'),
            onTap: () async {
              final f = await showDatePicker(
                context: context,
                initialDate: e.fecha,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
              );
              if (f != null) setState(() => e.fecha = f);
            },
          ),
          _titulo('Marco'),
          _selectorMarco(),
          _titulo('Canción'),
          _selectorCancion(),
          if (e.cancion != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _inicio,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Empezar la canción en el segundo', suffixText: 's'),
            ),
            const SizedBox(height: 8),
            Text('Audio original de la grabación: ${e.volumenOriginal == 0 ? 'apagado' : '${e.volumenOriginal}%'}'),
            Slider(
              value: e.volumenOriginal.toDouble(),
              max: 100,
              divisions: 10,
              onChanged: (v) => setState(() => e.volumenOriginal = v.round()),
            ),
          ],
          _titulo('Grabación'),
          Text('Duración: ${_duracionTexto(e.duracion)}'),
          Slider(
            value: e.duracion.toDouble(),
            min: 5,
            max: 180,
            divisions: 35,
            label: _duracionTexto(e.duracion),
            onChanged: (v) => setState(() => e.duracion = v.round()),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ModoInicio>(
            segments: const [
              ButtonSegment(value: ModoInicio.boton, label: Text('Botón'), icon: Icon(Icons.touch_app_outlined)),
              ButtonSegment(value: ModoInicio.temporizador, label: Text('Temporizador'), icon: Icon(Icons.timer_outlined)),
            ],
            selected: {e.modo},
            onSelectionChanged: (s) => setState(() => e.modo = s.first),
          ),
          const SizedBox(height: 4),
          Text(
            e.modo == ModoInicio.boton
                ? 'Tocas el botón (o el control Bluetooth) y empieza la cuenta regresiva.'
                : 'La cámara empieza sola ${e.retrasoTemporizador} s después de abrirla o de entregar el video anterior.',
            style: const TextStyle(color: Marles.tintaSuave),
          ),
          if (e.modo == ModoInicio.temporizador) ...[
            const SizedBox(height: 8),
            _chips('Espera antes de empezar', [5, 10, 15, 20, 30], e.retrasoTemporizador,
                (v) => e.retrasoTemporizador = v),
          ],
          const SizedBox(height: 8),
          _chips('Cuenta regresiva', [0, 3, 5, 10], e.cuentaRegresiva, (v) => e.cuentaRegresiva = v),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar cámara frontal'),
            value: e.camaraFrontal,
            onChanged: (v) => setState(() => e.camaraFrontal = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _guardar, child: const Text('Guardar')),
        ],
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );

  Widget _chips(String titulo, List<int> valores, int actual, void Function(int) poner) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('$titulo:'),
        for (final v in valores)
          ChoiceChip(
            label: Text(v == 0 ? 'No' : '$v s'),
            selected: actual == v,
            onSelected: (_) => setState(() => poner(v)),
          ),
      ],
    );
  }

  Widget _selectorMarco() {
    final marcos = a.marcos;
    return SizedBox(
      height: 168,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _miniatura(
            seleccionado: e.marco == null,
            alTocar: () => setState(() => e.marco = null),
            child: const Center(child: Text('Sin marco')),
          ),
          for (final f in marcos)
            _miniatura(
              seleccionado: e.marco == nombreDe(f.path),
              alTocar: () => setState(() => e.marco = nombreDe(f.path)),
              child: Image.file(f, fit: BoxFit.cover),
            ),
          _miniatura(
            seleccionado: false,
            alTocar: () async {
              final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['png']);
              if (f?.path == null) return;
              final nombre = await a.importar(f!.path!, a.dirMarcos);
              setState(() => e.marco = nombre);
            },
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.add_photo_alternate_outlined), Text('Importar PNG')],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniatura({required bool seleccionado, required VoidCallback alTocar, required Widget child}) {
    return GestureDetector(
      onTap: alTocar,
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Marles.turquesaPalido,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: seleccionado ? Marles.rojo : Colors.transparent, width: 3),
        ),
        child: child,
      ),
    );
  }

  Widget _selectorCancion() {
    final canciones = a.canciones.map((f) => nombreDe(f.path)).toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: canciones.contains(e.cancion) ? e.cancion : null,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin canción')),
              for (final c in canciones) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => e.cancion = v),
          ),
        ),
        IconButton(
          tooltip: 'Importar canción',
          icon: const Icon(Icons.library_music_outlined),
          onPressed: () async {
            final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensionesMusica);
            if (f?.path == null) return;
            final nombre = await a.importar(f!.path!, a.dirMusica);
            setState(() => e.cancion = nombre);
          },
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    e.nombre = _nombre.text.trim().isEmpty ? 'Evento ${fechaCorta(e.fecha)}' : _nombre.text.trim();
    e.cancionInicio = int.tryParse(_inicio.text) ?? 0;
    final original = widget.evento;
    if (original == null) {
      a.eventos.add(e);
    } else {
      original.copiarDe(e);
    }
    await a.guardar();
    if (mounted) Navigator.of(context).pop(original ?? e);
  }
}

String _duracionTexto(int s) => s < 60 ? '$s s' : '${s ~/ 60} min${s % 60 == 0 ? '' : ' ${s % 60} s'}';

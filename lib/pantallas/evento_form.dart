import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../almacen.dart';
import '../modelos.dart';
import '../tema.dart';
import '../utiles/formato.dart';
import '../utiles/medidas.dart';
import 'importar.dart';

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
      // 10 letras: la dirección de la galería no se puede adivinar probando.
      ? Evento(id: nuevoId(10), nombre: '', fecha: DateTime.now())
      : Evento.fromJson(widget.evento!.toJson());
  late final _nombre = TextEditingController(text: e.nombre);
  late final _inicio = TextEditingController(text: '${e.cancionInicio}');

  /// Cómo estaba el formulario al abrirlo, para avisar si se sale sin guardar.
  late final String _inicial;

  /// true desde que se toca Guardar: un segundo toque no lo agrega dos veces.
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Si el marco o la canción se borraron de la biblioteca, el formulario lo
    // muestra como "sin marco" / "sin canción" en vez de guardar algo que no existe.
    if (a.falta(a.rutaMarco(e.marco))) e.marco = null;
    if (a.falta(a.rutaCancion(e.cancion))) e.cancion = null;
    _inicial = _foto();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _inicio.dispose();
    super.dispose();
  }

  String _foto() => jsonEncode([e.toJson(), _nombre.text, _inicio.text]);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (hecho, _) {
        if (!hecho) unawaited(_salir());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.evento == null ? 'Nuevo evento' : 'Configurar evento')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: margenes(context, arriba: 8, abajo: 12),
            child: FilledButton(onPressed: _guardar, child: const Text('Guardar')),
          ),
        ),
        body: ListView(
          padding: margenes(context, arriba: 8, abajo: 24),
          children: [
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Nombre del evento',
                hintText: 'Boda de Ana y Luis',
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(fechaCorta(e.fecha)),
              trailing: const Text('Cambiar', style: TextStyle(color: Marles.rojo)),
              onTap: _elegirFecha,
            ),
            _titulo('Marco'),
            _selectorMarco(),
            _titulo('Canción'),
            _selectorCancion(),
            if (e.cancion != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _inicio,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: const InputDecoration(labelText: 'Empezar la canción en el segundo', suffixText: 's'),
              ),
              const SizedBox(height: 12),
              Text('Audio original de la grabación: ${e.volumenOriginal == 0 ? 'apagado' : '${e.volumenOriginal}%'}'),
              Slider(
                value: e.volumenOriginal.toDouble(),
                max: 100,
                divisions: 10,
                label: '${e.volumenOriginal}%',
                onChanged: (v) => setState(() => e.volumenOriginal = v.round()),
              ),
            ],
            _titulo('Grabación'),
            Text('Duración: ${duracionTexto(e.duracion)}'),
            Slider(
              value: e.duracion.toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              label: duracionTexto(e.duracion),
              onChanged: (v) => setState(() => e.duracion = v.round()),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ModoInicio>(
              segments: const [
                ButtonSegment(
                  value: ModoInicio.boton,
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text('Botón')),
                  icon: Icon(Icons.touch_app_outlined),
                ),
                ButtonSegment(
                  value: ModoInicio.temporizador,
                  // Con letra grande se achica en vez de partirse ("Temporiza / dor").
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text('Temporizador')),
                  icon: Icon(Icons.timer_outlined),
                ),
              ],
              selected: {e.modo},
              onSelectionChanged: (s) => setState(() => e.modo = s.first),
            ),
            const SizedBox(height: 6),
            Text(
              e.modo == ModoInicio.boton
                  ? 'Tocas el botón (o el control Bluetooth) y empieza la cuenta regresiva.'
                  : 'La cámara empieza sola ${e.retrasoTemporizador} s después de abrirla o de entregar el video anterior.',
              style: const TextStyle(color: Marles.tintaSuave),
            ),
            if (e.modo == ModoInicio.temporizador) ...[
              const SizedBox(height: 12),
              _chips(
                'Espera antes de empezar',
                [5, 10, 15, 20, 30],
                e.retrasoTemporizador,
                (v) => e.retrasoTemporizador = v,
              ),
            ],
            const SizedBox(height: 12),
            _chips('Cuenta regresiva', [0, 3, 5, 10], e.cuentaRegresiva, (v) => e.cuentaRegresiva = v),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usar cámara frontal'),
              value: e.camaraFrontal,
              onChanged: (v) => setState(() => e.camaraFrontal = v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: e.fecha,
      firstDate: e.fecha.isBefore(DateTime(2024)) ? e.fecha : DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (f != null && mounted) setState(() => e.fecha = f);
  }

  Widget _titulo(String t) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
  );

  Widget _chips(String titulo, List<int> valores, int actual, void Function(int) poner) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
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
    // Alto de la fila según la letra del sistema, para que el texto quepa.
    final alto = 160 + 20 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: alto,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _miniatura(
                etiqueta: 'Sin marco',
                seleccionado: e.marco == null,
                alTocar: () => setState(() => e.marco = null),
                child: const _Rotulo(texto: 'Sin\nmarco'),
              ),
              for (final f in marcos)
                _miniatura(
                  etiqueta: 'Marco ${nombreDe(f.path)}',
                  seleccionado: e.marco == nombreDe(f.path),
                  alTocar: () => setState(() => e.marco = nombreDe(f.path)),
                  child: Image.file(f, fit: BoxFit.cover, cacheWidth: 270),
                ),
              _miniatura(
                etiqueta: 'Importar marco PNG',
                seleccionado: false,
                alTocar: () async {
                  final nombre = await importarMarco(context);
                  if (nombre != null && mounted) setState(() => e.marco = nombre);
                },
                child: const _Rotulo(texto: 'Importar\nPNG', icono: Icons.add_photo_alternate_outlined),
              ),
            ],
          ),
        ),
        if (e.marco != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              e.marco!,
              style: const TextStyle(color: Marles.tintaSuave),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// [etiqueta] es lo que lee TalkBack (una imagen sola no dice qué marco es).
  Widget _miniatura({
    required String etiqueta,
    required bool seleccionado,
    required VoidCallback alTocar,
    required Widget child,
  }) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: etiqueta,
      selected: seleccionado,
      button: true,
      onTap: alTocar,
      child: GestureDetector(
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
      ),
    );
  }

  Widget _selectorCancion() {
    final canciones = a.canciones.map((f) => nombreDe(f.path)).toList();
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            // La clave hace que se vea la canción recién importada.
            key: ValueKey(e.cancion),
            initialValue: canciones.contains(e.cancion) ? e.cancion : null,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin canción')),
              for (final c in canciones)
                DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => e.cancion = v),
          ),
        ),
        IconButton(
          tooltip: 'Importar canción',
          icon: const Icon(Icons.library_music_outlined),
          onPressed: () async {
            final nombre = await importarCancion(context);
            if (nombre != null && mounted) setState(() => e.cancion = nombre);
          },
        ),
      ],
    );
  }

  /// Al salir sin guardar, pregunta antes de perder los cambios.
  Future<void> _salir() async {
    if (_foto() == _inicial) {
      Navigator.of(context).pop();
      return;
    }
    final salir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Los cambios de este evento se perderán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    if (salir == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    _guardando = true;
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

/// Texto de una miniatura sin imagen. Con letra grande se achica para caber
/// entero, en vez de partir palabras ("Impor-tar").
class _Rotulo extends StatelessWidget {
  const _Rotulo({required this.texto, this.icono});
  final String texto;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono != null) ...[Icon(icono, color: Marles.turquesaProfundo), const SizedBox(height: 4)],
              Text(texto, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

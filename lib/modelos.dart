import 'dart:math';

String nuevoId([int largo = 8]) {
  const letras = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(largo, (_) => letras[r.nextInt(letras.length)]).join();
}

enum ModoInicio { boton, temporizador }

/// Configuración de un evento: se aplica igual a cada video.
class Evento {
  Evento({
    required this.id,
    required this.nombre,
    required this.fecha,
    this.marco,
    this.cancion,
    this.cancionInicio = 0,
    this.duracion = 15,
    this.cuentaRegresiva = 3,
    this.modo = ModoInicio.boton,
    this.retrasoTemporizador = 10,
    this.volumenOriginal = 0,
    this.camaraFrontal = false,
  });

  final String id;
  String nombre;
  DateTime fecha;

  /// Nombre de archivo dentro de la biblioteca de marcos.
  String? marco;

  /// Nombre de archivo dentro de la biblioteca de música.
  String? cancion;

  /// Segundo de la canción desde el que empieza a sonar.
  int cancionInicio;

  /// Segundos que dura cada video (5 a 180).
  int duracion;
  int cuentaRegresiva;
  ModoInicio modo;

  /// Segundos de espera antes de empezar en modo temporizador.
  int retrasoTemporizador;

  /// 0 = solo la canción, 100 = audio original al mismo volumen.
  int volumenOriginal;
  bool camaraFrontal;

  /// Copia la configuración de otro evento (todo menos el id).
  void copiarDe(Evento o) {
    nombre = o.nombre;
    fecha = o.fecha;
    marco = o.marco;
    cancion = o.cancion;
    cancionInicio = o.cancionInicio;
    duracion = o.duracion;
    cuentaRegresiva = o.cuentaRegresiva;
    modo = o.modo;
    retrasoTemporizador = o.retrasoTemporizador;
    volumenOriginal = o.volumenOriginal;
    camaraFrontal = o.camaraFrontal;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'fecha': fecha.toIso8601String(),
    'marco': marco,
    'cancion': cancion,
    'cancionInicio': cancionInicio,
    'duracion': duracion,
    'cuentaRegresiva': cuentaRegresiva,
    'modo': modo.name,
    'retrasoTemporizador': retrasoTemporizador,
    'volumenOriginal': volumenOriginal,
    'camaraFrontal': camaraFrontal,
  };

  factory Evento.fromJson(Map<String, dynamic> j) => Evento(
    id: j['id'],
    nombre: j['nombre'],
    fecha: DateTime.parse(j['fecha']),
    marco: j['marco'],
    cancion: j['cancion'],
    cancionInicio: j['cancionInicio'] ?? 0,
    duracion: j['duracion'] ?? 15,
    cuentaRegresiva: j['cuentaRegresiva'] ?? 3,
    modo: ModoInicio.values.byName(j['modo'] ?? 'boton'),
    retrasoTemporizador: j['retrasoTemporizador'] ?? 10,
    volumenOriginal: j['volumenOriginal'] ?? 0,
    camaraFrontal: j['camaraFrontal'] ?? false,
  );
}

enum EstadoVideo { pendiente, subiendo, subido }

class VideoGrabado {
  VideoGrabado({
    required this.id,
    required this.eventoId,
    required this.archivo,
    required this.creado,
    this.estado = EstadoVideo.pendiente,
  });

  final String id;
  final String eventoId;

  /// Ruta del video final (con marco y música).
  final String archivo;
  final DateTime creado;
  EstadoVideo estado;

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventoId': eventoId,
    'archivo': archivo,
    'creado': creado.toIso8601String(),
    'estado': estado == EstadoVideo.subido ? 'subido' : 'pendiente',
  };

  factory VideoGrabado.fromJson(Map<String, dynamic> j) => VideoGrabado(
    id: j['id'],
    eventoId: j['eventoId'],
    archivo: j['archivo'],
    creado: DateTime.parse(j['creado']),
    estado: j['estado'] == 'subido' ? EstadoVideo.subido : EstadoVideo.pendiente,
  );
}

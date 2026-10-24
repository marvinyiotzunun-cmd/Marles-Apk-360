import 'package:flutter_test/flutter_test.dart';
import 'package:marles360/modelos.dart';

void main() {
  test('el evento se guarda y se lee igual', () {
    final e = Evento(
      id: 'abc123',
      nombre: 'Boda de Ana y Luis',
      fecha: DateTime(2026, 11, 14),
      marco: 'boda.png',
      cancion: 'vals.mp3',
      cancionInicio: 42,
      duracion: 30,
      modo: ModoInicio.temporizador,
      volumenOriginal: 20,
    );
    final copia = Evento.fromJson(e.toJson());
    expect(copia.toJson(), e.toJson());
  });

  test('copiarDe conserva el id', () {
    final e = Evento(id: 'uno111', nombre: 'A', fecha: DateTime(2026));
    e.copiarDe(Evento(id: 'dos222', nombre: 'B', fecha: DateTime(2027), duracion: 60));
    expect(e.id, 'uno111');
    expect(e.nombre, 'B');
    expect(e.duracion, 60);
  });

  test('los ids sirven para el servidor', () {
    final valido = RegExp(r'^[a-z0-9]{4,16}$');
    for (var i = 0; i < 200; i++) {
      expect(valido.hasMatch(nuevoId()), isTrue);
      expect(valido.hasMatch(nuevoId(6)), isTrue);
    }
  });

  test('un video subido se recuerda como subido', () {
    final v = VideoGrabado(id: 'v1v1v1v1', eventoId: 'abc123', archivo: '/x.mp4', creado: DateTime(2026));
    v.estado = EstadoVideo.subido;
    expect(VideoGrabado.fromJson(v.toJson()).estado, EstadoVideo.subido);
    v.estado = EstadoVideo.subiendo;
    expect(VideoGrabado.fromJson(v.toJson()).estado, EstadoVideo.pendiente);
  });
}

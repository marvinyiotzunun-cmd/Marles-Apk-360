/// Textos con fechas, horas y cantidades, iguales en todas las pantallas.
library;

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// 14 nov 2026
String fechaCorta(DateTime f) => '${f.day} ${_meses[f.month - 1]} ${f.year}';

/// 09:05
String horaCorta(DateTime f) => '${_dos(f.hour)}:${_dos(f.minute)}';

/// 45 s, 1 min, 2 min 30 s
String duracionTexto(int segundos) {
  if (segundos < 60) return '$segundos s';
  final resto = segundos % 60;
  return '${segundos ~/ 60} min${resto == 0 ? '' : ' $resto s'}';
}

/// Reloj de grabación: 0:09, 2:30
String reloj(int segundos) => '${segundos ~/ 60}:${_dos(segundos % 60)}';

/// 1 video, 3 videos
String cantidad(int n, String singular, [String? plural]) => '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

String _dos(int n) => n.toString().padLeft(2, '0');

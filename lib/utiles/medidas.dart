import 'dart:math';

import 'package:flutter/widgets.dart';

/// Ancho máximo del contenido. En una tableta las listas y botones no se
/// estiran de orilla a orilla; en el celular no cambia nada.
const anchoMaximo = 640.0;

/// Márgenes que centran el contenido en pantallas anchas.
EdgeInsets margenes(BuildContext context, {double arriba = 16, double abajo = 16, double lado = 16}) {
  final h = max(lado, (MediaQuery.sizeOf(context).width - anchoMaximo) / 2);
  return EdgeInsets.fromLTRB(h, arriba, h, abajo);
}

/// Cuánto agranda la letra el sistema (1.0 = normal).
double escalaLetra(BuildContext context) => MediaQuery.textScalerOf(context).scale(1);

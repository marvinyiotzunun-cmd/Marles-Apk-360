import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'almacen.dart';
import 'pantallas/inicio.dart';
import 'servicios/nube.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Almacen.instancia.cargar();
  runApp(const MarlesApp());

  // Cuando vuelve la señal, se suben solos los videos pendientes.
  Connectivity().onConnectivityChanged.listen((estado) {
    if (!estado.contains(ConnectivityResult.none)) {
      Nube.instancia.subirPendientes();
    }
  });
  unawaited(Nube.instancia.subirPendientes());
}

class MarlesApp extends StatelessWidget {
  const MarlesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marles APK 360',
      debugShowCheckedModeBanner: false,
      theme: temaMarles(),
      home: const PantallaInicio(),
    );
  }
}

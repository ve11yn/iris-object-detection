import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iris/object-detection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iris',
      theme: ThemeData(
        primaryColor: Color(0xFFC9DCFF),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: MaterialColor(
            0xFFC9DCFF,
            <int, Color>{
              50: Color(0xFFEFF6FB),
              100: Color(0xFFD6E9F7),
              200: Color(0xFFC9DCFF),
              300: Color(0xFFA3C8F0),
              400: Color(0xFF7DB3E1),
              500: Color(0xFF589ED2),
              600: Color(0xFF4285B6),
              700: Color(0xFF316A91),
              800: Color(0xFF21506C),
              900: Color(0xFF102547),
            },
          ),
        ),
      ),
      home: ObjectDetection(cameras: cameras),
    );
  }
}

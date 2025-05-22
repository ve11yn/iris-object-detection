import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';
import 'package:image/image.dart' as img;

class ObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ObjectDetection({super.key, required this.cameras});

  @override
  State<ObjectDetection> createState() => _ObjectDetectionState();
}

class _ObjectDetectionState extends State<ObjectDetection> {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String result = "Detecting...";
  bool isDetecting = false;
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;

  // tflite
  late Interpreter _interpreter;
  late List<String> _labels;

  Future<void> loadModel() async {
    final interpreterOptions = InterpreterOptions();
    _interpreter = await Interpreter.fromAsset('assets/model/object-detection.tflite', options: interpreterOptions);
    final labelData = await rootBundle.loadString('assets/model/label.txt');
    _labels = labelData.split('\n');
  }

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    loadModel();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController.initialize();

      if (!mounted) return;
      setState(() {
        isCameraReady = true;
        result = "Camera ready. Tap to detect objects.";
      });
    } catch (e) {
      setState(() {
        result = "Camera error: $e";
      });
      print("Camera error: $e");
    }
  }

  Future<void> _detectObjects() async {
    if (isDetecting) return;

    setState(() {
      isDetecting = true;
      result = "Processing...";
      _detectedObjects = [];
    });

    try {
      final XFile? picture = await _cameraController.takePicture();
      if (picture == null) return;
      _imageFile = File(picture.path);
      final image = img.decodeImage(await _imageFile!.readAsBytes())!;
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final inputImage = ImageProcessorBuilder()
          .add(ResizeOp(300, 300, ResizeMethod.BILINEAR))
          .add(NormalizeOp(127.5, 127.5))
          .build()
          .process(TensorImage.fromImage(image));

      final outputLocations = List.filled(1 * 10 * 4, 0.0).reshape([1, 10, 4]);
      final outputClasses = List.filled(1 * 10, 0.0).reshape([1, 10]);
      final outputScores = List.filled(1 * 10, 0.0).reshape([1, 10]);
      final numDetections = List.filled(1, 0.0).reshape([1]);

      _interpreter.runForMultipleInputs([inputImage.buffer], {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections
      });

      List<DetectedObject> objects = [];
      int count = numDetections[0][0].toInt();
      for (int i = 0; i < count; i++) {
        final score = outputScores[0][i];
        if (score > 0.5) {
          final label = _labels[outputClasses[0][i].toInt()];
          final box = outputLocations[0][i];
          final rect = Rect.fromLTRB(
            box[1] * _imageSize!.width,
            box[0] * _imageSize!.height,
            box[3] * _imageSize!.width,
            box[2] * _imageSize!.height,
          );

          objects.add(DetectedObject(
            boundingBox: rect,
            labels: [Label(text: label, confidence: score)],
          ));
        }
      }

      setState(() {
        _detectedObjects = objects;
        result = objects.isEmpty
            ? "No objects detected"
            : objects
                .map((e) => "${e.labels.first.text} - ${(e.labels.first.confidence * 100).toStringAsFixed(2)}%")
                .join("\n");
      });
    } catch (e) {
      setState(() => result = "Error: $e");
    } finally {
      setState(() => isDetecting = false);
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _interpreter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Object Detection"), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: isCameraReady ? _detectObjects : null,
              child: Stack(
                children: [
                  if (_imageFile != null && _detectedObjects.isNotEmpty)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: Stack(
                        children: [
                          Image.file(_imageFile!),
                          if (_imageSize != null)
                            CustomPaint(
                              painter: ObjectDetectorPainter(
                                _detectedObjects,
                                _imageSize!,
                                MediaQuery.of(context).size,
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Center(
                      child: isCameraReady
                          ? CameraPreview(_cameraController)
                          : CircularProgressIndicator(),
                    ),
                  if (_imageFile != null)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        onPressed: () => setState(() {
                          _imageFile = null;
                          _detectedObjects = [];
                        }),
                        child: Icon(Icons.refresh),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: Colors.grey[200],
            child: Text(result),
          ),
        ],
      ),
    );
  }
}

class DetectedObject {
  final Rect boundingBox;
  final List<Label> labels;
  DetectedObject({required this.boundingBox, required this.labels});
}

class Label {
  final String text;
  final double confidence;
  Label({required this.text, required this.confidence});
}

class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size originalImageSize;
  final Size currentCanvasSize;

  ObjectDetectorPainter(this.objects, this.originalImageSize, this.currentCanvasSize);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = currentCanvasSize.width / originalImageSize.width;
    final scaleY = currentCanvasSize.height / originalImageSize.height;
    final scale = math.min(scaleX, scaleY);

    final Paint boxPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final Paint bgPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    for (final obj in objects) {
      final rect = Rect.fromLTRB(
        obj.boundingBox.left * scale,
        obj.boundingBox.top * scale,
        obj.boundingBox.right * scale,
        obj.boundingBox.bottom * scale,
      );
      canvas.drawRect(rect, boxPaint);

      final label = obj.labels.first;
      final textSpan = TextSpan(
        text: "${label.text} ${(label.confidence * 100).toStringAsFixed(1)}%",
        style: TextStyle(color: Colors.black, fontSize: 14),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();

      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - 4,
        tp.width + 8,
        tp.height + 4,
      );
      canvas.drawRect(bgRect, bgPaint);
      tp.paint(canvas, Offset(rect.left + 4, rect.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

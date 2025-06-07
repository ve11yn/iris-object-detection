import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ObjectDetection({super.key, required this.cameras});

  @override
  State<ObjectDetection> createState() => _ObjectDetectionState();
}

class _ObjectDetectionState extends State<ObjectDetection> {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String result = "Initializing...";
  bool isDetecting = false;
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;

  // Change this to your computer's IP address when testing on physical device
  // Use 'localhost' or '10.0.2.2' (for Android emulator) when using emulator
  // static const String baseUrl = 'http://171.20.10.2:35871'; // For Android emulator
  static const String baseUrl = 'http://172.20.10.5:5000';

  // static const String baseUrl = 'http://localhost:5000'; // For iOS simulator
  // static const String baseUrl = 'http://192.168.1.100:5000'; // Replace with your actual IP for physical device

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkBackendConnection();
    await _initializeCamera();
  }

  Future<void> _checkBackendConnection() async {
    try {
      setState(() {
        result = "Connecting to YOLO backend...";
      });

      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          result = "Connected to YOLO backend!";
        });
      } else {
        setState(() {
          result = "Backend connection failed. Check if Python server is running.";
        });
      }
    } catch (e) {
      setState(() {
        result = "Cannot connect to backend at $baseUrl. Make sure:\n"
                "1. Python server is running (python app.py)\n"
                "2. IP address is correct\n"
                "3. Both devices are on same network";
      });
      print("Backend connection error: $e");
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        result = "No cameras available";
      });
      return;
    }

    try {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController.initialize();

      if (!mounted) return;
      
      setState(() {
        isCameraReady = true;
        result = "Ready! Tap screen to detect objects";
      });
    } catch (e) {
      setState(() {
        result = "Camera initialization failed: $e";
      });
      print("Camera error: $e");
    }
  }

  Future<void> _detectObjects() async {
    if (!isCameraReady || isDetecting) {
      return;
    }

    setState(() {
      isDetecting = true;
      result = "Taking photo and analyzing...";
      _detectedObjects = [];
    });

    try {
      // Take picture
      final XFile picture = await _cameraController.takePicture();
      _imageFile = File(picture.path);
      
      // Get image dimensions
      final decodedImage = await decodeImageFromList(await _imageFile!.readAsBytes());
      _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());

      setState(() {
        result = "Sending to YOLO for analysis...";
      });

      // Convert image to base64
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Send to backend
      final response = await http.post(
        Uri.parse('$baseUrl/detect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          List<DetectedObject> detectedObjects = [];
          
          for (var detection in data['detections']) {
            // Convert bounding box coordinates
            final bbox = detection['bbox'] as List;
            final rect = Rect.fromLTRB(
              bbox[0].toDouble(),
              bbox[1].toDouble(),
              bbox[2].toDouble(),
              bbox[3].toDouble(),
            );

            detectedObjects.add(DetectedObject(
              boundingBox: rect,
              label: detection['class'],
              confidence: detection['confidence'].toDouble(),
            ));
          }

          setState(() {
            _detectedObjects = detectedObjects;
            if (detectedObjects.isEmpty) {
              result = "No objects detected. Try different angle or lighting.";
            } else {
              result = "Found ${detectedObjects.length} object(s):\n" +
                  detectedObjects
                      .map((obj) => "${obj.label}: ${(obj.confidence * 100).toStringAsFixed(1)}%")
                      .join("\n");
            }
          });
        } else {
          setState(() {
            result = "Detection failed: ${data['error']}";
          });
        }
      } else {
        setState(() {
          result = "Server error: ${response.statusCode}";
        });
      }
   } catch (e) {
      String errorMessage = "Detection failed: ";
      
      if (e.toString().contains('SocketException')) {
        errorMessage += "Network error. Check if:\n"
            "1. Backend is running\n"
            "2. Phone and computer are on same WiFi\n"
            "3. IP address $baseUrl is correct";
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage += "Request timed out. The image might be too large or the server is busy.";
      } else {
        errorMessage += "$e\n\nMake sure Python backend is running!";
      }
      
      setState(() {
        result = errorMessage;
      });
      print("Detection error: $e");
    }
  }

  void _resetDetection() {
    setState(() {
      _imageFile = null;
      _detectedObjects = [];
      result = "Ready! Tap screen to detect objects";
    });
  }

  @override
  void dispose() {
    if (isCameraReady) {
      _cameraController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("YOLO Object Detection"),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkBackendConnection,
            tooltip: "Check connection",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (isCameraReady && !isDetecting) ? _detectObjects : null,
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: Stack(
                  children: [
                    Center(
                      child: _buildCameraOrImage(),
                    ),
                    if (isDetecting)
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    if (_imageFile != null)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: FloatingActionButton(
                          mini: true,
                          onPressed: _resetDetection,
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.refresh, color: Colors.black),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Backend: $baseUrl",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraOrImage() {
    if (_imageFile != null && _detectedObjects.isNotEmpty) {
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _imageSize?.width ?? 300,
          height: _imageSize?.height ?? 300,
          child: Stack(
            children: [
              Image.file(_imageFile!),
              CustomPaint(
                size: Size(_imageSize?.width ?? 300, _imageSize?.height ?? 300),
                painter: ObjectDetectorPainter(_detectedObjects),
              ),
            ],
          ),
        ),
      );
    } else if (_imageFile != null) {
      return Image.file(_imageFile!, fit: BoxFit.contain);
    } else if (isCameraReady) {
      return CameraPreview(_cameraController);
    } else {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            "Initializing...",
            style: TextStyle(color: Colors.white),
          ),
        ],
      );
    }
  }
}

class DetectedObject {
  final Rect boundingBox;
  final String label;
  final double confidence;

  DetectedObject({
    required this.boundingBox,
    required this.label,
    required this.confidence,
  });
}

class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;

  ObjectDetectorPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final Paint bgPaint = Paint()
      ..color = Colors.green.withOpacity(0.8);

    for (final obj in objects) {
      // Draw bounding box
      canvas.drawRect(obj.boundingBox, boxPaint);

      // Draw label background and text
      final textSpan = TextSpan(
        text: "${obj.label} ${(obj.confidence * 100).toStringAsFixed(1)}%",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Position label at top of bounding box
      double labelY = obj.boundingBox.top - textPainter.height - 8;
      
      // If label would be off-screen, put it inside the box
      if (labelY < 0) {
        labelY = obj.boundingBox.top + 4;
      }

      final bgRect = Rect.fromLTWH(
        obj.boundingBox.left,
        labelY,
        textPainter.width + 16,
        textPainter.height + 8,
      );

      // Draw rounded rectangle for label background
      final RRect roundedRect = RRect.fromRectAndRadius(
        bgRect,
        const Radius.circular(4),
      );
      canvas.drawRRect(roundedRect, bgPaint);
      
      textPainter.paint(
        canvas,
        Offset(obj.boundingBox.left + 8, labelY + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
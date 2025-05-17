import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

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
  late ObjectDetector _objectDetector;
  bool isDetecting = false;
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _initializeObjectDetector();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameraController = CameraController(
        widget.cameras[0], 
        ResolutionPreset.medium, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg
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

  Future<void> _initializeObjectDetector() async {
    try {
      // Use default detector options
      final options = ObjectDetectorOptions(
        mode: DetectionMode.single, // Use single image mode
        classifyObjects: true, // Classify objects (get labels)
        multipleObjects: true, // Detect multiple objects
      );
      _objectDetector = ObjectDetector(options: options);
      setState(() {
        result = "Object detector initialized";
      });
    } catch (e) {
      setState(() {
        result = "ML initialization error: $e";
      });
      print("ML initialization error: $e");
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
      // Take a picture
      final XFile? picture = await _cameraController.takePicture();
      if (picture == null) {
        setState(() {
          result = "Failed to take picture";
          isDetecting = false;
        });
        return;
      }
      
      // Create a file from the picture
      _imageFile = File(picture.path);
      if (!await _imageFile!.exists()) {
        setState(() {
          result = "Error: Image file does not exist";
          isDetecting = false;
        });
        return;
      }
      
      // Get the image dimensions for proper scaling of bounding boxes
      final image = await decodeImageFromList(_imageFile!.readAsBytesSync());
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());

      // Process with ML Kit Object Detector
      final inputImage = InputImage.fromFilePath(picture.path);
      final objects = await _objectDetector.processImage(inputImage);
      
      // Format results
      String detectedObjectsText = "";
      if (objects.isNotEmpty) {
        _detectedObjects = objects;
        detectedObjectsText = objects.map((object) {
          String text = "";
          if (object.labels.isNotEmpty) {
            final label = object.labels.first;
            text = "${label.text} - ${(label.confidence * 100).toStringAsFixed(2)}%";
          } else {
            text = "Unknown object";
          }
          return text;
        }).join("\n");
      } else {
        detectedObjectsText = "No objects detected";
      }
        
      setState(() {
        result = detectedObjectsText;
      });
    } catch (error) {
      print("Error processing image: $error");
      setState(() {
        result = "Error: $error";
        _detectedObjects = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error processing image: $error"), 
          backgroundColor: Colors.red,
        )
      );
    } finally {
      setState(() {
        isDetecting = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _objectDetector.close();
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
                  // Show either camera preview or the captured image with bounding boxes
                  if (_imageFile != null && _detectedObjects.isNotEmpty)
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Stack(
                          children: [
                            Image.file(_imageFile!),
                            if (_imageSize != null)
                              CustomPaint(
                                painter: ObjectDetectorPainter(
                                  _detectedObjects, 
                                  _imageSize!,
                                  MediaQuery.of(context).size
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      width: MediaQuery.of(context).size.width,
                      child: isCameraReady 
                        ? CameraPreview(_cameraController) 
                        : Center(child: CircularProgressIndicator()),
                    ),
                    
                  if (isCameraReady && _imageFile == null)
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Text(
                          "Tap on screen to detect objects",
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    
                  if (_imageFile != null)
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        onPressed: () {
                          setState(() {
                            _imageFile = null;
                            _detectedObjects = [];
                          });
                        },
                        child: Icon(Icons.refresh),
                        tooltip: "Return to camera",
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
                topLeft: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const Text(
                  "Detected Objects",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4)
                    ],
                  ),
                  child: Text(result, textAlign: TextAlign.start),
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter to draw bounding boxes
class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size originalImageSize;
  final Size currentCanvasSize;
  
  ObjectDetectorPainter(this.objects, this.originalImageSize, this.currentCanvasSize);
  
  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the scaling factor between original image and displayed size
    final double scaleX = currentCanvasSize.width / originalImageSize.width;
    final double scaleY = currentCanvasSize.height / originalImageSize.height;
    final double scale = math.min(scaleX, scaleY);
    
    // Paint for the bounding box
    final Paint paint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
      
    // Paint for the label background
    final Paint backgroundPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    
    for (final DetectedObject object in objects) {
      // Scale the bounding box to the current display size
      final Rect scaledRect = Rect.fromLTRB(
        object.boundingBox.left * scale,
        object.boundingBox.top * scale,
        object.boundingBox.right * scale,
        object.boundingBox.bottom * scale,
      );
      
      // Draw the bounding box
      canvas.drawRect(scaledRect, paint);
      
      // Draw label if available
      if (object.labels.isNotEmpty) {
        final label = object.labels.first;
        final text = "${label.text} ${(label.confidence * 100).toStringAsFixed(0)}%";
        
        final textSpan = TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        );
        
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        
        textPainter.layout();
        
        // Draw background for text
        final textBackgroundRect = Rect.fromLTWH(
          scaledRect.left,
          scaledRect.top - textPainter.height - 4,
          textPainter.width + 8,
          textPainter.height + 4,
        );
        
        canvas.drawRect(textBackgroundRect, backgroundPaint);
        
        // Draw text
        textPainter.paint(
          canvas, 
          Offset(scaledRect.left + 4, scaledRect.top - textPainter.height - 2),
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(ObjectDetectorPainter oldDelegate) {
    return oldDelegate.objects != objects;
  }
}
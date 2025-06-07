import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ObjectDetection({super.key, required this.cameras});

  @override
  State<ObjectDetection> createState() => _ObjectDetectionState();
}

class _ObjectDetectionState extends State<ObjectDetection>
    with TickerProviderStateMixin {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String result = "Initializing...";
  bool isDetecting = false;
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;
  
  // Bottom sheet controller
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  bool _isBottomSheetExpanded = false;

  // TensorFlow Lite
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _modelLoaded = false;

  // Image picker
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _bottomSheetController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _bottomSheetAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeInOut,
    ));
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadModel();
    await _initializeCamera();
  }

  Future<void> _loadModel() async {
    try {
      setState(() {
        result = "Loading AI model...";
      });

      // Load model with proper options for newer tflite_flutter
      final interpreterOptions = InterpreterOptions()
        ..threads = 4;
      
      _interpreter = await Interpreter.fromAsset(
        'assets/model/object-detection.tflite',
        options: interpreterOptions,
      );

      // Load labels
      final labelData = await rootBundle.loadString('assets/model/label.txt');
      _labels = labelData.trim().split('\n');

      setState(() {
        _modelLoaded = true;
        result = "AI model loaded successfully";
      });

      print('Model loaded successfully');
      print('Input tensors: ${_interpreter?.getInputTensors().length}');
      print('Output tensors: ${_interpreter?.getOutputTensors().length}');
      print('Labels loaded: ${_labels.length} classes');
    } catch (e) {
      setState(() {
        result = "Failed to load AI model: $e";
      });
      print("Model loading error: $e");
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
      setState(() {
        result = "Initializing camera...";
      });

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
        result = _modelLoaded 
          ? "Ready! Tap capture button to detect objects"
          : "Camera ready, loading AI model...";
      });
    } catch (e) {
      setState(() {
        result = "Camera initialization failed: $e";
      });
      print("Camera error: $e");
    }
  }

  Future<void> _takePicture() async {
    if (!isCameraReady || !_modelLoaded || isDetecting || _interpreter == null) {
      return;
    }

    try {
      final XFile picture = await _cameraController.takePicture();
      _imageFile = File(picture.path);
      await _detectObjects();
    } catch (e) {
      setState(() {
        result = "Failed to take picture: $e";
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        _imageFile = File(image.path);
        await _detectObjects();
      }
    } catch (e) {
      setState(() {
        result = "Failed to pick image: $e";
      });
    }
  }

  Future<void> _detectObjects() async {
    if (!_modelLoaded || isDetecting || _interpreter == null || _imageFile == null) {
      return;
    }

    setState(() {
      isDetecting = true;
      result = "Analyzing image...";
      _detectedObjects = [];
    });

    try {
      final imageBytes = await _imageFile!.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      _imageSize = Size(image.width.toDouble(), image.height.toDouble());

      setState(() {
        result = "Processing with AI...";
      });

      // Preprocess image for model
      final resizedImage = img.copyResize(image, width: 300, height: 300);
      final inputBytes = _imageToByteListFloat32(resizedImage);

      // Prepare outputs - using proper format for tflite_flutter 0.10.4
      var outputLocations = List.filled(1 * 10 * 4, 0.0).reshape([1, 10, 4]);
      var outputClasses = List.filled(1 * 10, 0.0).reshape([1, 10]);
      var outputScores = List.filled(1 * 10, 0.0).reshape([1, 10]);
      var numDetections = List.filled(1, 0.0);

      // Run inference
      _interpreter!.runForMultipleInputs(
        [inputBytes],
        {
          0: outputLocations,
          1: outputClasses,
          2: outputScores,
          3: numDetections,
        },
      );

      // Process results
      List<DetectedObject> detectedObjects = [];
      final count = math.min(numDetections[0].toInt(), 10);
      
      for (int i = 0; i < count; i++) {
        final score = outputScores[0][i];
        if (score > 0.3) {
          final classIndex = outputClasses[0][i].toInt();
          if (classIndex >= 0 && classIndex < _labels.length) {
            final label = _labels[classIndex];
            final location = outputLocations[0][i];
            
            final rect = Rect.fromLTRB(
              location[1] * _imageSize!.width,
              location[0] * _imageSize!.height,
              location[3] * _imageSize!.width,
              location[2] * _imageSize!.height,
            );

            detectedObjects.add(DetectedObject(
              boundingBox: rect,
              label: label,
              confidence: score,
            ));
          }
        }
      }

      setState(() {
        _detectedObjects = detectedObjects;
        if (detectedObjects.isEmpty) {
          result = "No objects detected. Try different angle or lighting.";
        } else {
          result = "Found ${detectedObjects.length} object(s)";
        }
      });

      // Auto-expand bottom sheet when objects are detected
      if (detectedObjects.isNotEmpty) {
        _bottomSheetController.forward();
        _isBottomSheetExpanded = true;
      }

    } catch (e) {
      setState(() {
        result = "Detection failed: $e";
      });
      print("Detection error: $e");
    } finally {
      setState(() {
        isDetecting = false;
      });
    }
  }

  Float32List _imageToByteListFloat32(img.Image image) {
    final bytes = Float32List(1 * 300 * 300 * 3);
    int pixelIndex = 0;

    for (int y = 0; y < 300; y++) {
      for (int x = 0; x < 300; x++) {
        final pixel = image.getPixel(x, y);
        // Use the correct methods for image package v3.3.0
        bytes[pixelIndex++] = (pixel.r - 127.5) / 127.5;
        bytes[pixelIndex++] = (pixel.g - 127.5) / 127.5;
        bytes[pixelIndex++] = (pixel.b - 127.5) / 127.5;
      }
    }
    return bytes;
  }

  void _resetDetection() {
    setState(() {
      _imageFile = null;
      _detectedObjects = [];
      result = "Ready! Tap capture button to detect objects";
    });
    _bottomSheetController.reverse();
    _isBottomSheetExpanded = false;
  }

  void _toggleBottomSheet() {
    if (_isBottomSheetExpanded) {
      _bottomSheetController.reverse();
    } else {
      _bottomSheetController.forward();
    }
    _isBottomSheetExpanded = !_isBottomSheetExpanded;
  }

  @override
  void dispose() {
    if (isCameraReady) {
      _cameraController.dispose();
    }
    _interpreter?.close();
    _bottomSheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main camera/image view
          Container(
            width: double.infinity,
            height: double.infinity,
            child: _buildCameraOrImage(),
          ),
          
          // Top app bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  if (_imageFile != null)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _resetDetection,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Camera controls (bottom)
          if (_imageFile == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Gallery button
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.photo_library, color: Colors.white),
                          onPressed: _pickImageFromGallery,
                        ),
                      ),
                      
                      // Capture button
                      GestureDetector(
                        onTap: (isCameraReady && _modelLoaded && !isDetecting) ? _takePicture : null,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDetecting ? Colors.red : Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: isDetecting
                                ? const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      
                      // Placeholder for symmetry
                      const SizedBox(width: 50),
                    ],
                  ),
                ),
              ),
            ),

          // Draggable bottom sheet for detected objects
          if (_imageFile != null && _detectedObjects.isNotEmpty)
            AnimatedBuilder(
              animation: _bottomSheetAnimation,
              builder: (context, child) {
                return Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height * 
                         (0.4 + (0.6 * _bottomSheetAnimation.value)),
                  child: GestureDetector(
                    onTap: _toggleBottomSheet,
                    onPanUpdate: (details) {
                      if (details.delta.dy < 0 && !_isBottomSheetExpanded) {
                        _toggleBottomSheet();
                      } else if (details.delta.dy > 0 && _isBottomSheetExpanded) {
                        _toggleBottomSheet();
                      }
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Drag indicator
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          
                          // Content
                          Expanded(
                            child: _bottomSheetAnimation.value > 0.5
                                ? _buildFullScreenObjectDetails()
                                : _buildCompactObjectList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Status message (when no objects detected)
          if (_imageFile != null && _detectedObjects.isEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    result,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraOrImage() {
    if (_imageFile != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _imageSize?.width ?? 300,
          height: _imageSize?.height ?? 300,
          child: Stack(
            children: [
              Image.file(_imageFile!),
              if (_detectedObjects.isNotEmpty)
                CustomPaint(
                  size: Size(_imageSize?.width ?? 300, _imageSize?.height ?? 300),
                  painter: ObjectDetectorPainter(_detectedObjects),
                ),
            ],
          ),
        ),
      );
    } else if (isCameraReady) {
      return CameraPreview(_cameraController);
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              "Initializing...",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCompactObjectList() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Detected Objects (${_detectedObjects.length})",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "Drag the box over the object you want to identify. You can also zoom in for a closer look!",
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _detectedObjects.length,
              itemBuilder: (context, index) {
                final obj = _detectedObjects[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 30,
                        color: Colors.yellow[700],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              obj.label.toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Confidence: ${(obj.confidence * 100).toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenObjectDetails() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Object Analysis",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _toggleBottomSheet,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "The image shows ${_detectedObjects.length > 1 ? 'multiple objects' : 'an object'} with high confidence detection. AI analysis reveals detailed information about each identified item.",
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _detectedObjects.length,
              itemBuilder: (context, index) {
                final obj = _detectedObjects[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.yellow[700],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            obj.label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.analytics_outlined, size: 20, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "Confidence: ${(obj.confidence * 100).toStringAsFixed(1)}%",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 20, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "Position: (${obj.boundingBox.left.toInt()}, ${obj.boundingBox.top.toInt()})",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.crop_free, size: 20, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            "Size: ${(obj.boundingBox.width).toInt()} × ${(obj.boundingBox.height).toInt()}",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final Paint bgPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.8);

    for (final obj in objects) {
      // Draw bounding box
      canvas.drawRect(obj.boundingBox, boxPaint);

      // Draw label background and text
      final textSpan = TextSpan(
        text: "${obj.label} ${(obj.confidence * 100).toStringAsFixed(1)}%",
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final bgRect = Rect.fromLTWH(
        obj.boundingBox.left,
        obj.boundingBox.top - textPainter.height - 8,
        textPainter.width + 16,
        textPainter.height + 8,
      );

      canvas.drawRect(bgRect, bgPaint);
      textPainter.paint(
        canvas,
        Offset(obj.boundingBox.left + 8, obj.boundingBox.top - textPainter.height - 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
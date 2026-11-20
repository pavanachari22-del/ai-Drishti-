import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AIDrishtiApp());
}

class AIDrishtiApp extends StatelessWidget {
  const AIDrishtiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Drishti Photography',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.cyanAccent,
        ),
      ),
      home: const CameraDrishtiScreen(),
    );
  }
}

enum GridMode { ruleOfThirds, goldenRatio, off }

class CameraDrishtiScreen extends StatefulWidget {
  const CameraDrishtiScreen({super.key});

  @override
  State<CameraDrishtiScreen> createState() => _CameraDrishtiScreenState();
}

class _CameraDrishtiScreenState extends State<CameraDrishtiScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  String? _errorMessage;

  GridMode _gridMode = GridMode.ruleOfThirds;
  int _tipIndex = 0;
  double _rollDegrees = 0.0;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  final List<String> _photographyTips = const [
    'Place your main subject on grid intersections for stronger balance.',
    'Keep the horizon aligned with horizontal grid lines or level indicator.',
    'Use golden spiral / ratio framing for natural depth and leading lines.',
    'Leave breathing room in the direction your subject is facing or moving.',
    'Lower your camera angle for dramatic perspective and foreground depth.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSensorListener();
    _initCameraFlow();
  }

  void _startSensorListener() {
    _accelSub = accelerometerEventStream().listen((event) {
      if (!mounted) return;
      final angle = math.atan2(event.x, event.y) * (180 / math.pi);
      setState(() {
        _rollDegrees = angle;
      });
    });
  }

  Future<void> _initCameraFlow() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage =
            'Camera permission is required. Please allow camera access in Settings.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isInitializing = false;
          _errorMessage = 'No camera found on this device.';
        });
        return;
      }

      await _setupCameraController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _setupCameraController(CameraDescription description) async {
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Camera error: $e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isInitializing) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    setState(() => _isInitializing = true);
    await _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  void _cycleGridMode() {
    setState(() {
      if (_gridMode == GridMode.ruleOfThirds) {
        _gridMode = GridMode.goldenRatio;
      } else if (_gridMode == GridMode.goldenRatio) {
        _gridMode = GridMode.off;
      } else {
        _gridMode = GridMode.ruleOfThirds;
      }
    });
  }

  void _nextTip() {
    setState(() {
      _tipIndex = (_tipIndex + 1) % _photographyTips.length;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCameraController(controller.description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String get _gridLabel {
    switch (_gridMode) {
      case GridMode.ruleOfThirds:
        return '3x3 Thirds';
      case GridMode.goldenRatio:
        return 'Golden Grid';
      case GridMode.off:
        return 'Grid Off';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLevel = _rollDegrees.abs() < 2.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text(
          'AI Drishti Photography',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            )
          : _errorMessage != null
              ? _buildErrorView()
              : _buildCameraBody(isLevel),
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined,
                size: 56, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await openAppSettings();
                await _initCameraFlow();
              },
              child: const Text('Open Settings & Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBody(bool isLevel) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera not ready'));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              if (_gridMode != GridMode.off)
                CustomPaint(
                  painter: CompositionGridPainter(gridMode: _gridMode),
                ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _gridLabel,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLevel
                            ? Colors.green.withValues(alpha: 0.75)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isLevel
                            ? 'Level OK (${_rollDegrees.toStringAsFixed(1)}°)' : 'Tilt:${_rollDegrees.toStringAsFixed(1)}°',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          color: const Color(0xFF141414),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'AI Composition Tip',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _nextTip,
                    icon: const Icon(Icons.lightbulb_outline, size: 16),
                    label: const Text('Next Tip'),
                  ),
                ],
              ),
              Text(
                _photographyTips[_tipIndex],
                style: const TextStyle(fontSize: 13.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cycleGridMode,
                      icon: const Icon(Icons.grid_on),
                      label: Text(_gridLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _nextTip,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Guide Tip'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CompositionGridPainter extends CustomPainter {
  final GridMode gridMode;

  CompositionGridPainter({required this.gridMode});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.0;

    final accentPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.75)
      ..strokeWidth = 1.2;

    if (gridMode == GridMode.ruleOfThirds) {
      final w1 = size.width / 3;
      final w2 = (size.width * 2) / 3;
      final h1 = size.height / 3;
      final h2 = (size.height * 2) / 3;

      canvas.drawLine(Offset(w1, 0), Offset(w1, size.height), linePaint);
      canvas.drawLine(Offset(w2, 0), Offset(w2, size.height), linePaint);
      canvas.drawLine(Offset(0, h1), Offset(size.width, h1), linePaint);
      canvas.drawLine(Offset(0, h2), Offset(size.width, h2), linePaint);

      final focalPoints = [
        Offset(w1, h1),
        Offset(w2, h1),
        Offset(w1, h2),
        Offset(w2, h2),
      ];
      for (final pt in focalPoints) {
        canvas.drawCircle(pt, 4.5, accentPaint);
      }
    } else if (grid

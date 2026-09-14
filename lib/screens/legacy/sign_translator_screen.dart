import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../models/ui_preferences.dart';
import '../../services/camera_service.dart';
import '../../services/model_service.dart';
import '../../services/permission_handler.dart';
import 'history_screen.dart' show HistoryItem;

/// Original live camera sign-translator page (extracted unchanged).
class TranslatorPage extends StatefulWidget {
  const TranslatorPage({
    super.key,
    required this.prefs,
    required this.onAddHistory,
  });

  final AppUiPreferences prefs;
  final ValueChanged<HistoryItem> onAddHistory;

  @override
  State<TranslatorPage> createState() => _TranslatorPageState();
}

class _TranslatorPageState extends State<TranslatorPage>
    with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final CameraService _cameraService = CameraService();
  final ModelService _modelService = ModelService();

  late final AnimationController _listeningController;
  late final AnimationController _speakingController;
  final TextEditingController _ttsController = TextEditingController();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _permissionsGranted = false;
  bool _isCameraInitialized = false;
  bool _isCameraRunning = false;
  bool _isModelLoaded = false;
  bool _isFallbackMode = false;
  bool _isProcessingFrame = false;

  int _selectedCameraIndex = 0;
  int _frameCounter = 0;

  String _recognizedText = '';
  String _speechText = '';
  String _initializationError = '';

  List<SignPrediction> _topPredictions = <SignPrediction>[];

  bool get _motionEnabled => !widget.prefs.reduceMotion;

  @override
  void initState() {
    super.initState();
    _listeningController = AnimationController(
      duration: const Duration(milliseconds: 850),
      vsync: this,
    );
    _speakingController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _configureTtsCallbacks();
    _applyVoiceSettings();
    _initializeServices();
  }

  @override
  void didUpdateWidget(covariant TranslatorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool voicePrefsChanged =
        oldWidget.prefs.ttsRate != widget.prefs.ttsRate ||
        oldWidget.prefs.ttsPitch != widget.prefs.ttsPitch ||
        oldWidget.prefs.ttsVolume != widget.prefs.ttsVolume;

    if (voicePrefsChanged) {
      _applyVoiceSettings();
    }

    if (!_motionEnabled) {
      _listeningController.stop();
      _speakingController.stop();
    }
  }

  Future<void> _applyVoiceSettings() async {
    await _tts.setSpeechRate(widget.prefs.ttsRate);
    await _tts.setPitch(widget.prefs.ttsPitch);
    await _tts.setVolume(widget.prefs.ttsVolume);
  }

  void _configureTtsCallbacks() {
    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() => _isSpeaking = true);
      if (_motionEnabled) {
        _speakingController.repeat(reverse: true);
      }
    });

    void onDone() {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
      _speakingController.stop();
      _speakingController.reset();
    }

    _tts.setCompletionHandler(onDone);
    _tts.setCancelHandler(onDone);
    _tts.setErrorHandler((message) {
      onDone();
      _showSnackBar('TTS error: ${message.toString()}');
    });
  }

  Future<void> _initializeServices() async {
    setState(() {
      _initializationError = '';
      _isFallbackMode = false;
    });

    try {
      final bool granted = await PermissionHandler.requestAllPermissions();
      if (!mounted) return;

      setState(() => _permissionsGranted = granted);
      if (!granted) {
        setState(() {
          _initializationError =
              'Camera and microphone permissions are needed for full mode.';
          _isFallbackMode = true;
        });
      }

      if (granted) {
        await _cameraService.initializeCamera();
        if (_cameraService.cameras.isNotEmpty) {
          await _cameraService.startCameraStream(
            cameraIndex: _selectedCameraIndex,
            frameProcessor: _processFrame,
          );

          if (!mounted) return;
          setState(() {
            _isCameraInitialized = true;
            _isCameraRunning = true;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = false;
        _isCameraRunning = false;
        _isFallbackMode = true;
        _initializationError = 'Camera error: $e';
      });
    }

    try {
      await _modelService.loadModel();
      if (!mounted) return;
      setState(() => _isModelLoaded = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isModelLoaded = false;
        _isFallbackMode = true;
      });
      if (kDebugMode) {
        debugPrint('Model initialization failed: $e');
      }
    }

    if (!mounted) return;
    if (_isFallbackMode) {
      _showSnackBar('Running in manual fallback mode');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    _frameCounter++;
    if (_frameCounter % widget.prefs.frameStride != 0) {
      return;
    }

    if (_isProcessingFrame ||
        !_isModelLoaded ||
        !_isCameraRunning ||
        !mounted) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final int sensorOrientation =
          _cameraService.cameraController?.description.sensorOrientation ?? 0;
      final SignPrediction prediction = await _modelService.runInference(
        image,
        sensorOrientation: sensorOrientation,
      );

      final List<SignPrediction> topPredictions = _modelService
          .getTopKPredictions(prediction.rawScores, topK: 3);

      if (!mounted) return;

      if (prediction.label == 'No hand') {
        if (_topPredictions.isNotEmpty) {
          setState(() => _topPredictions = <SignPrediction>[]);
        }
        return;
      }

      final bool shouldUpdateRecognized =
          prediction.label != 'Error' &&
          prediction.label != 'Unknown' &&
          prediction.confidence >= widget.prefs.recognitionThreshold &&
          prediction.label != _recognizedText;

      setState(() {
        _topPredictions = topPredictions;
        if (shouldUpdateRecognized) {
          _recognizedText = prediction.label;
        }
      });

      if (shouldUpdateRecognized) {
        if (widget.prefs.autoSpeakSigns) {
          await _speak(prediction.label, addToHistory: false);
        }

        if (prediction.confidence >= widget.prefs.historyConfidenceThreshold) {
          widget.onAddHistory(
            HistoryItem(
              type: 'sign',
              text: prediction.label,
              confidence: prediction.confidence.toInt(),
              timestamp: DateTime.now(),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Frame processing error: $e');
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _vibrateLight() {
    if (widget.prefs.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  void _vibrateMedium() {
    if (widget.prefs.hapticsEnabled) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _toggleListening() async {
    _vibrateMedium();

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      _listeningController.stop();
      _listeningController.reset();

      if (_speechText.isNotEmpty) {
        widget.onAddHistory(
          HistoryItem(
            type: 'speech',
            text: _speechText,
            timestamp: DateTime.now(),
          ),
        );
      }
      return;
    }

    try {
      final bool available = await _speech.initialize(
        onError: (error) => _showSnackBar('Speech error: $error'),
        onStatus: (status) {
          if (status == 'notListening' && mounted) {
            setState(() => _isListening = false);
            _listeningController.stop();
          }
        },
      );

      if (!mounted) return;

      if (!available) {
        _showSnackBar('Speech recognition is not available');
        return;
      }

      setState(() => _isListening = true);
      if (_motionEnabled) {
        _listeningController.repeat(reverse: true);
      }

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() => _speechText = result.recognizedWords);
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Speech service is unavailable in this environment');
      if (kDebugMode) {
        debugPrint('Speech init error: $e');
      }
    }
  }

  Future<void> _speak(String text, {bool addToHistory = true}) async {
    if (text.trim().isEmpty) return;

    if (_isSpeaking) {
      await _tts.stop();
      return;
    }

    _vibrateLight();
    await _tts.speak(text);

    if (addToHistory) {
      widget.onAddHistory(
        HistoryItem(type: 'tts', text: text.trim(), timestamp: DateTime.now()),
      );
    }
  }

  Future<void> _startCamera() async {
    if (_isCameraRunning) {
      _showSnackBar('Camera already running');
      return;
    }

    try {
      if (!_permissionsGranted) {
        final bool granted = await PermissionHandler.requestAllPermissions();
        if (!mounted) return;
        setState(() => _permissionsGranted = granted);
        if (!granted) {
          _showSnackBar('Permission is required for camera mode');
          return;
        }
      }

      await _cameraService.initializeCamera();
      if (_selectedCameraIndex >= _cameraService.cameras.length) {
        _selectedCameraIndex = 0;
      }

      await _cameraService.startCameraStream(
        cameraIndex: _selectedCameraIndex,
        frameProcessor: _processFrame,
      );

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _isCameraRunning = true;
        _initializationError = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = false;
        _isCameraRunning = false;
        _initializationError = 'Unable to start camera: $e';
      });
      _showSnackBar('Unable to start camera');
    }
  }

  Future<void> _stopCamera() async {
    await _cameraService.dispose();
    if (!mounted) return;
    setState(() {
      _isCameraInitialized = false;
      _isCameraRunning = false;
      _isProcessingFrame = false;
    });
  }

  Future<void> _switchCamera() async {
    if (!_isCameraRunning || _cameraService.cameras.length < 2) {
      _showSnackBar('No additional camera available');
      return;
    }

    final int nextIndex =
        (_selectedCameraIndex + 1) % _cameraService.cameras.length;
    final bool switched = await _cameraService.switchCamera(
      cameraIndex: nextIndex,
      frameProcessor: _processFrame,
    );

    if (!mounted) return;

    if (switched) {
      setState(() => _selectedCameraIndex = nextIndex);
    } else {
      _showSnackBar('Unable to switch camera');
    }
  }

  // Pre-existing helper kept for parity with the original app; the snapshot
  // button was already detached in the inherited UI.
  // ignore: unused_element
  Future<void> _captureSnapshot() async {
    if (!_isCameraRunning) {
      _showSnackBar('Start camera first');
      return;
    }

    final XFile? image = await _cameraService.captureImage();
    if (image == null) {
      _showSnackBar('Snapshot failed');
      return;
    }
    _showSnackBar('Snapshot captured');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  double _cameraAspectRatio() {
    final CameraController? controller = _cameraService.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return 4 / 3;
    }

    final double ratio = controller.value.aspectRatio;
    if (!ratio.isFinite || ratio <= 0) {
      return 4 / 3;
    }

    return ratio.clamp(0.75, 1.65);
  }

  Widget _buildMicPulse() {
    if (!_isListening || !_motionEnabled) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _listeningController,
      builder: (BuildContext context, Widget? child) {
        final double scale = 1 + (_listeningController.value * 0.14);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 98,
            height: 98,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraPreview(CameraController controller) {
    final Size? previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }

    final double previewAspectRatio = previewSize.height / previewSize.width;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: previewAspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildCameraCard() {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget content;
    if (_initializationError.isNotEmpty) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(height: 10),
          Text(
            _initializationError,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: PermissionHandler.openAppSettingsPage,
                child: const Text('Open Settings'),
              ),
              FilledButton(
                onPressed: _initializeServices,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      );
    } else if (!_isCameraRunning) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          const SizedBox.shrink(),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _startCamera,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [Icon(Icons.play_arrow), SizedBox(width: 8), Text('Start')],
            ),
          ),
        ],
      );
    } else if (!_isCameraInitialized ||
        _cameraService.cameraController == null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildCameraPreview(_cameraService.cameraController!),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Text(
                _recognizedText.isEmpty ? 'No sign detected' : _recognizedText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // ignore: unused_local_variable
                final bool compact = constraints.maxWidth < 640;

                // Minimal control row: only essential actions
                return Row(
                  children: [
                    Icon(Icons.videocam_outlined, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Spacer(),
                    IconButton(
                      tooltip: _isCameraRunning ? 'Stop' : 'Start',
                      onPressed: _isCameraRunning ? _stopCamera : _startCamera,
                      icon: Icon(_isCameraRunning ? Icons.stop : Icons.play_arrow),
                    ),
                    IconButton(
                      tooltip: 'Switch',
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double previewHeight =
                    ((constraints.maxWidth / _cameraAspectRatio()) * 1.18)
                        .clamp(290.0, 520.0);

                return Container(
                  width: double.infinity,
                  height: previewHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: content,
                );
              },
            ),
            const SizedBox(height: 10),
            if (_topPredictions.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _topPredictions.map((SignPrediction prediction) {
                  return Chip(
                    label: Text(
                      '${prediction.label} (${prediction.confidence.toStringAsFixed(0)}%)',
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Chip(label: Text(_permissionsGranted ? 'Permissions: OK' : 'Permissions: Required')),
                const SizedBox(width: 8),
                Chip(label: Text(_isModelLoaded ? 'Model: Ready' : 'Model: Loading')),
                const SizedBox(width: 8),
                Chip(label: Text(_isFallbackMode ? 'Mode: Manual' : 'Mode: AI')),
                const Spacer(),
                // compact recognized text preview
                if (_recognizedText.isNotEmpty)
                  Flexible(
                    child: Text(
                      _recognizedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _buildCameraCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic_rounded),
                    const SizedBox(width: 8),
                    const Text(
                      'Speech to Text',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color:
                            (_isListening
                                    ? scheme.errorContainer
                                    : scheme.primaryContainer)
                                .withValues(alpha: 0.9),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        _isListening ? 'Listening' : 'Idle',
                        style: TextStyle(
                          color: _isListening
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Color micBackground = _isListening
                        ? scheme.errorContainer
                        : scheme.primaryContainer;
                    final Color micForeground = _isListening
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer;

                    final Widget micButton = Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildMicPulse(),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: micBackground,
                            border: Border.all(
                              color: micForeground.withValues(alpha: 0.22),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: micBackground.withValues(alpha: 0.38),
                                blurRadius: _isListening ? 20 : 12,
                                spreadRadius: _isListening ? 2 : 0,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _toggleListening,
                            iconSize: 34,
                            icon: Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: micForeground,
                            ),
                          ),
                        ),
                      ],
                    );

                    final Widget transcriptBox = Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.78,
                        ),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.subtitles_outlined,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _speechText.isEmpty
                                  ? 'Tap the microphone to start live transcription.'
                                  : _speechText,
                              style: TextStyle(
                                color: _speechText.isEmpty
                                    ? scheme.onSurfaceVariant
                                    : scheme.onSurface,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (constraints.maxWidth < 620) {
                      return Column(
                        children: [
                          Align(alignment: Alignment.center, child: micButton),
                          const SizedBox(height: 12),
                          transcriptBox,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        micButton,
                        const SizedBox(width: 14),
                        Expanded(child: transcriptBox),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Text to Speech',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ttsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Type text to speak...',
                  ),
                ),
                const SizedBox(height: 12),
                if (_isSpeaking && _motionEnabled)
                  SizedBox(
                    height: 28,
                    child: AnimatedBuilder(
                      animation: _speakingController,
                      builder: (BuildContext context, Widget? child) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List<Widget>.generate(3, (int index) {
                            final double v =
                                (_speakingController.value + (index * 0.2)) %
                                1.0;
                            final double h = 8 + (v * 16);
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 6,
                              height: h,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: scheme.primary,
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final String text = _ttsController.text.isNotEmpty
                        ? _ttsController.text
                        : (_recognizedText.isNotEmpty
                              ? _recognizedText
                              : _speechText);
                    _speak(text);
                  },
                  icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
                  label: Text(_isSpeaking ? 'Stop' : 'Speak'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();

    _listeningController.dispose();
    _speakingController.dispose();
    _ttsController.dispose();

    _cameraService.dispose();
    _modelService.dispose();
    super.dispose();
  }
}


/// Adapter exposing the preserved translator page under the name used by the
/// messaging settings screen.
class SignTranslatorScreen extends StatelessWidget {
  const SignTranslatorScreen({
    super.key,
    required this.prefs,
    required this.onAddHistory,
    required this.onPreferencesChanged,
  });

  final AppUiPreferences prefs;
  final ValueChanged<HistoryItem> onAddHistory;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;

  @override
  Widget build(BuildContext context) {
    return TranslatorPage(prefs: prefs, onAddHistory: onAddHistory);
  }
}

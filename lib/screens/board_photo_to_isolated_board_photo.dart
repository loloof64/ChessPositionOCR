import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:chess_position_ocr/core/fen_recognition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:opencv_core/opencv.dart' as cv;

// Data class to hold both isolated board image and FEN prediction
class BoardAnalysisResult {
  final Uint8List isolatedBoard;
  final String fen;

  BoardAnalysisResult({required this.isolatedBoard, required this.fen});
}

@pragma('vm:entry-point')
Future<Uint8List?> heavyIsolationComputation(Uint8List imageData) async {
  try {
    developer.log(
      'Starting image processing in isolate',
      name: 'ChessboardOCR',
    );
    developer.log(
      'Image data size: ${imageData.length} bytes',
      name: 'ChessboardOCR',
    );

    final result = await extractChessboard(imageData);

    developer.log(
      'Image processing completed successfully',
      name: 'ChessboardOCR',
    );
    return result;
  } catch (e, stackTrace) {
    developer.log('Error in image processing: $e', name: 'ChessboardOCR');
    developer.log('Stack trace: $stackTrace', name: 'ChessboardOCR');
    rethrow; // Re-throw to let the UI handle it
  }
}

class BoardPhotoToIsolatedBoardPhoto extends StatefulWidget {
  const BoardPhotoToIsolatedBoardPhoto({super.key});

  @override
  State<BoardPhotoToIsolatedBoardPhoto> createState() =>
      _BoardPhotoToIsolatedBoardPhotoState();
}

class _BoardPhotoToIsolatedBoardPhotoState
    extends State<BoardPhotoToIsolatedBoardPhoto> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  Future<BoardAnalysisResult?>? _fenFuture;
  bool _isProcessing = false;
  bool _isDisposed = false;
  final FenRecognizer _fenRecognizer = FenRecognizer();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      await _fenRecognizer.initialize();
    } catch (e) {
      developer.log(
        'Failed to initialize FenRecognizer: $e',
        name: 'ChessboardOCR',
      );
    }
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) return;

    try {
      developer.log('Initializing camera...', name: 'ChessboardOCR');
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty && !_isDisposed) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset
              .medium, // Increased to medium for better quality (480×640)
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        // Set capture settings to reduce buffer usage
        try {
          await _cameraController!.initialize();
        } catch (initError) {
          developer.log(
            'Camera initialization error: $initError',
            name: 'ChessboardOCR',
          );
          _cameraController = null;
          return;
        }

        // Reduce frame rate to minimize buffer allocation
        try {
          await _cameraController!.setFocusMode(FocusMode.auto);
          await _cameraController!.setExposureMode(ExposureMode.auto);
        } catch (_) {}

        developer.log('Camera initialized successfully', name: 'ChessboardOCR');
        if (mounted && !_isDisposed) {
          setState(() {});
        }
      }
    } catch (e) {
      developer.log('Camera initialization failed: $e', name: 'ChessboardOCR');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Stop preview first to prevent ongoing operations
    try {
      if (_cameraController != null &&
          _cameraController!.value.isInitialized &&
          _cameraController!.value.isStreamingImages) {
        _cameraController!.stopImageStream();
      }
    } catch (_) {}

    try {
      if (_cameraController != null &&
          _cameraController!.value.isRecordingVideo) {
        _cameraController!.stopVideoRecording();
      }
    } catch (_) {}

    // Pause preview to stop any pending state updates
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        _cameraController!.pausePreview();
      }
    } catch (_) {}

    // Give the platform channel time to process the pause before disposing
    // This prevents the observer from trying to send state updates after disposal
    Future.delayed(Duration(milliseconds: 100), () {
      try {
        _cameraController?.dispose();
      } catch (e) {
        developer.log('Error disposing camera: $e', name: 'ChessboardOCR');
      }
      _cameraController = null;

      // Then dispose other resources
      _fenRecognizer.dispose();
      _fenFuture = null;
    });

    // Call super.dispose() immediately
    super.dispose();
  }

  Future<void> _takePhotoAndConvert() async {
    if (_isProcessing || !mounted) {
      developer.log(
        'Photo already being processed or widget disposed',
        name: 'ChessboardOCR',
      );
      return;
    }

    // Extra safety check for camera controller
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      developer.log('Camera not properly initialized', name: 'ChessboardOCR');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera not ready')));
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    XFile? image;
    try {
      developer.log('Taking photo...', name: 'ChessboardOCR');

      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        developer.log('Camera not initialized', name: 'ChessboardOCR');
        return;
      }

      // Pause preview to reduce buffer usage during capture - with extra safety
      try {
        if (!_isDisposed &&
            _cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _cameraController!.pausePreview();
        }
      } catch (pauseError) {
        developer.log(
          'Error pausing preview: $pauseError',
          name: 'ChessboardOCR',
        );
      }

      image = await _cameraController!.takePicture();

      // Check if widget was disposed while taking photo
      if (_isDisposed) {
        developer.log(
          'Widget disposed during photo capture',
          name: 'ChessboardOCR',
        );
        return;
      }

      developer.log(
        'Photo taken successfully, path: ${image.path}',
        name: 'ChessboardOCR',
      );
      developer.log('Photo name: ${image.name}', name: 'ChessboardOCR');

      // Resume preview after capture - with mounted check
      try {
        if (mounted && _cameraController?.value.isInitialized == true) {
          await _cameraController!.resumePreview();
        }
      } catch (resumeError) {
        developer.log(
          'Error resuming preview: $resumeError',
          name: 'ChessboardOCR',
        );
      }

      // Step 1: Read image bytes
      developer.log('Reading image bytes...', name: 'ChessboardOCR');
      final imageData = await image.readAsBytes();
      developer.log(
        'Image loaded: ${imageData.length} bytes',
        name: 'ChessboardOCR',
      );

      // Step 2: Test OpenCV processing
      final Future<BoardAnalysisResult?>
      fenFuture = Future.delayed(Duration(seconds: 1), () async {
        try {
          developer.log('Starting OpenCV processing...', name: 'ChessboardOCR');

          // Pause camera preview to prevent graphics conflicts during heavy processing
          try {
            if (_cameraController != null &&
                _cameraController!.value.isInitialized) {
              await _cameraController!.pausePreview();
            }
          } catch (_) {}

          // Decode image with OpenCV
          final mat = cv.imdecode(imageData, cv.IMREAD_COLOR);
          developer.log(
            'OpenCV decode successful: ${mat.width}x${mat.height}',
            name: 'ChessboardOCR',
          );

          // Process the image with our full pipeline
          final result = await extractChessboard(imageData);

          // Convert isolated board to FEN
          final fen = await _fenRecognizer.imageToFen(result ?? Uint8List(0));

          // Clean up
          mat.dispose();
          developer.log(
            'Processing completed successfully: $fen',
            name: 'ChessboardOCR',
          );

          // Resume preview after processing
          try {
            if (_cameraController != null &&
                _cameraController!.value.isInitialized) {
              await _cameraController!.resumePreview();
            }
          } catch (_) {}

          return BoardAnalysisResult(
            isolatedBoard: result ?? Uint8List(0),
            fen: fen,
          );
        } catch (e, stackTrace) {
          developer.log('OpenCV processing failed: $e', name: 'ChessboardOCR');
          developer.log('Stack trace: $stackTrace', name: 'ChessboardOCR');
          rethrow; // Let the UI handle the error
        }
      });

      setState(() {
        _fenFuture = fenFuture;
      });

      developer.log('Processing future created', name: 'ChessboardOCR');
    } catch (e, stackTrace) {
      developer.log('Error in _takePhotoAndConvert: $e', name: 'ChessboardOCR');
      developer.log('Stack trace: $stackTrace', name: 'ChessboardOCR');

      // Show Snackbar for early errors
      if (mounted) {
        final message = e is ChessboardExtractionException
            ? e.getUserMessage()
            : 'Failed to capture photo. Please try again.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }

      // Resume preview if there was an error
      try {
        if (_cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _cameraController!.resumePreview();
        }
      } catch (resumeError) {
        developer.log(
          'Error resuming preview: $resumeError',
          name: 'ChessboardOCR',
        );
      }

      // Clean up temporary file
      if (image != null) {
        try {
          final file = File(image.path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (deleteError) {
          developer.log(
            'Error deleting temp file: $deleteError',
            name: 'ChessboardOCR',
          );
        }
      }
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _fenFuture == null
        ? (_cameraController != null && _cameraController!.value.isInitialized
              ? Stack(
                  children: [
                    CameraPreview(_cameraController!),
                    Positioned(
                      bottom: 50,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: FloatingActionButton(
                          onPressed: _isProcessing
                              ? null
                              : _takePhotoAndConvert,
                          backgroundColor: _isProcessing
                              ? Colors.grey
                              : Colors.white,
                          child: _isProcessing
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                  size: 32,
                                ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(child: CircularProgressIndicator()))
        : FutureBuilder<BoardAnalysisResult?>(
            future: _fenFuture,
            builder: (context, snapshot) {
              final result = snapshot.data;
              final fen = result?.fen;
              final image = result?.isolatedBoard;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text("Analyzing board..."),
                  ],
                );
              } else if (snapshot.hasError) {
                // Show Snackbar with error message
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    final error = snapshot.error;
                    final message = error is ChessboardExtractionException
                        ? error.getUserMessage()
                        : 'An unexpected error occurred: $error';

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 4),
                      ),
                    );
                    // Reset to camera view
                    setState(() {
                      _fenFuture = null;
                      _isProcessing = false;
                    });
                  }
                });
                // Show loading indicator briefly while resetting
                return CircularProgressIndicator();
              } else if (snapshot.hasData) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 20,
                    children: [
                      if (image != null && image.isNotEmpty)
                        Container(
                          height: 300,
                          width: 300,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                          ),
                          child: Image.memory(image, fit: BoxFit.contain),
                        ),
                      if (fen != null && fen.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SelectableText(
                            fen,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ElevatedButton(
                        onPressed: () {
                          if (fen != null && fen.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: fen));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('FEN copied to clipboard'),
                              ),
                            );
                          }
                        },
                        child: Text('Copy FEN'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _fenFuture = null;
                            _isProcessing = false;
                          });
                        },
                        child: Text('Take Another Photo'),
                      ),
                    ],
                  ),
                );
              } else {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Photo taken successfully!"),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _fenFuture = null;
                          _isProcessing = false;
                        });
                      },
                      child: Text('Take Another Photo'),
                    ),
                  ],
                );
              }
            },
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Chessboard isolation'),
      ),
      body: Center(child: content),
    );
  }
}

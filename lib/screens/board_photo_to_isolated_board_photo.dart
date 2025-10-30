import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:opencv_core/opencv.dart' as cv;

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
  Future<Uint8List?>? _fenFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      developer.log('Initializing camera...', name: 'ChessboardOCR');
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.low, // Use lower resolution to reduce buffer usage
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        // Set capture settings to reduce buffer usage
        await _cameraController!.initialize();

        // Reduce frame rate to minimize buffer allocation
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);

        developer.log('Camera initialized successfully', name: 'ChessboardOCR');
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      developer.log('Camera initialization failed: $e', name: 'ChessboardOCR');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _fenFuture = null;
    super.dispose();
  }

  Future<void> _takePhotoAndConvert() async {
    if (_isProcessing) {
      developer.log('Photo already being processed', name: 'ChessboardOCR');
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

      // Pause preview to reduce buffer usage during capture
      await _cameraController!.pausePreview();

      image = await _cameraController!.takePicture();
      developer.log(
        'Photo taken successfully, path: ${image.path}',
        name: 'ChessboardOCR',
      );
      developer.log('Photo name: ${image.name}', name: 'ChessboardOCR');

      // Resume preview after capture
      await _cameraController!.resumePreview();

      // Step 1: Read image bytes
      developer.log('Reading image bytes...', name: 'ChessboardOCR');
      final imageData = await image.readAsBytes();
      developer.log(
        'Image loaded: ${imageData.length} bytes',
        name: 'ChessboardOCR',
      );

      // Step 2: Test OpenCV processing
      final Future<Uint8List?>
      fenFuture = Future.delayed(Duration(seconds: 1), () async {
        try {
          developer.log('Starting OpenCV processing...', name: 'ChessboardOCR');

          // Decode image with OpenCV
          final mat = cv.imdecode(imageData, cv.IMREAD_COLOR);
          developer.log(
            'OpenCV decode successful: ${mat.width}x${mat.height}',
            name: 'ChessboardOCR',
          );

          // Process the image with our full pipeline
          final result = await extractChessboard(imageData);

          // Clean up
          mat.dispose();
          developer.log(
            'Processing completed successfully',
            name: 'ChessboardOCR',
          );

          return result;
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
        : FutureBuilder<Uint8List?>(
            future: _fenFuture,
            builder: (context, snapshot) {
              final imageData = snapshot.data;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
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
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 20,
                  children: [
                    if (imageData != null)
                      Image.memory(imageData, fit: BoxFit.cover),
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

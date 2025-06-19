import 'package:opencv_core/opencv.dart' as cv;

/// Extracts and rectifies a quadrilateral region from an image using a perspective transform.
/// [srcImage] is the original OpenCV Mat image.
/// [corners] is a list of four [x, y] points (top-left, top-right, bottom-right, bottom-left).
/// [outputSize] is [width, height] of the output.
/// Returns a new Mat containing the warped (rectified) region.
cv.Mat extractWarpedRegion(
  cv.Mat srcImage,
  List<List<double>> corners,
  List<int> outputSize,
) {
  // Convert corners to VecPoint2f
  final srcPoints = cv.VecPoint2f.fromList(
    corners.map((pt) => cv.Point2f(pt[0], pt[1])).toList(),
  );

  // Define destination rectangle as VecPoint2f
  final width = outputSize[0].toDouble();
  final height = outputSize[1].toDouble();
  final dstPoints = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(width - 1, 0),
    cv.Point2f(width - 1, height - 1),
    cv.Point2f(0, height - 1),
  ]);

  // Get perspective transform matrix
  final perspectiveMat = cv.getPerspectiveTransform2f(srcPoints, dstPoints);

  // Apply perspective warp
  final warped = cv.warpPerspective(srcImage, perspectiveMat, (
    width.toInt(),
    height.toInt(),
  ));

  return warped;
}

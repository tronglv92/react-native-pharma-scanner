package com.margelo.nitro.PharmaScanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.camera.core.ImageProxy
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

interface DocumentDetectorListener {
    fun onDocumentDetected(detection: DocumentDetection, imageWidth: Int, imageHeight: Int)
}

class DocumentDetector {
    companion object {
        private const val TAG = "DocumentDetector"
        private const val MAX_MISS_FRAMES = 8
        private const val MIN_AREA_RATIO = 0.05
        private val opencvInitialized: Boolean by lazy {
            val success = OpenCVLoader.initLocal()
            if (!success) Log.e(TAG, "Failed to initialize OpenCV")
            success
        }
    }

    var listener: DocumentDetectorListener? = null

    private val stabilityFrameCount = 10
    private val stabilityThreshold = 0.02
    private val recentCorners = mutableListOf<Corners>()
    private var frameCounter = 0
    private var consecutiveMisses = 0
    private var lastGoodDetection: DocumentDetection? = null
    private var lastImageWidth = 0
    private var lastImageHeight = 0

    fun detectDocument(imageUri: String): DocumentDetection {
        if (!opencvInitialized) return emptyDetection()

        val path = if (imageUri.startsWith("file://")) {
            imageUri.removePrefix("file://")
        } else {
            imageUri
        }

        val bitmap = BitmapFactory.decodeFile(path) ?: return emptyDetection()
        val mat = Mat()
        Utils.bitmapToMat(bitmap, mat)
        bitmap.recycle()

        val result = detectFromMat(mat)
        mat.release()
        return result
    }

    fun processFrame(imageProxy: ImageProxy) {
        if (!opencvInitialized) {
            imageProxy.close()
            return
        }
        frameCounter++
        if (frameCounter % 3 != 0) {
            imageProxy.close()
            return
        }

        try {
            val mat = imageProxyToMat(imageProxy)
            if (mat != null) {
                lastImageWidth = mat.cols()
                lastImageHeight = mat.rows()

                val detection = detectFromMat(mat)
                mat.release()

                val result = if (detection.detected) {
                    consecutiveMisses = 0
                    lastGoodDetection = detection
                    detection
                } else if (consecutiveMisses < MAX_MISS_FRAMES && lastGoodDetection != null) {
                    consecutiveMisses++
                    lastGoodDetection!!
                } else {
                    consecutiveMisses++
                    lastGoodDetection = null
                    detection
                }

                if (frameCounter % 30 == 0) {
                    Log.d(TAG, "frame #$frameCounter detected=${result.detected} conf=${String.format("%.2f", result.confidence)} stable=${result.isStable} misses=$consecutiveMisses")
                }
                listener?.onDocumentDetected(result, lastImageWidth, lastImageHeight)
            }
        } finally {
            imageProxy.close()
        }
    }

    fun reset() {
        recentCorners.clear()
        frameCounter = 0
        consecutiveMisses = 0
        lastGoodDetection = null
    }

    private fun detectFromMat(src: Mat): DocumentDetection {
        val gray = Mat()
        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)

        val imageArea = src.rows().toDouble() * src.cols().toDouble()
        val candidates = mutableListOf<QuadCandidate>()

        // Try multiple Canny thresholds to handle different contrast levels
        findCandidatesCanny(gray, 30.0, 100.0, imageArea, candidates)
        findCandidatesCanny(gray, 50.0, 150.0, imageArea, candidates)
        findCandidatesCanny(gray, 75.0, 200.0, imageArea, candidates)

        gray.release()

        if (candidates.isEmpty()) {
            return emptyDetection()
        }

        // Pick best candidate by score
        val best = candidates.maxByOrNull { it.score }!!

        val sorted = sortCornerPoints(best.points)
        val detectedCorners = Corners(
            topLeft = Point(x = sorted[0].x / src.cols(), y = sorted[0].y / src.rows()),
            topRight = Point(x = sorted[1].x / src.cols(), y = sorted[1].y / src.rows()),
            bottomLeft = Point(x = sorted[3].x / src.cols(), y = sorted[3].y / src.rows()),
            bottomRight = Point(x = sorted[2].x / src.cols(), y = sorted[2].y / src.rows())
        )
        val confidence = (best.area / imageArea).coerceAtMost(1.0)

        recentCorners.add(detectedCorners)
        if (recentCorners.size > stabilityFrameCount) {
            recentCorners.removeAt(0)
        }

        val isStable = checkStability()
        val smoothedCorners = if (recentCorners.size >= 3) {
            averageCorners(recentCorners.takeLast(3))
        } else {
            detectedCorners
        }

        return DocumentDetection(
            detected = true,
            corners = smoothedCorners,
            confidence = confidence,
            isStable = isStable
        )
    }

    private fun findCandidatesCanny(
        gray: Mat, low: Double, high: Double,
        imageArea: Double, out: MutableList<QuadCandidate>
    ) {
        val blurred = Mat()
        Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

        val edges = Mat()
        Imgproc.Canny(blurred, edges, low, high)
        blurred.release()

        // Close to connect nearby edge fragments
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0))
        Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE, kernel)
        kernel.release()

        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        // RETR_LIST: find all contours (document may be inside desk edge)
        Imgproc.findContours(edges, contours, hierarchy, Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
        edges.release()
        hierarchy.release()

        val sorted = contours.sortedByDescending { Imgproc.contourArea(it) }

        for (contour in sorted) {
            val contour2f = MatOfPoint2f(*contour.toArray())
            val perimeter = Imgproc.arcLength(contour2f, true)
            val approx = MatOfPoint2f()
            Imgproc.approxPolyDP(contour2f, approx, 0.02 * perimeter, true)

            if (approx.rows() == 4) {
                val area = Imgproc.contourArea(approx)

                if (area > imageArea * MIN_AREA_RATIO) {
                    val points = approx.toArray()

                    val matOfPoint = MatOfPoint(*points.map { org.opencv.core.Point(it.x, it.y) }.toTypedArray())
                    val convex = Imgproc.isContourConvex(matOfPoint)
                    matOfPoint.release()

                    if (convex) {
                        val score = scoreCandidate(points, area, imageArea)
                        out.add(QuadCandidate(points, area, score))
                    }
                }
            }

            approx.release()
            contour2f.release()
        }

        contours.forEach { it.release() }
    }

    /**
     * Score a quadrilateral candidate. Higher = more document-like.
     * No hard rejection — just rank by quality.
     */
    private fun scoreCandidate(points: Array<org.opencv.core.Point>, area: Double, imageArea: Double): Double {
        val areaScore = (area / imageArea).coerceIn(0.0, 1.0)
        val rectScore = rectangularityScore(points)
        val aspectScore = aspectRatioScore(points)

        // Weighted: area matters most (we want the document, not small shapes),
        // rectangularity helps distinguish from random quads
        return areaScore * 0.5 + rectScore * 0.3 + aspectScore * 0.2
    }

    /**
     * How close the 4 angles are to 90 degrees.
     * Generous — perspective distortion makes angles deviate.
     */
    private fun rectangularityScore(points: Array<org.opencv.core.Point>): Double {
        var totalDeviation = 0.0
        for (i in points.indices) {
            val prev = points[(i + 3) % 4]
            val curr = points[i]
            val next = points[(i + 1) % 4]
            val angle = angleBetween(prev, curr, next)
            totalDeviation += abs(angle - 90.0)
        }
        // Perfect rectangle: 0 deviation. Very skewed: up to 360.
        // Be generous: even 60 degrees total deviation is acceptable
        return (1.0 - (totalDeviation / 180.0)).coerceIn(0.0, 1.0)
    }

    private fun aspectRatioScore(points: Array<org.opencv.core.Point>): Double {
        val sorted = sortCornerPoints(points)
        val w1 = distance(sorted[0], sorted[1])
        val w2 = distance(sorted[3], sorted[2])
        val h1 = distance(sorted[0], sorted[3])
        val h2 = distance(sorted[1], sorted[2])
        val avgW = (w1 + w2) / 2.0
        val avgH = (h1 + h2) / 2.0
        if (avgW <= 0 || avgH <= 0) return 0.0

        val ratio = max(avgW, avgH) / min(avgW, avgH)
        // Accept 1.0 to 3.0 generously
        return when {
            ratio < 1.0 -> 0.0
            ratio <= 2.0 -> 1.0
            ratio <= 3.0 -> 1.0 - (ratio - 2.0) * 0.5
            else -> 0.2
        }
    }

    private fun angleBetween(a: org.opencv.core.Point, b: org.opencv.core.Point, c: org.opencv.core.Point): Double {
        val v1x = a.x - b.x; val v1y = a.y - b.y
        val v2x = c.x - b.x; val v2y = c.y - b.y
        val dot = v1x * v2x + v1y * v2y
        val mag1 = sqrt(v1x * v1x + v1y * v1y)
        val mag2 = sqrt(v2x * v2x + v2y * v2y)
        if (mag1 == 0.0 || mag2 == 0.0) return 0.0
        val cosAngle = (dot / (mag1 * mag2)).coerceIn(-1.0, 1.0)
        return Math.toDegrees(kotlin.math.acos(cosAngle))
    }

    private fun distance(a: org.opencv.core.Point, b: org.opencv.core.Point): Double {
        val dx = a.x - b.x; val dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private fun averageCorners(cornersList: List<Corners>): Corners {
        val n = cornersList.size.toDouble()
        return Corners(
            topLeft = Point(
                x = cornersList.sumOf { it.topLeft.x } / n,
                y = cornersList.sumOf { it.topLeft.y } / n
            ),
            topRight = Point(
                x = cornersList.sumOf { it.topRight.x } / n,
                y = cornersList.sumOf { it.topRight.y } / n
            ),
            bottomLeft = Point(
                x = cornersList.sumOf { it.bottomLeft.x } / n,
                y = cornersList.sumOf { it.bottomLeft.y } / n
            ),
            bottomRight = Point(
                x = cornersList.sumOf { it.bottomRight.x } / n,
                y = cornersList.sumOf { it.bottomRight.y } / n
            )
        )
    }

    private fun sortCornerPoints(points: Array<org.opencv.core.Point>): Array<org.opencv.core.Point> {
        val sorted = arrayOfNulls<org.opencv.core.Point>(4)
        val sums = points.map { it.x + it.y }
        val diffs = points.map { it.y - it.x }
        sorted[0] = points[sums.indexOf(sums.min())]     // top-left
        sorted[2] = points[sums.indexOf(sums.max())]     // bottom-right
        sorted[1] = points[diffs.indexOf(diffs.min())]   // top-right
        sorted[3] = points[diffs.indexOf(diffs.max())]   // bottom-left
        @Suppress("UNCHECKED_CAST")
        return sorted as Array<org.opencv.core.Point>
    }

    private fun checkStability(): Boolean {
        if (recentCorners.size < stabilityFrameCount) return false
        val reference = recentCorners.last()
        return recentCorners.dropLast(1).all { cornersWithinThreshold(it, reference) }
    }

    private fun cornersWithinThreshold(a: Corners, b: Corners): Boolean {
        return pointsWithinThreshold(a.topLeft, b.topLeft)
                && pointsWithinThreshold(a.topRight, b.topRight)
                && pointsWithinThreshold(a.bottomLeft, b.bottomLeft)
                && pointsWithinThreshold(a.bottomRight, b.bottomRight)
    }

    private fun pointsWithinThreshold(a: Point, b: Point): Boolean {
        return abs(a.x - b.x) < stabilityThreshold
                && abs(a.y - b.y) < stabilityThreshold
    }

    private fun imageProxyToMat(imageProxy: ImageProxy): Mat? {
        try {
            val plane = imageProxy.planes[0]
            val buffer = plane.buffer
            val rowStride = plane.rowStride
            val width = imageProxy.width
            val height = imageProxy.height

            val mat = Mat(height, width, CvType.CV_8UC1)
            if (rowStride == width) {
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)
                mat.put(0, 0, bytes)
            } else {
                val allBytes = ByteArray(buffer.remaining())
                buffer.get(allBytes)
                val rowData = ByteArray(width)
                for (row in 0 until height) {
                    System.arraycopy(allBytes, row * rowStride, rowData, 0, width)
                    mat.put(row, 0, rowData)
                }
            }

            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val rotatedMat = when (rotationDegrees) {
                90 -> {
                    val dst = Mat()
                    Core.transpose(mat, dst)
                    Core.flip(dst, dst, 1)
                    mat.release()
                    dst
                }
                180 -> {
                    val dst = Mat()
                    Core.flip(mat, dst, -1)
                    mat.release()
                    dst
                }
                270 -> {
                    val dst = Mat()
                    Core.transpose(mat, dst)
                    Core.flip(dst, dst, 0)
                    mat.release()
                    dst
                }
                else -> mat
            }

            val bgr = Mat()
            Imgproc.cvtColor(rotatedMat, bgr, Imgproc.COLOR_GRAY2BGR)
            rotatedMat.release()
            return bgr
        } catch (e: Exception) {
            Log.e(TAG, "Failed to convert ImageProxy to Mat", e)
            return null
        }
    }

    private fun emptyDetection(): DocumentDetection {
        val zero = Point(x = 0.0, y = 0.0)
        val corners = Corners(topLeft = zero, topRight = zero, bottomLeft = zero, bottomRight = zero)
        return DocumentDetection(detected = false, corners = corners, confidence = 0.0, isStable = false)
    }

    private data class QuadCandidate(
        val points: Array<org.opencv.core.Point>,
        val area: Double,
        val score: Double
    )
}

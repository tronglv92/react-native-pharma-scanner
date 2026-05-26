package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import android.util.Size
import androidx.camera.core.Camera
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

object CameraManager {
    private const val TAG = "CameraManager"

    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var previewView: PreviewView? = null
    private var currentFlashMode: Int = ImageCapture.FLASH_MODE_AUTO
    var isSessionRunning: Boolean = false
        private set
    private var isContinuousScanActive: Boolean = false
    private var continuousScanFormats: Array<BarcodeFormat> = emptyArray()

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var startRequestId = 0
    private var lastAnalysisTimestamp = 0L
    private var activeBarcodeScanner: com.google.mlkit.vision.barcode.BarcodeScanner? = null
    private const val SCAN_INTERVAL_MS = 250L // Only process a frame every 250ms

    fun startSession(context: Context, lifecycleOwner: LifecycleOwner) {
        val requestId = ++startRequestId

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            // If stopSession() was called before this listener fired, bail out
            if (requestId != startRequestId) {
                Log.d(TAG, "Start cancelled — stopSession was called before bind")
                return@addListener
            }

            val provider = cameraProviderFuture.get()
            cameraProvider = provider

            preview = Preview.Builder().build().also { prev ->
                previewView?.let { pv ->
                    prev.surfaceProvider = pv.surfaceProvider
                }
            }

            imageCapture = ImageCapture.Builder()
                .setFlashMode(currentFlashMode)
                .build()

            @Suppress("DEPRECATION")
            imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setTargetResolution(Size(960, 540))
                .build()

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            try {
                provider.unbindAll()
                camera = provider.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageCapture,
                    imageAnalysis
                )
                isSessionRunning = true
                Log.d(TAG, "Camera session started")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to bind camera use cases", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stopSession() {
        // Invalidate any pending startSession listener
        startRequestId++

        val provider = cameraProvider
        cameraProvider = null
        camera = null
        imageCapture = null
        imageAnalysis = null
        preview = null
        isSessionRunning = false
        isContinuousScanActive = false
        continuousScanFormats = emptyArray()
        BarcodeScannerManager.onBarcodesDetectedCallback = null
        BarcodeScannerManager.activeFormats = emptyArray()
        OcrManager.onTextRecognizedCallback = null
        activeBarcodeScanner?.close()
        activeBarcodeScanner = null

        if (provider != null) {
            mainHandler.post {
                try {
                    provider.unbindAll()
                } catch (e: Exception) {
                    Log.w(TAG, "unbindAll failed during stop", e)
                }
                Log.d(TAG, "Camera session stopped")
            }
        } else {
            Log.d(TAG, "Camera session stopped (no provider)")
        }
    }

    suspend fun capturePhoto(context: Context): Triple<String, Int, Int> {
        val capture = imageCapture
            ?: return generateMockPhoto(context)

        val fileName = "${UUID.randomUUID()}.jpg"
        val photoFile = File(context.cacheDir, fileName)
        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

        return suspendCoroutine { continuation ->
            capture.takePicture(
                outputOptions,
                backgroundExecutor,
                object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                        val uri = "file://${photoFile.absolutePath}"
                        val options = android.graphics.BitmapFactory.Options().apply {
                            inJustDecodeBounds = true
                        }
                        android.graphics.BitmapFactory.decodeFile(photoFile.absolutePath, options)
                        val width = options.outWidth
                        val height = options.outHeight
                        continuation.resume(Triple(uri, width, height))
                    }

                    override fun onError(exception: ImageCaptureException) {
                        if (!isSessionRunning) {
                            // Session was stopped while capture was in-flight — silently
                            // return a mock photo instead of surfacing an error
                            Log.w(TAG, "Capture aborted — camera session was stopped")
                            continuation.resume(generateMockPhoto(context))
                        } else {
                            Log.e(TAG, "Photo capture failed", exception)
                            continuation.resumeWithException(exception)
                        }
                    }
                }
            )
        }
    }

    fun setFlashMode(mode: FlashMode) {
        currentFlashMode = when (mode) {
            FlashMode.AUTO -> ImageCapture.FLASH_MODE_AUTO
            FlashMode.ON -> ImageCapture.FLASH_MODE_ON
            FlashMode.OFF -> ImageCapture.FLASH_MODE_OFF
        }
        imageCapture?.flashMode = currentFlashMode
    }

    fun setZoom(factor: Double) {


        val cam = camera ?: return
        val maxZoom = cam.cameraInfo.zoomState.value?.maxZoomRatio ?: 1f
        val minZoom = cam.cameraInfo.zoomState.value?.minZoomRatio ?: 1f
        val clamped = factor.toFloat().coerceIn(minZoom, maxZoom)
        cam.cameraControl.setZoomRatio(clamped)
    }

    fun startContinuousScan(formats: Array<BarcodeFormat>) {
        val analysis = imageAnalysis ?: return
        continuousScanFormats = formats

        val mlKitFormats = formats.mapNotNull { BarcodeScannerManager.mapToMlKitFormat(it) }.toIntArray()
        val scannerOptions = if (mlKitFormats.isNotEmpty()) {
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(mlKitFormats[0], *mlKitFormats.drop(1).toIntArray())
                .build()
        } else {
            BarcodeScannerOptions.Builder().build()
        }

        // Close previous scanner if any
        activeBarcodeScanner?.close()
        val scanner = BarcodeScanning.getClient(scannerOptions)
        activeBarcodeScanner = scanner
        lastAnalysisTimestamp = 0L

        analysis.setAnalyzer(backgroundExecutor) { imageProxy ->
            val now = System.currentTimeMillis()
            if (now - lastAnalysisTimestamp < SCAN_INTERVAL_MS) {
                // Skip this frame — throttle to reduce CPU/battery usage
                imageProxy.close()
                return@setAnalyzer
            }
            lastAnalysisTimestamp = now
            processBarcode(imageProxy, scanner)
        }
        isContinuousScanActive = true
    }

    fun stopContinuousScan() {
        imageAnalysis?.clearAnalyzer()
        isContinuousScanActive = false
        continuousScanFormats = emptyArray()
        BarcodeScannerManager.onBarcodesDetectedCallback = null
        BarcodeScannerManager.activeFormats = emptyArray()
        activeBarcodeScanner?.close()
        activeBarcodeScanner = null
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun processBarcode(imageProxy: ImageProxy, scanner: com.google.mlkit.vision.barcode.BarcodeScanner) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val inputImage = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)

        scanner.process(inputImage)
            .addOnSuccessListener { barcodes ->
                if (barcodes.isNotEmpty()) {
                    val results = barcodes.mapNotNull { BarcodeScannerManager.mapBarcodeToResult(it) }.toTypedArray()
                    if (results.isNotEmpty()) {
                        BarcodeScannerManager.onBarcodesDetectedCallback?.invoke(results)
                    }
                }
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "Continuous barcode scan failed", e)
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }

    fun bindPreview(view: PreviewView) {
        previewView = view
        preview?.surfaceProvider = view.surfaceProvider
    }

    private fun generateMockPhoto(context: Context): Triple<String, Int, Int> {
        val width = 1920
        val height = 1080

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Gradient background
        val gradientPaint = Paint().apply {
            shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                0xFF2196F3.toInt(), // blue
                0xFF9C27B0.toInt(), // purple
                Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), gradientPaint)

        // Draw text
        val textPaint = Paint().apply {
            color = 0xFFFFFFFF.toInt()
            textSize = 64f
            textAlign = Paint.Align.CENTER
            isFakeBoldText = true
            isAntiAlias = true
        }
        canvas.drawText("Emulator Mock Photo", width / 2f, height / 2f, textPaint)

        // Timestamp
        val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        val timestamp = formatter.format(Date())
        val tsPaint = Paint().apply {
            color = 0xCCFFFFFF.toInt()
            textSize = 32f
            textAlign = Paint.Align.CENTER
            isAntiAlias = true
        }
        canvas.drawText(timestamp, width / 2f, height / 2f + 80f, tsPaint)

        // Save to cache dir
        val fileName = "${UUID.randomUUID()}.jpg"
        val file = File(context.cacheDir, fileName)
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
        }
        bitmap.recycle()

        return Triple("file://${file.absolutePath}", width, height)
    }
}

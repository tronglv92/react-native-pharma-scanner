package com.margelo.nitro.PharmaScanner

import android.app.Activity
import android.graphics.BitmapFactory
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

object DocumentScannerManager {
    private const val TAG = "DocumentScannerManager"

    suspend fun scanDocument(): List<CapturedImage> {
        val activity = ActivityProvider.currentActivity
            ?: throw IllegalStateException("Activity not available")

        val componentActivity = activity as? ComponentActivity
            ?: throw IllegalStateException("Activity is not a ComponentActivity")

        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()

        val scanner = GmsDocumentScanning.getClient(options)

        val intentSender = suspendCoroutine { continuation ->
            scanner.getStartScanIntent(componentActivity)
                .addOnSuccessListener { sender ->
                    continuation.resume(sender)
                }
                .addOnFailureListener { e ->
                    continuation.resumeWithException(e)
                }
        }

        return suspendCoroutine { continuation ->
            val key = "documentScan_${System.currentTimeMillis()}"
            val registry = componentActivity.activityResultRegistry

            var launcher: androidx.activity.result.ActivityResultLauncher<IntentSenderRequest>? = null

            launcher = registry.register(
                key,
                ActivityResultContracts.StartIntentSenderForResult()
            ) { result ->
                launcher?.unregister()

                if (result.resultCode == Activity.RESULT_OK) {
                    val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(result.data)
                    val pages = scanningResult?.getPages()

                    if (pages.isNullOrEmpty()) {
                        continuation.resume(emptyList())
                        return@register
                    }

                    val images = pages.mapNotNull { page ->
                        val uri = page.getImageUri()
                        try {
                            // Enhance image (sharpen + fix dark spots) before returning
                            val (enhancedUri, enhancedW, enhancedH) =
                                ImageProcessor.enhanceScannedImage(uri.toString())

                            CapturedImage(
                                uri = enhancedUri,
                                width = enhancedW.toDouble(),
                                height = enhancedH.toDouble(),
                                base64 = null
                            )
                        } catch (e: Exception) {
                            // Fallback to original image if enhancement fails (e.g. OOM)
                            Log.w(TAG, "Enhancement failed, using original image", e)
                            try {
                                val inputStream = componentActivity.contentResolver.openInputStream(uri)
                                val bitmapOptions = BitmapFactory.Options().apply {
                                    inJustDecodeBounds = true
                                }
                                BitmapFactory.decodeStream(inputStream, null, bitmapOptions)
                                inputStream?.close()

                                CapturedImage(
                                    uri = uri.toString(),
                                    width = bitmapOptions.outWidth.toDouble(),
                                    height = bitmapOptions.outHeight.toDouble(),
                                    base64 = null
                                )
                            } catch (e2: Exception) {
                                Log.e(TAG, "Failed to read scanned page dimensions", e2)
                                null
                            }
                        }
                    }

                    continuation.resume(images)
                } else {
                    // User cancelled — return empty list (not an error)
                    Log.d(TAG, "Document scan cancelled by user")
                    continuation.resume(emptyList())
                }
            }

            launcher.launch(IntentSenderRequest.Builder(intentSender).build())
        }
    }
}

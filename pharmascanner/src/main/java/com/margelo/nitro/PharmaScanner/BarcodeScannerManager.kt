package com.margelo.nitro.PharmaScanner

import android.net.Uri
import android.util.Log
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

object BarcodeScannerManager {
    private const val TAG = "BarcodeScannerManager"

    var onBarcodesDetectedCallback: ((Array<BarcodeResult>) -> Unit)? = null
    var activeFormats: Array<BarcodeFormat> = emptyArray()

    suspend fun scanBarcodes(options: com.margelo.nitro.PharmaScanner.BarcodeScanOptions): Array<BarcodeResult> {
        val context = ActivityProvider.currentActivity
            ?: throw IllegalStateException("Activity not available")

        val uri = Uri.parse(options.imageUri)
        val image = InputImage.fromFilePath(context, uri)

        val mlKitFormats = options.formats.mapNotNull { mapToMlKitFormat(it) }.toIntArray()
        val scannerOptions = if (mlKitFormats.isNotEmpty()) {
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(mlKitFormats[0], *mlKitFormats.drop(1).toIntArray())
                .build()
        } else {
            BarcodeScannerOptions.Builder().build()
        }

        val scanner = BarcodeScanning.getClient(scannerOptions)

        return suspendCoroutine { continuation ->
            scanner.process(image)
                .addOnSuccessListener { barcodes ->
                    val results = barcodes.mapNotNull { mapBarcodeToResult(it) }.toTypedArray()
                    scanner.close()
                    continuation.resume(results)
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Barcode scanning failed", e)
                    scanner.close()
                    continuation.resumeWithException(e)
                }
        }
    }

    fun mapToMlKitFormat(format: BarcodeFormat): Int? {
        return when (format) {
            BarcodeFormat.QR_CODE -> Barcode.FORMAT_QR_CODE
            BarcodeFormat.CODE_128 -> Barcode.FORMAT_CODE_128
            BarcodeFormat.PDF_417 -> Barcode.FORMAT_PDF417
            BarcodeFormat.DATA_MATRIX -> Barcode.FORMAT_DATA_MATRIX
            BarcodeFormat.EAN_13 -> Barcode.FORMAT_EAN_13
            BarcodeFormat.EAN_8 -> Barcode.FORMAT_EAN_8
        }
    }

    fun mapMlKitFormatToBarcode(format: Int): BarcodeFormat? {
        return when (format) {
            Barcode.FORMAT_QR_CODE -> BarcodeFormat.QR_CODE
            Barcode.FORMAT_CODE_128 -> BarcodeFormat.CODE_128
            Barcode.FORMAT_PDF417 -> BarcodeFormat.PDF_417
            Barcode.FORMAT_DATA_MATRIX -> BarcodeFormat.DATA_MATRIX
            Barcode.FORMAT_EAN_13 -> BarcodeFormat.EAN_13
            Barcode.FORMAT_EAN_8 -> BarcodeFormat.EAN_8
            else -> null
        }
    }

    fun mapBarcodeToResult(barcode: Barcode): BarcodeResult? {
        val format = mapMlKitFormatToBarcode(barcode.format) ?: return null
        val value = barcode.displayValue ?: barcode.rawValue ?: ""
        val rawValue = barcode.rawValue ?: ""
        val rect = barcode.boundingBox
        val boundingBox = if (rect != null) {
            FrameRect(
                x = rect.left.toDouble(),
                y = rect.top.toDouble(),
                width = rect.width().toDouble(),
                height = rect.height().toDouble()
            )
        } else {
            null
        }
        return BarcodeResult(
            format = format,
            value = value,
            rawValue = rawValue,
            boundingBox = boundingBox
        )
    }
}

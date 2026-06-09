package com.margelo.nitro.PharmaScanner

import android.content.Context
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

object DocumentExtractor {
    private const val TAG = "DocumentExtractor"

    fun configure(apiKey: String, baseUrl: String) {
        // No-op — kept for Nitro bridge API compatibility.
        // Online extraction (Mistral) is handled in JS.
    }

    suspend fun extract(
        imageUri: String,
        documentType: String,
        language: String,
        customPrompt: String?,
        forceOffline: Boolean
    ): DocumentExtractionResult {
        Log.d(TAG, "extract() called: customPrompt=$customPrompt, docType=$documentType")
        val startTime = System.currentTimeMillis()

        // Assess image quality before processing
        val qualityWarnings = assessImageQuality(imageUri)
        Log.d(TAG, "Image quality assessed: ${qualityWarnings.size} warnings")

        // Local LLM path (Qwen3 via llama.cpp)
        if (customPrompt == "__local_llm__") {
            val wakeLock = acquireInferenceWakeLock()
            // Start foreground service to prevent Samsung/OEM from freezing the process
            try {
                InferenceForegroundService.start(ActivityProvider.applicationContext)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to start foreground service", e)
            }
            try {
                val result = withTimeout(180_000L) {
                    localLlmExtraction(imageUri, documentType, startTime)
                }
                return appendWarnings(result, qualityWarnings)
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                throw IllegalStateException(
                    "Document extraction timed out. The device may be too slow for local LLM processing."
                )
            } finally {
                wakeLock?.let {
                    if (it.isHeld) it.release()
                    Log.d(TAG, "Inference WakeLock released")
                }
                try {
                    InferenceForegroundService.stop(ActivityProvider.applicationContext)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to stop foreground service", e)
                }
            }
        }

        // All other extraction (Mistral) is handled in JS.
        // Native fallback: return raw OCR text.
        val result = ocrFallback(imageUri, documentType, startTime)
        return appendWarnings(result, qualityWarnings)
    }

    private fun acquireInferenceWakeLock(): PowerManager.WakeLock? {
        return try {
            val context = ActivityProvider.applicationContext
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val lock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "PharmaScanner:LlmInference"
            )
            lock.acquire(5 * 60 * 1000L) // 5 minute timeout
            Log.d(TAG, "Inference WakeLock acquired")
            lock
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire WakeLock", e)
            null
        }
    }

    // --- Image Quality Assessment ---

    private fun assessImageQuality(imageUri: String): List<String> {
        return try {
            val quality = ImageQualityAssessor.assess(imageUri)
            val warnings = quality.warnings.toMutableList()
            if (quality.rating == "poor") {
                warnings.add("IMAGE_QUALITY:poor - results may be unreliable")
            }
            warnings
        } catch (e: Exception) {
            Log.w(TAG, "Image quality assessment failed", e)
            emptyList()
        }
    }

    private fun appendWarnings(result: DocumentExtractionResult, extra: List<String>): DocumentExtractionResult {
        if (extra.isEmpty()) return result
        val allWarnings = result.warnings.toMutableList()
        allWarnings.addAll(extra)
        return DocumentExtractionResult(
            documentType = result.documentType,
            data = result.data,
            rawText = result.rawText,
            confidence = result.confidence,
            extractionMethod = result.extractionMethod,
            processingTimeMs = result.processingTimeMs,
            ocrTimeMs = result.ocrTimeMs,
            warnings = allWarnings.toTypedArray()
        )
    }

    // --- Confidence Scoring ---

    private fun computeAggregateConfidence(ocrResult: OcrResult): Double {
        var totalWeight = 0.0
        var weightedSum = 0.0

        for (block in ocrResult.blocks) {
            for (line in block.lines) {
                val weight = line.text.length.toDouble()
                weightedSum += line.confidence * weight
                totalWeight += weight
            }
        }

        return if (totalWeight > 0) weightedSum / totalWeight else 0.5
    }

    private fun lowConfidenceWarnings(ocrResult: OcrResult): List<String> {
        val warnings = mutableListOf<String>()
        for (block in ocrResult.blocks) {
            for (line in block.lines) {
                if (line.confidence < 0.7 && line.text.isNotEmpty()) {
                    val pct = (line.confidence * 100).toInt()
                    val truncated = line.text.take(50)
                    warnings.add("LOW_OCR_CONFIDENCE:$truncated ($pct%)")
                }
            }
        }
        return warnings
    }

    // --- Local LLM extraction (Qwen3 via llama.cpp) ---

    private suspend fun localLlmExtraction(
        imageUri: String,
        documentType: String,
        startTime: Long
    ): DocumentExtractionResult {
        // 1. Run OCR via existing OcrManager
        Log.d(TAG, "LocalLLM [1/5] Starting OCR...")
        val ocrStart = System.currentTimeMillis()
        val ocrResult = OcrManager.recognizeText(imageUri)
        val ocrText = ocrResult.text
        val ocrTimeMs = (System.currentTimeMillis() - ocrStart).toDouble()
        Log.d(TAG, "LocalLLM [1/5] OCR done: ${ocrTimeMs.toLong()}ms, ${ocrText.length} chars")

        if (ocrText.isBlank()) {
            throw IllegalStateException("No text recognized in the image.")
        }

        // 2. Check model availability
        if (!LlamaCppManager.isModelDownloaded) {
            throw IllegalStateException("Local LLM model not downloaded. Please download the model first.")
        }

        // 3. Load model if not already loaded (on IO thread to avoid blocking main thread)
        if (!LlamaCppManager.isModelLoaded) {
            Log.d(TAG, "LocalLLM [2/5] Loading model into memory...")
            withContext(Dispatchers.IO) {
                LlamaCppManager.loadModel()
            }
            Log.d(TAG, "LocalLLM [2/5] Model loaded")
        } else {
            Log.d(TAG, "LocalLLM [2/5] Model already in memory")
        }

        // 4. Build prompt with JSON schema for document type
        val schema = schemaForDocumentType(documentType)
        val prompt = LlamaCppManager.buildPrompt(ocrText, schema)
        Log.d(TAG, "LocalLLM [3/5] Prompt built: ${prompt.length} chars")

        // 5. Generate structured JSON (runs on Dispatchers.Default inside LlamaCppManager)
        Log.d(TAG, "LocalLLM [4/5] Generating structured JSON...")
        val rawOutput = LlamaCppManager.generate(prompt)
        Log.d(TAG, "LocalLLM [4/5] Generation done: ${rawOutput.length} chars")

        // 6. Extract JSON from output
        val jsonString = extractJSON(rawOutput) ?: "{}"
        val elapsed = (System.currentTimeMillis() - startTime).toDouble()
        Log.d(TAG, "LocalLLM [5/5] Complete: ${elapsed.toLong()}ms total")

        // 7. Compute confidence from OCR quality
        val ocrConfidence = computeAggregateConfidence(ocrResult)
        val confidence = minOf(ocrConfidence, 0.90)
        val warnings = lowConfidenceWarnings(ocrResult)

        return DocumentExtractionResult(
            documentType = if (documentType == "auto") "invoice" else documentType,
            data = jsonString,
            rawText = ocrText,
            confidence = confidence,
            extractionMethod = "local_llm",
            processingTimeMs = elapsed,
            ocrTimeMs = ocrTimeMs,
            warnings = warnings.toTypedArray()
        )
    }

    private suspend fun ocrFallback(
        imageUri: String,
        documentType: String,
        startTime: Long
    ): DocumentExtractionResult {
        val ocrResult = OcrManager.recognizeText(imageUri)
        val ocrText = ocrResult.text
        val ocrTimeMs = ocrResult.processingTimeMs
        val elapsed = (System.currentTimeMillis() - startTime).toDouble()

        val lines = ocrText.split("\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        val resolvedType = if (documentType == "auto") "invoice" else documentType
        val data = JSONObject().apply {
            put("_documentType", resolvedType)
            put("content", JSONObject().apply {
                put("lines", org.json.JSONArray(lines))
            })
        }

        // Compute confidence from OCR quality, scaled down for fallback mode
        val ocrConfidence = computeAggregateConfidence(ocrResult)
        val confidence = ocrConfidence * 0.3
        val warnings = mutableListOf("Use Mistral mode for structured extraction.")
        warnings.addAll(lowConfidenceWarnings(ocrResult))

        return DocumentExtractionResult(
            documentType = resolvedType,
            data = data.toString(),
            rawText = ocrText,
            confidence = confidence,
            extractionMethod = "ocr_only",
            processingTimeMs = elapsed,
            ocrTimeMs = ocrTimeMs,
            warnings = warnings.toTypedArray()
        )
    }

    // --- JSON schemas (matching iOS) ---

    private fun schemaForDocumentType(documentType: String): String {
        return when (documentType) {
            "invoice", "auto" -> """
{
  "invoiceNumber": "string",
  "date": "string",
  "dueDate": "string",
  "seller": { "name": "string", "address": "string", "taxId": "string" },
  "buyer": { "name": "string", "address": "string", "taxId": "string" },
  "items": [{ "name": "string", "quantity": "number", "unit": "string", "unitPrice": "number", "amount": "number" }],
  "subtotal": "number",
  "tax": "number",
  "total": "number",
  "currency": "string",
  "notes": "string"
}""".trimIndent()

            "prescription" -> """
{
  "patientName": "string",
  "doctorName": "string",
  "date": "string",
  "facility": "string",
  "diagnosis": "string",
  "medications": [{ "name": "string", "dosage": "string", "quantity": "string", "instructions": "string" }],
  "notes": "string"
}""".trimIndent()

            "receipt" -> """
{
  "storeName": "string",
  "storeAddress": "string",
  "date": "string",
  "items": [{ "name": "string", "quantity": "number", "price": "number" }],
  "subtotal": "number",
  "tax": "number",
  "total": "number",
  "paymentMethod": "string"
}""".trimIndent()

            "id_card" -> """
{
  "fullName": "string",
  "dateOfBirth": "string",
  "idNumber": "string",
  "address": "string",
  "issueDate": "string",
  "expiryDate": "string",
  "issuingAuthority": "string"
}""".trimIndent()

            else -> """
{
  "documentType": "string",
  "content": "object",
  "extractedFields": "object"
}""".trimIndent()
        }
    }

    // --- JSON extraction (bracket-matching) ---

    private fun extractJSON(text: String): String? {
        val startIdx = text.indexOf('{')
        if (startIdx == -1) return null

        var depth = 0
        var endIdx = -1
        val bracketStack = mutableListOf<Char>()
        for (i in startIdx until text.length) {
            when (text[i]) {
                '{' -> { depth++; bracketStack.add('{') }
                '[' -> bracketStack.add('[')
                '}' -> {
                    depth--
                    if (bracketStack.isNotEmpty() && bracketStack.last() == '{') bracketStack.removeAt(bracketStack.size - 1)
                    if (depth == 0) {
                        endIdx = i
                        break
                    }
                }
                ']' -> {
                    if (bracketStack.isNotEmpty() && bracketStack.last() == '[') bracketStack.removeAt(bracketStack.size - 1)
                }
            }
        }

        if (endIdx != -1) return text.substring(startIdx, endIdx + 1)

        // JSON is truncated — repair by closing open brackets/braces
        Log.w(TAG, "JSON truncated, repairing (${bracketStack.size} unclosed brackets)")
        val truncated = text.substring(startIdx).trimEnd().trimEnd(',')
        val sb = StringBuilder(truncated)
        // Close any trailing incomplete value (string or number)
        val lastChar = sb.lastOrNull()
        if (lastChar != null && lastChar != '}' && lastChar != ']' && lastChar != '"' &&
            !lastChar.isDigit() && lastChar != 'e' && lastChar != 'l') {
            // Likely mid-value, try to close a string
            sb.append('"')
        }
        for (bracket in bracketStack.reversed()) {
            when (bracket) {
                '[' -> sb.append(']')
                '{' -> sb.append('}')
            }
        }
        return sb.toString()
    }
}

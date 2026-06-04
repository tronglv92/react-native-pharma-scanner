package com.margelo.nitro.PharmaScanner

import android.util.Log
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
        val startTime = System.currentTimeMillis()

        // Local LLM path (Qwen3-1.7B via llama.cpp)
        if (customPrompt == "__local_llm__") {
            return localLlmExtraction(imageUri, documentType, startTime)
        }

        // All other extraction (Mistral) is handled in JS.
        // Native fallback: return raw OCR text.
        return ocrFallback(imageUri, documentType, startTime)
    }

    // --- Local LLM extraction (Qwen3 via llama.cpp) ---

    private suspend fun localLlmExtraction(
        imageUri: String,
        documentType: String,
        startTime: Long
    ): DocumentExtractionResult {
        // 1. Run OCR via existing OcrManager
        val ocrStart = System.currentTimeMillis()
        val ocrResult = OcrManager.recognizeText(imageUri)
        val ocrText = ocrResult.text
        val ocrTimeMs = (System.currentTimeMillis() - ocrStart).toDouble()

        if (ocrText.isBlank()) {
            throw IllegalStateException("No text recognized in the image.")
        }

        // 2. Check model availability
        if (!LlamaCppManager.isModelDownloaded) {
            throw IllegalStateException("Local LLM model not downloaded. Please download the model first.")
        }

        // 3. Load model if not already loaded
        if (!LlamaCppManager.isModelLoaded) {
            LlamaCppManager.loadModel()
        }

        // 4. Build prompt with JSON schema for document type
        val schema = schemaForDocumentType(documentType)
        val prompt = LlamaCppManager.buildPrompt(ocrText, schema)

        // 5. Generate structured JSON
        val rawOutput = LlamaCppManager.generate(prompt)

        // 6. Extract JSON from output
        val jsonString = extractJSON(rawOutput) ?: "{}"
        val elapsed = (System.currentTimeMillis() - startTime).toDouble()

        return DocumentExtractionResult(
            documentType = if (documentType == "auto") "invoice" else documentType,
            data = jsonString,
            rawText = ocrText,
            confidence = 0.80,
            extractionMethod = "local_llm",
            processingTimeMs = elapsed,
            ocrTimeMs = ocrTimeMs,
            warnings = arrayOf()
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

        val data = JSONObject().apply {
            put("_documentType", documentType)
            put("content", JSONObject().apply {
                put("lines", org.json.JSONArray(lines))
            })
        }

        return DocumentExtractionResult(
            documentType = documentType,
            data = data.toString(),
            rawText = ocrText,
            confidence = 0.1,
            extractionMethod = "ocr_only",
            processingTimeMs = elapsed,
            ocrTimeMs = ocrTimeMs,
            warnings = arrayOf("Use Mistral mode for structured extraction.")
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
        for (i in startIdx until text.length) {
            when (text[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) {
                        endIdx = i
                        break
                    }
                }
            }
        }

        if (endIdx == -1) return null
        return text.substring(startIdx, endIdx + 1)
    }
}

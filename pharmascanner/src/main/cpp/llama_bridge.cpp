#include <jni.h>
#include <string>
#include <vector>
#include <cstdlib>
#include <chrono>
#include <thread>
#include <algorithm>
#include <android/log.h>

#include "llama.h"
#include "ggml-backend.h"
#include "mtmd.h"
#include "mtmd-helper.h"

#define LOG_TAG "LlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static llama_model    *g_model    = nullptr;
static llama_context  *g_context  = nullptr;
static llama_sampler  *g_sampler  = nullptr;
static mtmd_context   *g_mtmd_ctx = nullptr;

extern "C" {

JNIEXPORT void JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeInitBackend(
    JNIEnv *env, jobject /* thiz */, jstring nativeLibDir) {

    const char *path = env->GetStringUTFChars(nativeLibDir, nullptr);
    if (path) {
        LOGI("Loading CPU backend variants from: %s", path);
        ggml_backend_load_all_from_path(path);
        env->ReleaseStringUTFChars(nativeLibDir, path);
    }
    llama_backend_init();

    // Log registered backends for diagnostics
    size_t n_backends = ggml_backend_reg_count();
    LOGI("Backend initialized: %zu backends registered", n_backends);
    for (size_t i = 0; i < n_backends; i++) {
        ggml_backend_reg_t reg = ggml_backend_reg_get(i);
        LOGI("  backend[%zu]: %s", i, ggml_backend_reg_name(reg));
    }
}

JNIEXPORT jboolean JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeLoadModel(
    JNIEnv *env, jobject /* thiz */, jstring modelPath, jstring mmprojPath, jint nGpuLayers) {

    if (g_model != nullptr) {
        LOGI("Model already loaded, skipping");
        return JNI_TRUE;
    }

    const char *path = env->GetStringUTFChars(modelPath, nullptr);
    if (!path) {
        LOGE("Failed to get model path string");
        return JNI_FALSE;
    }

    const char *mmproj = env->GetStringUTFChars(mmprojPath, nullptr);
    if (!mmproj) {
        LOGE("Failed to get mmproj path string");
        env->ReleaseStringUTFChars(modelPath, path);
        return JNI_FALSE;
    }

    LOGI("=== nativeLoadModel START ===");
    LOGI("Loading text model from: %s", path);
    LOGI("Loading mmproj from: %s", mmproj);

    // Model params — CPU only on Android
    LOGI("[Load 1/4] Loading text model file...");
    auto t_load_start = std::chrono::steady_clock::now();
    auto model_params = llama_model_default_params();
    model_params.n_gpu_layers = static_cast<int32_t>(nGpuLayers);

    g_model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(modelPath, path);

    if (!g_model) {
        LOGE("[Load 1/4] FAILED to load text model");
        env->ReleaseStringUTFChars(mmprojPath, mmproj);
        return JNI_FALSE;
    }
    auto t_model_loaded = std::chrono::steady_clock::now();
    double model_load_ms = std::chrono::duration<double, std::milli>(t_model_loaded - t_load_start).count();
    LOGI("[Load 1/4] Text model loaded in %.1f ms", model_load_ms);

    // Context params — vision needs larger context for image tokens + prompt + generation
    LOGI("[Load 2/4] Creating llama context (n_ctx=4096)...");
    auto ctx_params = llama_context_default_params();
    ctx_params.n_ctx   = 4096;
    ctx_params.n_batch = 512;

    // Use available CPU cores (capped at 4 to reduce thermal throttling)
    unsigned int hw_threads = std::thread::hardware_concurrency();
    int n_threads = static_cast<int>(std::min(hw_threads, 4u));
    if (n_threads < 1) n_threads = 2;
    ctx_params.n_threads       = n_threads;
    ctx_params.n_threads_batch = n_threads;
    LOGI("Using %d threads (hardware: %u)", n_threads, hw_threads);

    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGE("[Load 2/4] FAILED to create context");
        llama_model_free(g_model);
        g_model = nullptr;
        env->ReleaseStringUTFChars(mmprojPath, mmproj);
        return JNI_FALSE;
    }
    auto t_ctx_created = std::chrono::steady_clock::now();
    double ctx_ms = std::chrono::duration<double, std::milli>(t_ctx_created - t_model_loaded).count();
    LOGI("[Load 2/4] Context created in %.1f ms", ctx_ms);

    // Initialize mtmd (multimodal) context for vision
    LOGI("[Load 3/4] Initializing mtmd vision context (image_max_tokens=768)...");
    mtmd_context_params mparams = mtmd_context_params_default();
    mparams.use_gpu          = false;  // CPU only on Android
    mparams.print_timings    = true;
    mparams.n_threads        = n_threads;
    mparams.warmup           = false;
    mparams.image_max_tokens = 768;    // Limit vision tokens to reduce compute/heat (default ~1600)

    g_mtmd_ctx = mtmd_init_from_file(mmproj, g_model, mparams);
    env->ReleaseStringUTFChars(mmprojPath, mmproj);

    if (!g_mtmd_ctx) {
        LOGE("[Load 3/4] FAILED to initialize mtmd context");
        llama_free(g_context);
        g_context = nullptr;
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }
    auto t_mtmd_created = std::chrono::steady_clock::now();
    double mtmd_ms = std::chrono::duration<double, std::milli>(t_mtmd_created - t_ctx_created).count();
    LOGI("[Load 3/4] mtmd context created in %.1f ms", mtmd_ms);

    if (!mtmd_support_vision(g_mtmd_ctx)) {
        LOGE("[Load 3/4] Model does not support vision input");
        mtmd_free(g_mtmd_ctx);
        g_mtmd_ctx = nullptr;
        llama_free(g_context);
        g_context = nullptr;
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }

    // Greedy sampling — JSON extraction is deterministic
    LOGI("[Load 4/4] Initializing greedy sampler...");
    g_sampler = llama_sampler_init_greedy();

    auto t_load_end = std::chrono::steady_clock::now();
    double total_load_ms = std::chrono::duration<double, std::milli>(t_load_end - t_load_start).count();
    LOGI("=== nativeLoadModel END (%.1f ms total) ===", total_load_ms);
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeGenerateFromImage(
    JNIEnv *env, jobject /* thiz */, jstring prompt, jstring imagePath, jint maxTokens) {

    if (!g_model || !g_context || !g_sampler || !g_mtmd_ctx) {
        LOGE("Model not loaded");
        return env->NewStringUTF("");
    }

    const char *prompt_jni = env->GetStringUTFChars(prompt, nullptr);
    if (!prompt_jni) {
        LOGE("Failed to get prompt string");
        return env->NewStringUTF("");
    }
    std::string prompt_str(prompt_jni);
    env->ReleaseStringUTFChars(prompt, prompt_jni);

    const char *img_path_jni = env->GetStringUTFChars(imagePath, nullptr);
    if (!img_path_jni) {
        LOGE("Failed to get image path string");
        return env->NewStringUTF("");
    }
    std::string img_path(img_path_jni);
    env->ReleaseStringUTFChars(imagePath, img_path_jni);

    LOGI("=== nativeGenerateFromImage START ===");
    LOGI("Image path: %s", img_path.c_str());
    LOGI("Prompt length: %zu chars", prompt_str.size());

    auto t_start = std::chrono::steady_clock::now();

    // Step 1: Load image bitmap from file
    LOGI("[Step 1/5] Loading image bitmap from file...");
    mtmd_bitmap *bitmap = mtmd_helper_bitmap_init_from_file(g_mtmd_ctx, img_path.c_str());
    if (!bitmap) {
        LOGE("[Step 1/5] FAILED to load image from: %s", img_path.c_str());
        return env->NewStringUTF("");
    }
    auto t_img_load = std::chrono::steady_clock::now();
    double img_load_ms = std::chrono::duration<double, std::milli>(t_img_load - t_start).count();
    LOGI("[Step 1/5] Image loaded: %ux%u in %.1f ms", mtmd_bitmap_get_nx(bitmap), mtmd_bitmap_get_ny(bitmap), img_load_ms);

    // Step 2: Clear KV cache
    LOGI("[Step 2/5] Clearing KV cache...");
    llama_memory_t mem = llama_get_memory(g_context);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    LOGI("[Step 2/5] KV cache cleared");

    // Step 3: Tokenize prompt with image (prompt must contain <__media__> marker)
    LOGI("[Step 3/5] Tokenizing prompt with image...");
    mtmd_input_chunks *chunks = mtmd_input_chunks_init();
    mtmd_input_text text;
    text.text         = prompt_str.c_str();
    text.add_special  = true;
    text.parse_special = true;

    const mtmd_bitmap *bitmaps[] = { bitmap };
    int32_t tok_ret = mtmd_tokenize(g_mtmd_ctx, chunks, &text, bitmaps, 1);
    mtmd_bitmap_free(bitmap);

    if (tok_ret != 0) {
        LOGE("[Step 3/5] mtmd_tokenize FAILED: %d", tok_ret);
        mtmd_input_chunks_free(chunks);
        return env->NewStringUTF("");
    }

    size_t n_chunks = mtmd_input_chunks_size(chunks);
    size_t total_tokens = mtmd_helper_get_n_tokens(chunks);
    LOGI("[Step 3/5] Tokenized: %zu chunks, %zu total tokens", n_chunks, total_tokens);

    // Log details of each chunk
    for (size_t ci = 0; ci < n_chunks; ci++) {
        const mtmd_input_chunk *chunk = mtmd_input_chunks_get(chunks, ci);
        auto ctype = mtmd_input_chunk_get_type(chunk);
        size_t ctokens = mtmd_input_chunk_get_n_tokens(chunk);
        const char *type_str = (ctype == MTMD_INPUT_CHUNK_TYPE_TEXT) ? "TEXT" :
                               (ctype == MTMD_INPUT_CHUNK_TYPE_IMAGE) ? "IMAGE" : "AUDIO";
        LOGI("  chunk[%zu]: type=%s, tokens=%zu", ci, type_str, ctokens);
    }

    // Step 4: Eval chunks one by one (to identify which step gets stuck)
    LOGI("[Step 4/5] Evaluating %zu chunks (prefill)...", n_chunks);
    auto t_prefill_start = std::chrono::steady_clock::now();
    llama_pos n_past = 0;

    for (size_t ci = 0; ci < n_chunks; ci++) {
        const mtmd_input_chunk *chunk = mtmd_input_chunks_get(chunks, ci);
        auto ctype = mtmd_input_chunk_get_type(chunk);
        size_t ctokens = mtmd_input_chunk_get_n_tokens(chunk);
        bool is_last = (ci == n_chunks - 1);

        const char *type_str = (ctype == MTMD_INPUT_CHUNK_TYPE_TEXT) ? "TEXT" :
                               (ctype == MTMD_INPUT_CHUNK_TYPE_IMAGE) ? "IMAGE" : "AUDIO";
        LOGI("[Step 4/5] Evaluating chunk %zu/%zu (type=%s, tokens=%zu)...", ci + 1, n_chunks, type_str, ctokens);

        auto t_chunk_start = std::chrono::steady_clock::now();
        int32_t eval_ret = mtmd_helper_eval_chunk_single(g_mtmd_ctx, g_context, chunk, n_past, 0, 512, is_last, &n_past);

        if (eval_ret != 0) {
            LOGE("[Step 4/5] Chunk %zu eval FAILED: %d", ci, eval_ret);
            mtmd_input_chunks_free(chunks);
            return env->NewStringUTF("");
        }
        auto t_chunk_end = std::chrono::steady_clock::now();
        double chunk_ms = std::chrono::duration<double, std::milli>(t_chunk_end - t_chunk_start).count();
        LOGI("[Step 4/5] Chunk %zu/%zu done in %.1f ms (n_past=%d)", ci + 1, n_chunks, chunk_ms, (int)n_past);
    }

    mtmd_input_chunks_free(chunks);

    auto t_prefill_end = std::chrono::steady_clock::now();
    double prefill_ms = std::chrono::duration<double, std::milli>(t_prefill_end - t_prefill_start).count();
    LOGI("[Step 4/5] Prefill done: %zu tokens in %.1f ms (%.1f tok/s)",
         total_tokens, prefill_ms, total_tokens / (prefill_ms / 1000.0));

    // Step 5: Autoregressive generation with early JSON stop
    LOGI("[Step 5/5] Starting token generation (max %d tokens)...", static_cast<int>(maxTokens));
    auto t_gen_start = std::chrono::steady_clock::now();
    std::string output;
    int max_gen = static_cast<int>(maxTokens);
    const llama_vocab *vocab = llama_model_get_vocab(g_model);
    llama_token eos_token = llama_vocab_eos(vocab);
    int brace_depth = 0;
    bool json_started = false;
    int gen_tokens = 0;

    for (int i = 0; i < max_gen; i++) {
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);

        // Check for end of sequence
        if (new_token == eos_token || llama_vocab_is_eog(vocab, new_token)) {
            LOGI("EOS at token %d", i);
            break;
        }

        gen_tokens++;

        // Convert token to text
        char buf[256];
        int n_chars = llama_token_to_piece(
            vocab,
            new_token,
            buf,
            sizeof(buf),
            0,
            true  // special
        );

        if (n_chars > 0) {
            output.append(buf, n_chars);

            // Log progress every 10 tokens
            if (gen_tokens % 10 == 0) {
                auto t_now = std::chrono::steady_clock::now();
                double elapsed_ms = std::chrono::duration<double, std::milli>(t_now - t_gen_start).count();
                LOGI("Generation progress: %d tokens, %.1f tok/s",
                     gen_tokens, gen_tokens / (elapsed_ms / 1000.0));
            }

            // Track JSON brace depth — stop early when the root object closes
            for (int j = 0; j < n_chars; j++) {
                if (buf[j] == '{') {
                    brace_depth++;
                    json_started = true;
                } else if (buf[j] == '}') {
                    brace_depth--;
                    if (json_started && brace_depth <= 0) {
                        LOGI("Early stop: JSON complete at token %d", i);
                        goto generation_done;
                    }
                }
            }
        }

        // Prepare next batch with single token
        llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        int ret = llama_decode(g_context, next_batch);
        if (ret != 0) {
            LOGE("Decode failed at generation step %d", i);
            break;
        }
    }
    generation_done:

    // Reset sampler state for next generation
    llama_sampler_reset(g_sampler);

    auto t_gen_end = std::chrono::steady_clock::now();
    double gen_ms = std::chrono::duration<double, std::milli>(t_gen_end - t_gen_start).count();
    double total_ms = std::chrono::duration<double, std::milli>(t_gen_end - t_start).count();
    LOGI("Generation done: %d tokens in %.1f ms (%.1f tok/s), total: %.1f ms",
         gen_tokens, gen_ms, gen_tokens > 0 ? gen_tokens / (gen_ms / 1000.0) : 0.0, total_ms);
    LOGI("Generated %zu characters", output.size());

    // Strip <think>...</think> block if present
    auto think_start = output.find("<think>");
    if (think_start != std::string::npos) {
        auto think_end = output.find("</think>");
        if (think_end != std::string::npos) {
            output.erase(think_start, think_end + 8 - think_start);
        }
    }

    // Extract JSON from markdown fences (```json ... ```) if present
    auto fence_start = output.find("```json");
    if (fence_start != std::string::npos) {
        auto json_start = output.find('\n', fence_start);
        if (json_start != std::string::npos) {
            json_start++; // skip newline
            auto fence_end = output.find("```", json_start);
            if (fence_end != std::string::npos) {
                output = output.substr(json_start, fence_end - json_start);
            } else {
                output = output.substr(json_start);
            }
        }
    }

    // Trim whitespace
    while (!output.empty() && (output.front() == ' ' || output.front() == '\n' || output.front() == '\r')) {
        output.erase(output.begin());
    }
    while (!output.empty() && (output.back() == ' ' || output.back() == '\n' || output.back() == '\r')) {
        output.pop_back();
    }

    LOGI("[Step 5/5] Cleaned output (%zu chars): %.500s", output.size(), output.c_str());
    LOGI("=== nativeGenerateFromImage END (%.1f ms total) ===", total_ms);
    return env->NewStringUTF(output.c_str());
}

JNIEXPORT void JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeUnloadModel(
    JNIEnv * /* env */, jobject /* thiz */) {

    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_mtmd_ctx) {
        mtmd_free(g_mtmd_ctx);
        g_mtmd_ctx = nullptr;
    }
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    llama_backend_free();
    LOGI("Model unloaded");
}

JNIEXPORT jboolean JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeIsLoaded(
    JNIEnv * /* env */, jobject /* thiz */) {
    return (g_model != nullptr && g_context != nullptr && g_mtmd_ctx != nullptr) ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"

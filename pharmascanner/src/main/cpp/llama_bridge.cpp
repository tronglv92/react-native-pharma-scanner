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

#define LOG_TAG "LlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static llama_model    *g_model   = nullptr;
static llama_context  *g_context = nullptr;
static llama_sampler  *g_sampler = nullptr;

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
    JNIEnv *env, jobject /* thiz */, jstring modelPath, jint nGpuLayers) {

    if (g_model != nullptr) {
        LOGI("Model already loaded, skipping");
        return JNI_TRUE;
    }

    const char *path = env->GetStringUTFChars(modelPath, nullptr);
    if (!path) {
        LOGE("Failed to get model path string");
        return JNI_FALSE;
    }

    LOGI("Loading model from: %s", path);

    // Model params — offload layers to GPU if available
    auto model_params = llama_model_default_params();
    model_params.n_gpu_layers = static_cast<int32_t>(nGpuLayers);

    g_model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(modelPath, path);

    if (!g_model) {
        LOGE("Failed to load model");
        return JNI_FALSE;
    }

    // Context params — optimized for mobile
    // Prompts are ~838 tokens + up to 512 generation, use 2048 for headroom
    auto ctx_params = llama_context_default_params();
    ctx_params.n_ctx   = 2048;
    ctx_params.n_batch = 512;

    // Use available CPU cores (capped at 6 for Snapdragon 8 Gen 3 — uses performance
    // + prime cores without saturating efficiency cores)
    unsigned int hw_threads = std::thread::hardware_concurrency();
    int n_threads = static_cast<int>(std::min(hw_threads, 6u));
    if (n_threads < 1) n_threads = 2;
    ctx_params.n_threads       = n_threads;
    ctx_params.n_threads_batch = n_threads;
    LOGI("Using %d threads (hardware: %u)", n_threads, hw_threads);

    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGE("Failed to create context");
        llama_model_free(g_model);
        g_model = nullptr;
        return JNI_FALSE;
    }

    // Greedy sampling — JSON extraction is deterministic, no need for temperature
    g_sampler = llama_sampler_init_greedy();

    LOGI("Model loaded successfully");
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeGenerate(
    JNIEnv *env, jobject /* thiz */, jstring prompt, jint maxTokens) {

    if (!g_model || !g_context || !g_sampler) {
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

    // Clear KV cache
    llama_memory_t mem = llama_get_memory(g_context);
    if (mem) {
        llama_memory_clear(mem, true);
    }

    // Tokenize prompt
    const llama_vocab *vocab = llama_model_get_vocab(g_model);
    int prompt_len = static_cast<int>(prompt_str.size());
    int max_tokens_estimate = prompt_len + 256;
    std::vector<llama_token> tokens(max_tokens_estimate);

    int n_tokens = llama_tokenize(
        vocab,
        prompt_str.c_str(),
        prompt_len,
        tokens.data(),
        max_tokens_estimate,
        true,   // add_special
        true    // parse_special
    );

    if (n_tokens < 0) {
        // Buffer too small — resize and retry
        tokens.resize(-n_tokens);
        n_tokens = llama_tokenize(
            vocab,
            prompt_str.c_str(),
            prompt_len,
            tokens.data(),
            -n_tokens,
            true,
            true
        );
    }

    if (n_tokens <= 0) {
        LOGE("Tokenization failed: %d", n_tokens);
        return env->NewStringUTF("");
    }

    tokens.resize(n_tokens);
    LOGI("Prompt tokenized: %d tokens", n_tokens);

    // Decode prefill in batches of n_batch (512)
    auto t_prefill_start = std::chrono::steady_clock::now();
    const int n_batch = 512;
    int offset = 0;
    while (offset < n_tokens) {
        int chunk_size = std::min(n_batch, n_tokens - offset);
        llama_batch batch = llama_batch_get_one(tokens.data() + offset, chunk_size);
        int ret = llama_decode(g_context, batch);
        if (ret != 0) {
            LOGE("Prefill decode failed at offset %d: %d", offset, ret);
            return env->NewStringUTF("");
        }
        offset += chunk_size;
    }
    auto t_prefill_end = std::chrono::steady_clock::now();
    double prefill_ms = std::chrono::duration<double, std::milli>(t_prefill_end - t_prefill_start).count();
    LOGI("Prefill done: %d tokens in %.1f ms (%.1f tok/s)",
         n_tokens, prefill_ms, n_tokens / (prefill_ms / 1000.0));

    // Autoregressive generation with early JSON stop
    auto t_gen_start = std::chrono::steady_clock::now();
    std::string output;
    int max_gen = static_cast<int>(maxTokens);
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
    double total_ms = std::chrono::duration<double, std::milli>(t_gen_end - t_prefill_start).count();
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

    LOGI("Cleaned output (%zu chars): %.500s", output.size(), output.c_str());
    return env->NewStringUTF(output.c_str());
}

JNIEXPORT void JNICALL
Java_com_margelo_nitro_PharmaScanner_LlamaCppManager_nativeUnloadModel(
    JNIEnv * /* env */, jobject /* thiz */) {

    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
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
    return (g_model != nullptr && g_context != nullptr) ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"

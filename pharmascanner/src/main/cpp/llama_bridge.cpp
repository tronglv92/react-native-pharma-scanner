#include <jni.h>
#include <string>
#include <vector>
#include <cstdlib>
#include <android/log.h>

#include "llama.h"

#define LOG_TAG "LlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static llama_model    *g_model   = nullptr;
static llama_context  *g_context = nullptr;
static llama_sampler  *g_sampler = nullptr;

extern "C" {

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

    llama_backend_init();

    // Model params — offload layers to GPU if available
    auto model_params = llama_model_default_params();
    model_params.n_gpu_layers = static_cast<int32_t>(nGpuLayers);

    g_model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(modelPath, path);

    if (!g_model) {
        LOGE("Failed to load model");
        llama_backend_free();
        return JNI_FALSE;
    }

    // Context params
    auto ctx_params = llama_context_default_params();
    ctx_params.n_ctx   = 4096;
    ctx_params.n_batch = 512;

    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGE("Failed to create context");
        llama_model_free(g_model);
        g_model = nullptr;
        llama_backend_free();
        return JNI_FALSE;
    }

    // Sampler chain: temperature 0.1 + dist sampling
    auto chain_params = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(chain_params);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.1f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(
        static_cast<uint32_t>(rand())));

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

    // Autoregressive generation
    std::string output;
    int max_gen = static_cast<int>(maxTokens);
    llama_token eos_token = llama_vocab_eos(vocab);

    for (int i = 0; i < max_gen; i++) {
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);

        // Check for end of sequence
        if (new_token == eos_token || llama_vocab_is_eog(vocab, new_token)) {
            break;
        }

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
        }

        // Prepare next batch with single token
        llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        int ret = llama_decode(g_context, next_batch);
        if (ret != 0) {
            LOGE("Decode failed at generation step %d", i);
            break;
        }
    }

    // Reset sampler state for next generation
    llama_sampler_reset(g_sampler);

    LOGI("Generated %zu characters", output.size());
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

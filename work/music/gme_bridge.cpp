// JNI bridge that gives the Android runner the same GameMusicEmu_* calls the
// Windows gme.dll extension provides. GML passes buffer addresses as strings.
#include <jni.h>
#include <android/log.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>
#include <zlib.h>
#include "gme.h"

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "MMMusic", __VA_ARGS__)

namespace {
const int kSampleRate = 44100;
const int kChunkBytes = 1520;  // obj_gme buffer_size: s16 stereo
Music_Emu* g_emu = nullptr;
int g_track = 0;
std::mutex g_lock;

void* parse_address(JNIEnv* env, jstring text)
{
    if (!text) return nullptr;
    const char* raw = env->GetStringUTFChars(text, nullptr);
    const char* digits = raw;
    if (digits[0] == '0' && (digits[1] == 'x' || digits[1] == 'X')) digits += 2;
    uintptr_t value = static_cast<uintptr_t>(strtoull(digits, nullptr, 16));
    env->ReleaseStringUTFChars(text, raw);
    return reinterpret_cast<void*>(value);
}

void free_emu()
{
    if (g_emu) gme_delete(g_emu);
    g_emu = nullptr;
}
}  // namespace

extern "C" {

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nLoad(JNIEnv* env, jclass, jdouble size, jstring address)
{
    std::lock_guard<std::mutex> hold(g_lock);
    free_emu();
    void* data = parse_address(env, address);
    if (!data || size <= 0) return 0;
    gme_err_t error = gme_open_data(data, static_cast<long>(size), &g_emu, kSampleRate);
    if (error) {
        LOG("gme_open_data failed: %s", error);
        g_emu = nullptr;
        return 0;
    }
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nStartTrack(JNIEnv*, jclass, jdouble track)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (!g_emu) return 0;
    g_track = static_cast<int>(track);
    gme_err_t error = gme_start_track(g_emu, g_track);
    if (error) LOG("gme_start_track(%d) failed: %s", g_track, error);
    return error ? 0 : 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nRead(JNIEnv* env, jclass, jstring address)
{
    std::lock_guard<std::mutex> hold(g_lock);
    short* out = static_cast<short*>(parse_address(env, address));
    if (!out) return 0;
    if (!g_emu) {
        memset(out, 0, kChunkBytes);
        return 0;
    }
    gme_play(g_emu, kChunkBytes / 2, out);
    return gme_track_ended(g_emu) ? 0 : 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nFree(JNIEnv*, jclass)
{
    std::lock_guard<std::mutex> hold(g_lock);
    free_emu();
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nNumTracks(JNIEnv*, jclass)
{
    std::lock_guard<std::mutex> hold(g_lock);
    return g_emu ? gme_track_count(g_emu) : 0;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nNumVoices(JNIEnv*, jclass)
{
    std::lock_guard<std::mutex> hold(g_lock);
    return g_emu ? gme_voice_count(g_emu) : 0;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nMuteVoice(JNIEnv*, jclass, jdouble voice, jdouble mute)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (g_emu) gme_mute_voice(g_emu, static_cast<int>(voice), mute != 0);
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nMuteVoices(JNIEnv*, jclass, jdouble mask)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (g_emu) gme_mute_voices(g_emu, static_cast<int>(mask));
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nSetTempo(JNIEnv*, jclass, jdouble tempo)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (g_emu) gme_set_tempo(g_emu, tempo);
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nGetPosition(JNIEnv*, jclass)
{
    std::lock_guard<std::mutex> hold(g_lock);
    return g_emu ? gme_tell(g_emu) : 0;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nSetPosition(JNIEnv*, jclass, jdouble msec)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (g_emu) gme_seek(g_emu, static_cast<int>(msec));
    return 1;
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nTrackLength(JNIEnv*, jclass)
{
    std::lock_guard<std::mutex> hold(g_lock);
    if (!g_emu) return 0;
    gme_info_t* info = nullptr;
    if (gme_track_info(g_emu, &info, g_track) || !info) return 0;
    double length = info->play_length;
    gme_free_info(info);
    return length;
}

JNIEXPORT jstring JNICALL Java_com_company_game_GameMusicEmu_nInfo(JNIEnv* env, jclass, jint field)
{
    std::lock_guard<std::mutex> hold(g_lock);
    const char* value = "";
    gme_info_t* info = nullptr;
    if (g_emu && !gme_track_info(g_emu, &info, g_track) && info) {
        const char* fields[] = {info->song, info->author, info->copyright, info->comment};
        if (field >= 0 && field < 4 && fields[field]) value = fields[field];
    }
    jstring result = env->NewStringUTF(value);
    if (info) gme_free_info(info);
    return result;
}

// ---- zlib: replaces buffer_zlib_x64.dll (gzip-compressed level downloads) ----
static std::vector<unsigned char> g_inflated;

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nInflate(JNIEnv* env, jclass, jstring address, jdouble offset, jdouble length)
{
    unsigned char* src = static_cast<unsigned char*>(parse_address(env, address));
    g_inflated.clear();
    if (!src || length <= 0) return -1;
    z_stream s;
    memset(&s, 0, sizeof(s));
    // 15 + 32: accept zlib or gzip headers automatically.
    if (inflateInit2(&s, 15 + 32) != Z_OK) return -1;
    s.next_in = src + static_cast<size_t>(offset);
    s.avail_in = static_cast<uInt>(length);
    unsigned char chunk[65536];
    int status;
    do {
        s.next_out = chunk;
        s.avail_out = sizeof(chunk);
        status = inflate(&s, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) {
            // Raw deflate fallback (no header).
            inflateEnd(&s);
            if (g_inflated.empty()) {
                memset(&s, 0, sizeof(s));
                if (inflateInit2(&s, -15) != Z_OK) return -1;
                s.next_in = src + static_cast<size_t>(offset);
                s.avail_in = static_cast<uInt>(length);
                do {
                    s.next_out = chunk;
                    s.avail_out = sizeof(chunk);
                    status = inflate(&s, Z_NO_FLUSH);
                    if (status != Z_OK && status != Z_STREAM_END) { inflateEnd(&s); g_inflated.clear(); return -1; }
                    g_inflated.insert(g_inflated.end(), chunk, chunk + (sizeof(chunk) - s.avail_out));
                } while (status != Z_STREAM_END && s.avail_in > 0);
                inflateEnd(&s);
                return static_cast<double>(g_inflated.size());
            }
            LOG("inflate failed: %d", status);
            g_inflated.clear();
            return -1;
        }
        g_inflated.insert(g_inflated.end(), chunk, chunk + (sizeof(chunk) - s.avail_out));
    } while (status != Z_STREAM_END && (s.avail_in > 0 || s.avail_out == 0));
    inflateEnd(&s);
    return static_cast<double>(g_inflated.size());
}

JNIEXPORT jdouble JNICALL Java_com_company_game_GameMusicEmu_nInflateCopy(JNIEnv* env, jclass, jstring address)
{
    unsigned char* dst = static_cast<unsigned char*>(parse_address(env, address));
    if (!dst) return 0;
    if (!g_inflated.empty()) memcpy(dst, g_inflated.data(), g_inflated.size());
    double n = static_cast<double>(g_inflated.size());
    g_inflated.clear();
    g_inflated.shrink_to_fit();
    return n;
}

}  // extern "C"

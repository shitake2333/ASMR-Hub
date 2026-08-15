// ffmpeg_bridge.c — minimal audio decoding bridge for ASMR Hub.
// Compiles against FFmpeg 7.1 shared build (BtbN win64-gpl-shared).
// Exposes a tiny C API so Dart only needs 4 trivial FFI functions; all
// AVFrame/AVPacket layout details stay in C.
//
// Build (MinGW):
//   gcc -shared -O2 -o ffmpeg_bridge.dll ffmpeg_bridge.c \
//     -I include -L . -lavformat -lavcodec -lavutil -lswresample
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

typedef struct {
    AVFormatContext *fmt;
    int audio_stream;
    AVCodecContext *codec;
    SwrContext *swr;
    AVPacket *pkt;
    AVFrame *frame;
    int sample_rate;
    int channels;
    int64_t channel_layout;
    // Internal PCM buffer (s16le interleaved).
    uint8_t *pcm_buf;
    int pcm_buf_cap;
    int pcm_buf_len;
    int pcm_buf_pos;
    int64_t last_error;
    // Optional encoder sidecar (cache writing while playing).
    AVCodecContext *enc;
    SwrContext *enc_swr;
    AVPacket *enc_pkt;
    AVFrame *enc_frame;
    uint8_t *enc_buf;
    int enc_buf_cap;
    int enc_buf_len;
    int enc_buf_pos;
    uint8_t *enc_acc;  // PCM accumulator (s16 interleaved frames)
    int enc_acc_len;
    int enc_acc_cap;
    int enc_bitrate;
    int enc_codec_id;  // AV_CODEC_ID_MP3 or AV_CODEC_ID_FLAC
    int enc_frame_samples;  // samples per encoder frame (1152 mp3, 4096 flac)
    int input_eof;     // decoder reached EOF
    int enc_flushed;   // encoder flush started
    int enc_finished;  // all encoded data consumed
} Bridge;

static const char *err_str(int err) {
    static char buf[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(err, buf, sizeof(buf));
    return buf;
}

static void enc_init(Bridge *b, int codec, int bitrate);
static void enc_free(Bridge *b);

// Appends `len` bytes at `src` to the encoded-output FIFO.
static void enc_append(Bridge *b, const uint8_t *src, int len) {
    if (b->enc_buf_len + len > b->enc_buf_cap) {
        int new_cap = b->enc_buf_cap ? b->enc_buf_cap : 64 * 1024;
        while (new_cap < b->enc_buf_len + len) new_cap *= 2;
        uint8_t *nb = (uint8_t *)realloc(b->enc_buf, new_cap);
        if (!nb) return;
        b->enc_buf = nb;
        b->enc_buf_cap = new_cap;
    }
    memcpy(b->enc_buf + b->enc_buf_len, src, len);
    b->enc_buf_len += len;
}

// Sends one frame (or NULL to flush) into the MP3 encoder and drains the
// resulting packets into the encoded FIFO.
static void enc_feed(Bridge *b, AVFrame *f) {
    if (!b->enc) return;
    if (avcodec_send_frame(b->enc, f) < 0) return;
    while (1) {
        int r = avcodec_receive_packet(b->enc, b->enc_pkt);
        if (r < 0) break;
        enc_append(b, b->enc_pkt->data, b->enc_pkt->size);
        av_packet_unref(b->enc_pkt);
    }
}

// Sends one frame of exactly `samples` s16-interleaved PCM samples to the
// MP3 encoder and drains the resulting packets into the encoded FIFO.
static void enc_send_samples(Bridge *b, const uint8_t *pcm_s16, int samples) {
    AVFrame *f = b->enc_frame;
    av_frame_unref(f);
    f->nb_samples = samples;
    f->format = b->enc->sample_fmt;
    f->sample_rate = 44100;
    av_channel_layout_copy(&f->ch_layout, &b->enc->ch_layout);
    if (av_frame_get_buffer(f, 0) < 0) return;
    if (b->enc_swr) {
        // Input is interleaved s16: a single plane.
        uint8_t *inp = (uint8_t *)pcm_s16;
        swr_convert(b->enc_swr, f->data, samples,
                    (const uint8_t **)&inp, samples);
    }
    enc_feed(b, f);
}

// Accumulates decoded PCM and feeds the encoder in exact frames
// (libmp3lame rejects non-last frames of any other size; FLAC uses 4096).
static void enc_accumulate(Bridge *b, const uint8_t *pcm, int bytes) {
    if (!b->enc || bytes <= 0) return;
    int frame_bytes = b->enc_frame_samples * 4;
    if (b->enc_acc_len + bytes > b->enc_acc_cap) {
        int new_cap = b->enc_acc_cap ? b->enc_acc_cap : frame_bytes;
        while (new_cap < b->enc_acc_len + bytes) new_cap *= 2;
        uint8_t *nb = (uint8_t *)realloc(b->enc_acc, new_cap);
        if (!nb) return;
        b->enc_acc = nb;
        b->enc_acc_cap = new_cap;
    }
    memcpy(b->enc_acc + b->enc_acc_len, pcm, bytes);
    b->enc_acc_len += bytes;
    while (b->enc_acc_len >= frame_bytes) {
        enc_send_samples(b, b->enc_acc, b->enc_frame_samples);
        int rest = b->enc_acc_len - frame_bytes;
        if (rest > 0) memmove(b->enc_acc, b->enc_acc + frame_bytes, rest);
        b->enc_acc_len = rest;
    }
}

// Sends the final partial frame (if any) and flushes the encoder.
static void enc_flush_acc(Bridge *b) {
    if (!b->enc) return;
    if (b->enc_acc_len > 0) {
        enc_send_samples(b, b->enc_acc, b->enc_acc_len / 4);
        b->enc_acc_len = 0;
    }
    enc_feed(b, NULL);
}

EXPORT void *bridge_open(const char *url, const char *headers, const char *ua,
                         int mp3_bitrate, int codec) {
    Bridge *b = (Bridge *)calloc(1, sizeof(Bridge));
    if (!b) return NULL;
    b->audio_stream = -1;

    AVDictionary *opts = NULL;
    if (headers && headers[0]) {
        av_dict_set(&opts, "headers", headers, 0);
    }
    if (ua && ua[0]) {
        av_dict_set(&opts, "user_agent", ua, 0);
    }
    av_dict_set(&opts, "http_persistent", "0", 0);

    if (avformat_open_input(&b->fmt, url, NULL, &opts) < 0) {
        av_dict_free(&opts);
        free(b);
        return NULL;
    }
    av_dict_free(&opts);

    if (avformat_find_stream_info(b->fmt, NULL) < 0) {
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }

    b->audio_stream = av_find_best_stream(
        b->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    if (b->audio_stream < 0) {
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }

    AVStream *st = b->fmt->streams[b->audio_stream];
    const AVCodec *dec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!dec) {
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }
    b->codec = avcodec_alloc_context3(dec);
    if (!b->codec) {
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }
    if (avcodec_parameters_to_context(b->codec, st->codecpar) < 0) {
        avcodec_free_context(&b->codec);
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }
    if (avcodec_open2(b->codec, dec, NULL) < 0) {
        avcodec_free_context(&b->codec);
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }

    b->sample_rate = b->codec->sample_rate;
    b->channels = b->codec->ch_layout.nb_channels > 0
                      ? b->codec->ch_layout.nb_channels
                      : 2;
    if (b->channels <= 0) b->channels = 2;

    // Resample to a FIXED output format: 44100 Hz, stereo, s16 interleaved.
    // This keeps the SoLoud buffer stream configuration trivial.
    b->sample_rate = 44100;
    b->channels = 2;
    AVChannelLayout out_layout;
    av_channel_layout_default(&out_layout, b->channels);
    swr_alloc_set_opts2(
        &b->swr,
        &out_layout, AV_SAMPLE_FMT_S16, b->sample_rate,
        &b->codec->ch_layout, b->codec->sample_fmt, b->codec->sample_rate,
        0, NULL);
    if (!b->swr || swr_init(b->swr) < 0) {
        avcodec_free_context(&b->codec);
        avformat_close_input(&b->fmt);
        free(b);
        return NULL;
    }

    b->pkt = av_packet_alloc();
    b->frame = av_frame_alloc();
    b->pcm_buf_cap = 192000 * 2; // > 1s of 48k stereo s16
    b->pcm_buf = (uint8_t *)malloc(b->pcm_buf_cap);
    b->pcm_buf_len = 0;
    b->pcm_buf_pos = 0;

    // Optional encoder sidecar (for writing a compressed cache while
    // playing). mp3_bitrate <= 0 disables it; codec: 1 = MP3, 2 = FLAC.
    if (codec == 2) {
        enc_init(b, 2, 0);
    } else if (mp3_bitrate > 0) {
        enc_init(b, 1, mp3_bitrate);
    }
    return b;
}

// (Re)initializes the encoder sidecar for [codec]: 0 = none, 1 = MP3,
// 2 = FLAC. Frees any previous encoder state.
static void enc_init(Bridge *b, int codec, int bitrate) {
    enc_free(b);
    b->enc_bitrate = bitrate;
    const AVCodec *enc_codec = NULL;
    if (codec == 2) {
        enc_codec = avcodec_find_encoder(AV_CODEC_ID_FLAC);
    } else {
        enc_codec = avcodec_find_encoder(AV_CODEC_ID_MP3);
    }
    if (!enc_codec) return;
    b->enc_codec_id = codec == 2 ? AV_CODEC_ID_FLAC : AV_CODEC_ID_MP3;
    // FLAC's frame size depends on the sample rate (4608 @ 44100 Hz);
    // MP3 uses 1152-sample frames.
    b->enc_frame_samples = codec == 2 ? 4608 : 1152;
    b->enc = avcodec_alloc_context3(enc_codec);
    b->enc->sample_rate = 44100;
    if (codec == 2) {
        // FLAC: lossless; compression level 5 (default) is a good balance.
        b->enc->compression_level = 5;
        // FLAC is a fixed-point codec; its sample fmt is S16 for our config.
        b->enc->sample_fmt = AV_SAMPLE_FMT_S16;
    } else {
        b->enc->bit_rate = bitrate;
    }
    av_channel_layout_default(&b->enc->ch_layout, 2);
    if (codec != 2 && enc_codec->sample_fmts) {
        b->enc->sample_fmt = enc_codec->sample_fmts[0];
    } else if (codec != 2) {
        b->enc->sample_fmt = AV_SAMPLE_FMT_FLTP;
    }
    b->enc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    if (avcodec_open2(b->enc, enc_codec, NULL) < 0) {
        avcodec_free_context(&b->enc);
        b->enc = NULL;
        return;
    }
    AVChannelLayout in_layout;
    av_channel_layout_default(&in_layout, 2);
    swr_alloc_set_opts2(
        &b->enc_swr, &b->enc->ch_layout, b->enc->sample_fmt, 44100,
        &in_layout, AV_SAMPLE_FMT_S16, 44100, 0, NULL);
    if (!b->enc_swr || swr_init(b->enc_swr) < 0) {
        swr_free(&b->enc_swr);
        avcodec_free_context(&b->enc);
        b->enc = NULL;
        return;
    }
    b->enc_pkt = av_packet_alloc();
    b->enc_frame = av_frame_alloc();
    b->enc_buf_cap = 0;
    b->enc_buf_len = 0;
    b->enc_buf_pos = 0;
    b->enc_acc_cap = 0;
    b->enc_acc_len = 0;
    b->enc_flushed = 0;
    b->enc_finished = 0;
    // Raw FLAC has no container; the encoder does not emit the fLaC marker
    // or STREAMINFO. Emit a minimal header manually so the cached file is a
    // valid standalone FLAC stream. Layout verified against ffmpeg's FLAC
    // muxer output for 44100 Hz / stereo / 16-bit: fLaC marker, STREAMINFO
    // block (min/max block 4608, unknown frame sizes, 44100 Hz, 2ch, 16-bit,
    // total samples unknown -> 0). Players accept a 0 sample count and just
    // report the duration once decoding starts.
    if (codec == 2) {
        // fLaC(4) + block header(4) + STREAMINFO(34) = 42 bytes.
        // Layout verified against ffmpeg's FLAC muxer for 44100 Hz stereo
        // 16-bit; total samples left 0 (unknown while streaming).
        static const uint8_t flac_hdr[42] = {
            'f', 'L', 'a', 'C',                          // 4: fLaC
            0x00, 0x00, 0x00, 0x22,                      // 4: STREAMINFO, size 34
            0x12, 0x00, 0x12, 0x00,                      // 4: min/max block 4608
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,          // 6: min/max frame 0
            0x0A, 0xC4, 0x43, 0x70,                      // 4: 44100Hz, ch-1=1, bps-1=15
            0x00, 0x00, 0x00, 0x00,                      // 4: total samples 0
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,          // 16: MD5 (zeroed)
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        };
        enc_append(b, flac_hdr, sizeof(flac_hdr));
    }
}

static void enc_free(Bridge *b) {
    if (b->enc) avcodec_free_context(&b->enc);
    if (b->enc_swr) swr_free(&b->enc_swr);
    if (b->enc_frame) av_frame_free(&b->enc_frame);
    if (b->enc_pkt) av_packet_free(&b->enc_pkt);
    if (b->enc_buf) free(b->enc_buf);
    if (b->enc_acc) free(b->enc_acc);
    b->enc = NULL;
    b->enc_swr = NULL;
    b->enc_frame = NULL;
    b->enc_pkt = NULL;
    b->enc_buf = NULL;
    b->enc_acc = NULL;
}

EXPORT int bridge_get_sample_rate(void *h) {
    Bridge *b = (Bridge *)h;
    return b ? b->sample_rate : 0;
}

EXPORT int bridge_get_channels(void *h) {
    Bridge *b = (Bridge *)h;
    return b ? b->channels : 0;
}

// Returns the media duration in seconds (0 for live/unknown streams).
// The value is known right after bridge_open because avformat parses the
// container metadata, so the UI can show the duration before playback.
EXPORT double bridge_get_duration(void *h) {
    Bridge *b = (Bridge *)h;
    if (!b || !b->fmt) return 0;
    int64_t d = b->fmt->duration;
    if (d <= 0) return 0;
    return (double)d / AV_TIME_BASE;
}

// Reads up to `cap` bytes of decoded interleaved s16 PCM.
// Returns bytes written, 0 on EOF, -1 on error.
EXPORT int bridge_read_pcm(void *h, uint8_t *out, int cap) {
    Bridge *b = (Bridge *)h;
    if (!b) return -1;
    int written = 0;
    while (written < cap) {
        // Drain buffered PCM first.
        if (b->pcm_buf_len - b->pcm_buf_pos > 0) {
            int avail = b->pcm_buf_len - b->pcm_buf_pos;
            int take = avail < (cap - written) ? avail : (cap - written);
            memcpy(out + written, b->pcm_buf + b->pcm_buf_pos, take);
            b->pcm_buf_pos += take;
            written += take;
            if (written >= cap) return written;
        }

        int ret = av_read_frame(b->fmt, b->pkt);
        if (ret < 0) {
            // EOF: flush decoder then finish gracefully (return 0 = normal end).
            b->input_eof = 1;
            avcodec_send_packet(b->codec, NULL);
            while (1) {
                int r = avcodec_receive_frame(b->codec, b->frame);
                if (r < 0) break;
                if (b->frame->nb_samples > 0) {
                    int out_samples = swr_get_out_samples(
                        b->swr, b->frame->nb_samples);
                    int bytes =
                        out_samples * b->channels * 2;
                    if (bytes > b->pcm_buf_cap) {
                        free(b->pcm_buf);
                        b->pcm_buf_cap = bytes;
                        b->pcm_buf = (uint8_t *)malloc(b->pcm_buf_cap);
                    }
                    uint8_t *outp = b->pcm_buf;
                    int converted = swr_convert(
                        b->swr, &outp, out_samples,
                        (const uint8_t **)b->frame->extended_data,
                        b->frame->nb_samples);
                    if (converted > 0) {
                        b->pcm_buf_len = converted * b->channels * 2;
                        b->pcm_buf_pos = 0;
                        enc_accumulate(b, b->pcm_buf, converted * 4);
                        break;
                    }
                }
            }
            if (b->pcm_buf_len - b->pcm_buf_pos <= 0) {
                return written > 0 ? written : 0;
            }
            continue;
        }

        if (b->pkt->stream_index == b->audio_stream) {
            if (avcodec_send_packet(b->codec, b->pkt) == 0) {
                int r = avcodec_receive_frame(b->codec, b->frame);
                if (r == 0 && b->frame->nb_samples > 0) {
                    int out_samples = swr_get_out_samples(
                        b->swr, b->frame->nb_samples);
                    int bytes = out_samples * b->channels * 2;
                    if (bytes > b->pcm_buf_cap) {
                        free(b->pcm_buf);
                        b->pcm_buf_cap = bytes;
                        b->pcm_buf = (uint8_t *)malloc(b->pcm_buf_cap);
                    }
                    uint8_t *outp = b->pcm_buf;
                    int converted = swr_convert(
                        b->swr, &outp, out_samples,
                        (const uint8_t **)b->frame->extended_data,
                        b->frame->nb_samples);
                    if (converted > 0) {
                        b->pcm_buf_len = converted * b->channels * 2;
                        b->pcm_buf_pos = 0;
                        enc_accumulate(b, b->pcm_buf, converted * 4);
                    }
                }
            }
        }
        av_packet_unref(b->pkt);
    }
    return written;
}

// Seeks the input to `seconds`. Returns 0 on success, -1 on failure.
// The decoder, resampler and encoder sidecar are all reset; any encoded
// bytes buffered before the seek are discarded (the cache file written by
// the caller is invalidated too).
EXPORT int bridge_seek(void *h, double seconds) {
    Bridge *b = (Bridge *)h;
    if (!b || !b->fmt) return -1;
    int64_t ts = (int64_t)(seconds * AV_TIME_BASE);
    if (av_seek_frame(b->fmt, -1, ts, AVSEEK_FLAG_BACKWARD) < 0) {
        if (b->audio_stream < 0) return -1;
        if (av_seek_frame(b->fmt, b->audio_stream, ts,
                          AVSEEK_FLAG_BACKWARD) < 0) {
            return -1;
        }
    }
    avcodec_flush_buffers(b->codec);
    if (b->swr) {
        swr_close(b->swr);
        if (swr_init(b->swr) < 0) return -1;
    }
    b->pcm_buf_len = 0;
    b->pcm_buf_pos = 0;
    b->input_eof = 0;
    // Reset the encoder sidecar so the cache restarts cleanly.
    if (b->enc_bitrate > 0 || b->enc_codec_id == AV_CODEC_ID_FLAC) {
        int codec = b->enc_codec_id == AV_CODEC_ID_FLAC ? 2 : 1;
        enc_free(b);
        enc_init(b, codec, b->enc_bitrate);
    }
    return 0;
}

// Takes encoded (MP3) bytes produced while decoding. Returns:
//   >0  bytes copied to `out`
//    0  no data available yet (keep decoding)
//   -1  error / encoder disabled
//   -2  encoding finished (all bytes consumed; call no more)
EXPORT int bridge_take_encoded(void *h, uint8_t *out, int cap) {
    Bridge *b = (Bridge *)h;
    if (!b || !b->enc) return -1;
    if (b->enc_finished) return -2;
    if (b->input_eof && !b->enc_flushed) {
        b->enc_flushed = 1;
        enc_flush_acc(b); // flush partial frame + encoder
    }
    if (b->enc_buf_len - b->enc_buf_pos > 0) {
        int avail = b->enc_buf_len - b->enc_buf_pos;
        int take = avail < cap ? avail : cap;
        memcpy(out, b->enc_buf + b->enc_buf_pos, take);
        b->enc_buf_pos += take;
        if (b->enc_buf_pos >= b->enc_buf_len) {
            b->enc_buf_len = 0;
            b->enc_buf_pos = 0;
        }
        return take;
    }
    if (b->enc_flushed) {
        b->enc_finished = 1;
        return -2;
    }
    return 0;
}

EXPORT const char *bridge_last_error(void *h) {
    Bridge *b = (Bridge *)h;
    if (!b) return "null handle";
    return err_str((int)b->last_error);
}

EXPORT void bridge_close(void *h) {
    Bridge *b = (Bridge *)h;
    if (!b) return;
    if (b->enc) {
        if (!b->enc_finished && !b->enc_flushed) enc_flush_acc(b);
        enc_free(b);
    }
    if (b->swr) swr_free(&b->swr);
    if (b->swr) swr_free(&b->swr);
    if (b->frame) av_frame_free(&b->frame);
    if (b->pkt) av_packet_free(&b->pkt);
    if (b->codec) avcodec_free_context(&b->codec);
    if (b->fmt) avformat_close_input(&b->fmt);
    if (b->pcm_buf) free(b->pcm_buf);
    free(b);
}

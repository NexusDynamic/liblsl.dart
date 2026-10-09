// The thread behind LSLInlet.sampleStream() and chunkStream().
//
// liblsl has no "a sample arrived" hook: the only way to learn of one without
// polling is to be inside lsl_pull_* when it is queued. Something therefore
// has to block there for every inlet that is listened to, and it cannot be a
// Dart isolate. The Dart VM bounds how many isolates of a group are entered
// at once, an isolate blocked in a native call still counts, and past that
// bound (16 on the machine this was measured on) every other isolate waits
// for a listener to come out of its pull before it can handle an event.
//
// So the waiting is done here, on a plain thread the VM knows nothing about.
// It reads the receive clock the moment the pull returns, packs what it got
// into one heap block and hands the block to a Dart callback made with
// NativeCallable.listener, which may be called from any thread and runs on
// its isolate's event loop when that isolate is next free.
//
// - One thread per listener, parked inside liblsl while its stream is quiet.
// - A block belongs to Dart once the callback has it: lsl_dart_block_free().
// - The thread's last call is always a block of kind kEnded or kFailed, and
//   it calls nothing after it. Dart then joins it with lsl_dart_listener_destroy().
// - If the listening isolate dies first, a NativeFinalizer calls
//   lsl_dart_listener_abandon(): calling its callback after that would crash.
// - The four control words are shared with Dart and each has one writer.
//
// See lib/src/lsl/sample_listener.dart for the other half.

#include <lsl_c.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

extern "C" {

// Layout mirrored by LslDartBlock in lib/src/ffi/bindings_ex.dart.
typedef struct lsl_dart_block {
	// kData, kEnded or kFailed.
	int32_t kind;
	// kEnded: the liblsl error code that ended the listener, or 0.
	int32_t error;
	// Samples in this block.
	int32_t samples;
	// How many of them, from the first, were in the inlet when clock was read.
	int32_t ready;
	// lsl_local_clock() as the pull that returned the first sample came back.
	double clock;
	// One per sample.
	double *timestamps;
	// samples * channels values of the stream's format; for a string stream,
	// that many strings one after another, each ending in a zero byte.
	void *data;
	// Bytes at data.
	uint64_t data_bytes;
	// kEnded with an error: what liblsl had to say about it, or null.
	// kFailed: why.
	char *message;
} lsl_dart_block;

typedef void (*lsl_dart_block_callback)(lsl_dart_block *block);

typedef struct lsl_dart_listener lsl_dart_listener;

} // extern "C"

namespace {

constexpr int32_t kData = 0;
// The thread's last block, after a stop or a pull that liblsl failed.
constexpr int32_t kEnded = 1;
// The thread's last block, when it is leaving for a reason of its own.
constexpr int32_t kFailed = 2;

// The control words. Dart reads and writes them as plain uint32.
constexpr int kStop = 0;	 // nonzero: leave. Written by Dart.
constexpr int kPaused = 1;	 // nonzero: do not pull. Written by Dart.
constexpr int kSent = 2;	 // samples handed over, modulo 2^32.
constexpr int kReceived = 3; // samples that reached the stream. Written by Dart.
constexpr int kControlWords = 4;

size_t element_size(int32_t format) {
	switch (format) {
	case cft_int8: return 1;
	case cft_int16: return 2;
	case cft_float32:
	case cft_int32: return 4;
	case cft_double64:
	case cft_int64: return 8;
	default: return sizeof(char *);
	}
}

// Blocks are one allocation: header, timestamps, data, then the message.
lsl_dart_block *new_block(int32_t kind, int32_t samples, size_t data_bytes, size_t message_bytes) {
	const size_t times_bytes = sizeof(double) * static_cast<size_t>(samples);
	// The data starts on an 8-byte boundary: the header and the doubles are
	// both multiples of eight.
	const size_t total = sizeof(lsl_dart_block) + times_bytes + data_bytes + message_bytes;
	auto *raw = static_cast<char *>(std::malloc(total));
	if (!raw) return nullptr;
	auto *block = reinterpret_cast<lsl_dart_block *>(raw);
	block->kind = kind;
	block->error = 0;
	block->samples = samples;
	block->ready = samples;
	block->clock = 0;
	block->timestamps = reinterpret_cast<double *>(raw + sizeof(lsl_dart_block));
	block->data = raw + sizeof(lsl_dart_block) + times_bytes;
	block->data_bytes = data_bytes;
	block->message = message_bytes ? raw + sizeof(lsl_dart_block) + times_bytes + data_bytes : nullptr;
	return block;
}

} // namespace

struct lsl_dart_listener {
	lsl_inlet inlet;
	int32_t format;
	int32_t channels;
	int32_t max_samples;
	double coalesce;
	double wake_interval;
	uint32_t max_backlog;
	// Blocks after which the thread fails, for tests; zero for never.
	int32_t fail_after;
	lsl_dart_block_callback callback;
	std::atomic<uint32_t> control[kControlWords];
	std::thread thread;
	// Held around every call of the callback, and to set `abandoned`: once
	// lsl_dart_listener_abandon() has returned, the callback is not called.
	std::mutex handoff;
	// The isolate that was listening is gone, and the callback with it.
	bool abandoned = false;

	// Hands `block` to Dart, or frees it if nobody is there to take it.
	void deliver(lsl_dart_block *block) {
		std::lock_guard<std::mutex> lock(handoff);
		if (abandoned)
			std::free(block);
		else
			callback(block);
	}

	// Whether to pull again; false when it is to leave. With a limit it first
	// waits while Dart is that many samples behind or has paused, so what
	// arrives meanwhile stays in the inlet's buffer, which liblsl bounds.
	bool may_pull() {
		if (control[kStop].load(std::memory_order_relaxed)) return false;
		if (max_backlog == 0) return true;
		int spins = 0;
		while (control[kPaused].load(std::memory_order_relaxed) ||
			   static_cast<uint32_t>(control[kSent].load(std::memory_order_relaxed) -
									 control[kReceived].load(std::memory_order_relaxed)) >=
				   max_backlog) {
			if (control[kStop].load(std::memory_order_relaxed)) return false;
			// Most such waits are over in microseconds.
			if (++spins > 20000) std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
		return true;
	}

	unsigned long pull(void *data, double *times, int32_t samples, double timeout, int32_t *ec) {
		const auto elements = static_cast<unsigned long>(samples) * static_cast<unsigned long>(channels);
		const auto stamps = static_cast<unsigned long>(samples);
		switch (format) {
		case cft_float32:
			return lsl_pull_chunk_f(inlet, static_cast<float *>(data), times, elements, stamps, timeout, ec);
		case cft_double64:
			return lsl_pull_chunk_d(inlet, static_cast<double *>(data), times, elements, stamps, timeout, ec);
		case cft_int64:
			return lsl_pull_chunk_l(inlet, static_cast<int64_t *>(data), times, elements, stamps, timeout, ec);
		case cft_int32:
			return lsl_pull_chunk_i(inlet, static_cast<int32_t *>(data), times, elements, stamps, timeout, ec);
		case cft_int16:
			return lsl_pull_chunk_s(inlet, static_cast<int16_t *>(data), times, elements, stamps, timeout, ec);
		case cft_int8:
			return lsl_pull_chunk_c(inlet, static_cast<char *>(data), times, elements, stamps, timeout, ec);
		case cft_string:
			return lsl_pull_chunk_str(inlet, static_cast<char **>(data), times, elements, stamps, timeout, ec);
		default:
			*ec = lsl_argument_error;
			return 0;
		}
	}

	// The last thing this thread tells Dart.
	void end(int32_t error, const std::string &message, int32_t kind = kEnded) {
		auto *block = new_block(kind, 0, 0, message.empty() ? 0 : message.size() + 1);
		// Without memory there is nothing to say it with; Dart is left with a
		// listener that never ends, which it can still stop and destroy.
		if (!block) return;
		block->error = error;
		if (block->message) std::memcpy(block->message, message.c_str(), message.size() + 1);
		deliver(block);
	}

	void run() {
		const size_t size = element_size(format);
		const bool strings = format == cft_string;
		const auto max = static_cast<size_t>(max_samples);
		const auto width = static_cast<size_t>(channels);
		// Where a pull writes; copied out into the block that is handed over.
		std::vector<char> data(max * width * size);
		std::vector<double> times(max);
		int32_t delivered = 0;

		while (may_pull()) {
			// One sample, so the call returns the moment there is one rather
			// than waiting to fill a chunk.
			int32_t ec = 0;
			auto elements = pull(data.data(), times.data(), 1, wake_interval, &ec);
			if (elements == 0) {
				// Anything liblsl reports but a timeout ends the listener.
				if (ec == 0 || ec == lsl_timeout_error) continue;
				// Read here: liblsl keeps the message per thread.
				const char *why = lsl_last_error();
				end(ec, why ? why : "");
				return;
			}
			// Read before anything else: this is the receive time.
			const double clock = lsl_local_clock();
			int32_t failure = 0;
			size_t samples = elements / width;
			if (samples < max) {
				// What came with it: these were in the inlet as the clock was read.
				ec = 0;
				samples += pull(data.data() + samples * width * size, times.data() + samples,
								static_cast<int32_t>(max - samples), 0, &ec) /
						   width;
				if (ec != 0 && ec != lsl_timeout_error) failure = ec;
			}
			const size_t ready = samples;
			if (failure == 0 && coalesce > 0 && samples < max) {
				// And what arrives in the time allowed for more.
				ec = 0;
				samples += pull(data.data() + samples * width * size, times.data() + samples,
								static_cast<int32_t>(max - samples), coalesce, &ec) /
						   width;
				if (ec != 0 && ec != lsl_timeout_error) failure = ec;
			}
			std::string why;
			if (failure != 0) {
				const char *text = lsl_last_error();
				if (text) why = text;
			}

			size_t bytes = samples * width * size;
			auto **texts = reinterpret_cast<char **>(data.data());
			if (strings) {
				bytes = 0;
				for (size_t i = 0; i < samples * width; i++)
					bytes += (texts[i] ? std::strlen(texts[i]) : 0) + 1;
			}
			auto *block = new_block(kData, static_cast<int32_t>(samples), bytes, 0);
			if (block) {
				block->ready = static_cast<int32_t>(ready);
				block->clock = clock;
				std::memcpy(block->timestamps, times.data(), samples * sizeof(double));
				if (!strings) std::memcpy(block->data, data.data(), bytes);
			}
			if (strings) {
				auto *out = block ? static_cast<char *>(block->data) : nullptr;
				for (size_t i = 0; i < samples * width; i++) {
					const size_t length = texts[i] ? std::strlen(texts[i]) : 0;
					if (out) {
						if (length) std::memcpy(out, texts[i], length);
						out[length] = 0;
						out += length + 1;
					}
					// liblsl allocated each one for us.
					if (texts[i]) lsl_destroy_string(texts[i]);
					texts[i] = nullptr;
				}
			}
			if (!block) {
				end(0, "Out of memory for a sample block", kFailed);
				return;
			}
			// Counted before it is handed over, so Dart never counts ahead.
			control[kSent].fetch_add(static_cast<uint32_t>(samples), std::memory_order_relaxed);
			deliver(block);
			if (failure != 0) {
				end(failure, why);
				return;
			}
			if (++delivered == fail_after) {
				end(0, "debugFailAfter: failing after " + std::to_string(delivered) + " blocks", kFailed);
				return;
			}
		}
		end(0, "");
	}
};

extern "C" {

/// Starts a thread that pulls from `inlet` and hands what arrives to
/// `callback`, which must be callable from any thread.
///
/// `format` and `channels` are the stream's. A block holds up to
/// `max_samples` samples: the one the thread was woken by and whatever else
/// was waiting, plus what arrives within `coalesce` seconds if that is above
/// zero. `wake_interval` (seconds, above zero) bounds how long stopping takes.
/// `max_backlog` above zero holds the thread back while Dart is that many
/// samples behind or has paused. `fail_after` above zero is for tests: the
/// thread fails after that many blocks.
///
/// Returns null if the arguments are unusable or no thread could be started.
LIBLSL_C_API lsl_dart_listener *lsl_dart_listener_start(lsl_inlet inlet, int32_t format,
	int32_t channels, int32_t max_samples, double coalesce, double wake_interval,
	uint32_t max_backlog, int32_t fail_after, lsl_dart_block_callback callback) {
	if (!inlet || !callback || channels < 1 || max_samples < 1) return nullptr;
	// liblsl does not wait on a timeout of zero or less: the thread would spin.
	if (!std::isfinite(wake_interval) || wake_interval <= 0) return nullptr;
	switch (format) {
	case cft_float32:
	case cft_double64:
	case cft_string:
	case cft_int32:
	case cft_int16:
	case cft_int8:
	case cft_int64: break;
	default: return nullptr;
	}
	lsl_dart_listener *listener = nullptr;
	try {
		listener = new lsl_dart_listener();
		listener->inlet = inlet;
		listener->format = format;
		listener->channels = channels;
		listener->max_samples = max_samples;
		listener->coalesce = coalesce;
		listener->wake_interval = wake_interval;
		listener->max_backlog = max_backlog;
		listener->fail_after = fail_after;
		listener->callback = callback;
		for (auto &word : listener->control) word.store(0);
		listener->thread = std::thread([listener] {
			try {
				listener->run();
			} catch (const std::exception &e) {
				listener->end(0, e.what(), kFailed);
			} catch (...) { listener->end(0, "Sample listener thread failed", kFailed); }
		});
		return listener;
	} catch (...) {
		delete listener;
		return nullptr;
	}
}

/// The listener's four control words: stop, paused, sent, received.
LIBLSL_C_API uint32_t *lsl_dart_listener_control(lsl_dart_listener *listener) {
	// std::atomic<uint32_t> is a uint32_t on every platform this builds for.
	static_assert(sizeof(std::atomic<uint32_t>) == sizeof(uint32_t), "control words are not plain");
	return reinterpret_cast<uint32_t *>(listener->control);
}

/// Asks the thread to leave if it has not, waits for it and frees the
/// listener. Blocks for up to the wake interval unless the thread has
/// already sent its last block.
LIBLSL_C_API void lsl_dart_listener_destroy(lsl_dart_listener *listener) {
	if (!listener) return;
	listener->control[kStop].store(1);
	if (listener->thread.joinable()) listener->thread.join();
	delete listener;
}

/// For a listener whose isolate is gone without having destroyed it: stops
/// the thread and makes sure the callback is not called again. Does not wait
/// for the thread, which frees the listener as it leaves.
///
/// The inlet is not touched: it is not the listener's, and may have been
/// handed to another isolate. Whoever is left destroys it, once the thread
/// has had a wake interval to leave its pull.
///
/// The signature is a Dart NativeFinalizer's.
LIBLSL_C_API void lsl_dart_listener_abandon(void *token) {
	auto *listener = static_cast<lsl_dart_listener *>(token);
	if (!listener) return;
	std::thread thread;
	{
		std::lock_guard<std::mutex> lock(listener->handoff);
		listener->abandoned = true;
		listener->control[kStop].store(1);
		thread = std::move(listener->thread);
	}
	// It may be inside a pull for the rest of its wake interval, and whoever
	// is tearing the isolate down should not wait for that.
	std::thread([listener, pulling = std::move(thread)]() mutable {
		if (pulling.joinable()) pulling.join();
		delete listener;
	}).detach();
}

/// Frees a block the callback was given.
LIBLSL_C_API void lsl_dart_block_free(lsl_dart_block *block) { std::free(block); }

} // extern "C"

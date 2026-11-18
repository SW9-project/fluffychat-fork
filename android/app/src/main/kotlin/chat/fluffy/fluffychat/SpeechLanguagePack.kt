// SPDX-FileCopyrightText: 2026 SW9-project contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

package chat.fluffy.fluffychat

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Checks and downloads the language pack of the on-device speech recognizer
 * for Assist voice input (docs/voice-input.md). Android 13 (API 33) and later;
 * below that `check` answers "unknown".
 *
 * A download is a request to the system's on-device recognition service, which
 * fetches the pack itself. No audio or text is sent.
 */
object SpeechLanguagePack {
    private const val CHANNEL = "chat.fluffy.fluffychat/speech_language_pack"
    private const val TAG = "SpeechLanguagePack"

    /** How long `check` waits for the recognition service to answer. */
    private const val CHECK_TIMEOUT_MS = 5000L

    /** How long a recognizer is kept for a download request without a listener. */
    private const val REQUEST_DESTROY_DELAY_MS = 5000L

    private val handler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val locale = call.argument<String>("locale")?.replace('_', '-')
            if (locale == null) {
                result.error("missingLocale", "locale is required", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "check" -> check(context.applicationContext, locale, result)
                "download" -> download(context.applicationContext, locale, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun intentFor(locale: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        }

    private fun List<String>.hasLocale(locale: String): Boolean {
        val wanted = Locale.forLanguageTag(locale)
        return any { it.equals(locale, ignoreCase = true) || Locale.forLanguageTag(it) == wanted }
    }

    /**
     * Answers "installed", "downloading", "needsDownload", "unsupported" or
     * "unknown".
     */
    private fun check(context: Context, locale: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("unknown")
            return
        }
        if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            result.success("unsupported")
            return
        }
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        var answered = false
        fun answer(value: String) {
            if (answered) return
            answered = true
            recognizer.destroy()
            result.success(value)
        }
        handler.postDelayed({ answer("unknown") }, CHECK_TIMEOUT_MS)
        recognizer.checkRecognitionSupport(
            intentFor(locale),
            ContextCompat.getMainExecutor(context),
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    val installed = support.installedOnDeviceLanguages
                    val pending = support.pendingOnDeviceLanguages
                    val supported = support.supportedOnDeviceLanguages
                    Log.i(TAG, "$locale: installed=$installed pending=$pending supported=$supported")
                    answer(
                        when {
                            installed.hasLocale(locale) -> "installed"
                            pending.hasLocale(locale) -> "downloading"
                            supported.hasLocale(locale) -> "needsDownload"
                            // A service that lists nothing tells us nothing.
                            installed.isEmpty() && pending.isEmpty() && supported.isEmpty() -> "unknown"
                            else -> "unsupported"
                        },
                    )
                }

                override fun onError(error: Int) {
                    Log.w(TAG, "checkRecognitionSupport error $error")
                    answer("unknown")
                }
            },
        )
    }

    /**
     * Asks the on-device recognition service to download the pack. Answers
     * "installed", "downloading", "scheduled", "requested", "error" or
     * "unavailable".
     */
    private fun download(context: Context, locale: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            result.success("unavailable")
            return
        }
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            requestWithoutListener(recognizer, locale)
            result.success("requested")
            return
        }
        var answered = false
        fun answer(value: String) {
            if (answered) return
            answered = true
            result.success(value)
        }
        recognizer.triggerModelDownload(
            intentFor(locale),
            ContextCompat.getMainExecutor(context),
            object : ModelDownloadListener {
                override fun onProgress(completedPercent: Int) {
                    answer("downloading")
                }

                override fun onSuccess() {
                    answer("installed")
                    recognizer.destroy()
                }

                override fun onScheduled() {
                    answer("scheduled")
                    recognizer.destroy()
                }

                override fun onError(error: Int) {
                    Log.w(TAG, "triggerModelDownload error $error")
                    recognizer.destroy()
                    if (error == SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS) {
                        // The service cannot report progress: ask without a listener.
                        requestWithoutListener(
                            SpeechRecognizer.createOnDeviceSpeechRecognizer(context),
                            locale,
                        )
                        answer("requested")
                    } else {
                        answer("error")
                    }
                }
            },
        )
    }

    private fun requestWithoutListener(recognizer: SpeechRecognizer, locale: String) {
        recognizer.triggerModelDownload(intentFor(locale))
        // The request is sent once the recognizer is bound to the service.
        handler.postDelayed({ recognizer.destroy() }, REQUEST_DESTROY_DELAY_MS)
    }
}

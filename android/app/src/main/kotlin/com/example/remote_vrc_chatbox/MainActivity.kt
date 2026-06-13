package com.wi11oh.remote_vrc_chatbox

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val methodCh = "com.wi11oh.remote_vrc_chatbox/speech"
    private val eventCh  = "com.wi11oh.remote_vrc_chatbox/speech_events"

    private var recognizer: SpeechRecognizer? = null
    private var sink: EventChannel.EventSink? = null
    private var looping = false
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventCh)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
                override fun onCancel(args: Any?) { sink = null }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodCh)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> { start(); result.success(null) }
                    "stop"  -> { stop();  result.success(null) }
                    else    -> result.notImplemented()
                }
            }
    }

    private fun createRecognizer(): SpeechRecognizer {
        // API 33以上かつオンデバイス認識が利用可能なら使う（ビープなし・タイムアウトなし）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
            return SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        }
        return SpeechRecognizer.createSpeechRecognizer(this)
    }

    private fun start() {
        if (looping) return
        looping = true
        recognizer = createRecognizer()
        recognizer?.setRecognitionListener(listener())
        cycle()
    }

    private fun cycle() {
        if (!looping) return
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 300_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 300_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 300_000L)
        }
        recognizer?.startListening(intent)
    }

    private fun listener() = object : RecognitionListener {
        override fun onReadyForSpeech(p: Bundle?) {}
        override fun onPartialResults(b: Bundle?) {
            val text = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
            if (text.isNotEmpty()) sink?.success(mapOf("type" to "partial", "text" to text))
        }
        override fun onResults(b: Bundle?) {
            val text = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""
            if (text.isNotEmpty()) sink?.success(mapOf("type" to "final", "text" to text))
            if (looping) handler.postDelayed(::cycle, 100)
        }
        override fun onError(error: Int) {
            if (looping) handler.postDelayed(::cycle, 100)
        }
        override fun onBeginningOfSpeech() {}
        override fun onEndOfSpeech() {}
        override fun onRmsChanged(v: Float) {}
        override fun onBufferReceived(b: ByteArray?) {}
        override fun onEvent(t: Int, p: Bundle?) {}
    }

    private fun stop() {
        looping = false
        handler.removeCallbacksAndMessages(null)
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
    }

    override fun onDestroy() { stop(); super.onDestroy() }
}

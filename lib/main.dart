import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:remote_vrc_chatbox/drawer.dart';
import 'package:remote_vrc_chatbox/sound.dart';
import "package:remote_vrc_chatbox/theme_provider.dart";

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:remote_vrc_chatbox/text_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:osc/osc.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:provider/provider.dart';

const _speechMethod = MethodChannel('com.wi11oh.remote_vrc_chatbox/speech');
const _speechEvent  = EventChannel('com.wi11oh.remote_vrc_chatbox/speech_events');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDarkTheme = prefs.getBool("isDarkTheme") ?? true;
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(isDarkTheme: isDarkTheme),
      child: const MyApp(),
    )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeProvider.isDarkTheme ? ThemeData.light() : ThemeData.dark(),
          home: const MyForm(),
        );
      },
    );
  }
}

class MyForm extends StatefulWidget {
  const MyForm({Key? key}) : super(key: key);
  @override
  MyFormState createState() => MyFormState();
}

class MyFormState extends State<MyForm> {

  late StreamSubscription _intentDataStreamSubscription;
  late WebSocketChannel _channel;
  late String _ipAddr;
  late StreamSubscription<dynamic> _streamSubscription;
  late bool _isWebsocket = false;

  TextEditingController txc = TextEditingController();
  bool _isTextFieldEmpty = true;
  ScrollController scc = ScrollController();

  List<String> items = [];
  List<String> times = [];
  List<String> modes = [];
  List<bool> bulletins = [];

  SpeechToText speechToText = SpeechToText();
  bool isListenning = false;
  bool _speechAvailable = false;
  bool _isContinuousMode = false;
  String _pttAccumulated = "";
  StreamSubscription? _speechSubscription;

  bool _isBulletinMode = false;
  String _bulletinText = "";
  double _bulletinProgress = 1.0;
  Timer? _bulletinTimer;
  Timer? _bulletinProgressTimer;

  Future<void> _initSpeechToText() async {
    _speechAvailable = await speechToText.initialize();
    setState(() {});
  }

  void _setupSpeechStream() {
    _speechSubscription = _speechEvent.receiveBroadcastStream().listen((event) {
      if (!mounted) return;
      final map = Map<String, dynamic>.from(event as Map);
      final type = map['type'] as String;
      final text = (map['text'] as String?) ?? '';
      if (type == 'partial') {
        setState(() {
          txc.text = _pttAccumulated.isEmpty ? text : '$_pttAccumulated $text';
        });
      } else if (type == 'final' && text.isNotEmpty) {
        if (_isContinuousMode) {
          send({"mode": "nomal", "textmsg": text});
          setState(() { txc.text = ""; });
        } else {
          setState(() {
            _pttAccumulated = _pttAccumulated.isEmpty ? text : '$_pttAccumulated $text';
            txc.text = _pttAccumulated;
          });
        }
      }
    });
  }

  Future<void> _loadContinuousMode() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() { _isContinuousMode = p.getBool("isContinuousMode") ?? false; });
  }

  Future<void> _loadBulletinMode() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() { _isBulletinMode = p.getBool("isBulletinMode") ?? false; });
  }

  void _onContinuousModeToggle(bool value) {
    setState(() { _isContinuousMode = value; });
    if (isListenning) _stopNative();
  }

  void _onBulletinModeToggle(bool value) {
    setState(() { _isBulletinMode = value; });
    if (!value) _stopBulletinLoop();
  }

  void _startBulletinLoop() {
    _bulletinTimer?.cancel();
    _bulletinProgressTimer?.cancel();
    setState(() { _bulletinProgress = 1.0; });

    const totalMs = 20000;
    const intervalMs = 50;
    int elapsed = 0;

    _bulletinProgressTimer = Timer.periodic(
      const Duration(milliseconds: intervalMs),
      (t) {
        elapsed += intervalMs;
        if (!mounted) { t.cancel(); return; }
        setState(() {
          _bulletinProgress = (1.0 - elapsed / totalMs).clamp(0.0, 1.0);
        });
        if (elapsed >= totalMs) t.cancel();
      },
    );

    _bulletinTimer = Timer(const Duration(seconds: 20), () {
      if (!_isBulletinMode || _bulletinText.isEmpty) return;
      send({"mode": "nomal", "textmsg": _bulletinText}, bulletinResend: true);
      _startBulletinLoop();
    });
  }

  void _stopBulletinLoop() {
    _bulletinTimer?.cancel();
    _bulletinProgressTimer?.cancel();
    _bulletinTimer = null;
    _bulletinProgressTimer = null;
    setState(() { _bulletinProgress = 1.0; });
  }

  void _startNative() {
    if (!_speechAvailable) return;
    _pttAccumulated = "";
    setState(() { isListenning = true; });
    _speechMethod.invokeMethod('start');
  }

  void _stopNative({bool sendResult = false}) {
    _speechMethod.invokeMethod('stop');
    if (sendResult && txc.text.isNotEmpty) {
      final text = txc.text;
      Future.delayed(const Duration(milliseconds: 200), () => send({"mode": "nomal", "textmsg": text}));
    }
    setState(() { isListenning = false; _pttAccumulated = ""; txc.text = ""; });
  }

  Timer? _oscTypingTimer;
  bool _isTypingEnabled = false;

  SeSound se = SeSound();

  @override
  void initState() {
    super.initState();
    readConnSet();
    connectToWebSocket();
    _initSpeechToText();
    _loadContinuousMode();
    _loadBulletinMode();
    _setupSpeechStream();

    txc.addListener(_updateTextFieldState);

    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) setState(() { txc.text = value.first.path; });
    }, onError: (_) {});

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) setState(() { txc.text = value.first.path; });
    });


    _oscTypingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isTextFieldEmpty && _isTypingEnabled) {
        _sendTypingOsc();
      }
    });
  }

  void _onTypingToggle(bool enabled) {
    setState(() {
      _isTypingEnabled = enabled;
    });
  }

  Future<void> _onIpSaved() async {
    final p = await SharedPreferences.getInstance();
    final newIp = p.getString("ip") ?? "192.168.0.10";
    setState(() { _ipAddr = newIp; });
    if (_isWebsocket) {
      _channel.sink.close();
      await Future.delayed(const Duration(seconds: 2));
      connectToWebSocket();
    }
  }

  @override
  void dispose() {
    _oscTypingTimer?.cancel();
    _bulletinTimer?.cancel();
    _bulletinProgressTimer?.cancel();
    _streamSubscription.cancel();
    _intentDataStreamSubscription.cancel();
    _speechSubscription?.cancel();
    _speechMethod.invokeMethod('stop');
    _channel.sink.close();
    txc.removeListener(_updateTextFieldState);
    se.dispose();
    super.dispose();
  }

  void _updateTextFieldState() {
    setState(() {
      _isTextFieldEmpty = txc.text.isEmpty;
    });
  }

  Future<void> connectToWebSocket() async {
    final p = await SharedPreferences.getInstance();
    _ipAddr = p.getString("ip") ?? "192.168.0.10";
    _channel = WebSocketChannel.connect(Uri.parse("ws://$_ipAddr:41129"));
    _streamSubscription = _channel.stream.listen((message) {
      final streamMap = jsonDecode(message) as Map<String, dynamic>;
      final clip = streamMap["clip"] as String;
      _addItem(clip, "copy (PC→mobile)");
      Clipboard.setData(ClipboardData(text: clip));
      txc.clear();
      scc.animateTo(
        scc.position.maxScrollExtent + 87,
        duration: const Duration(seconds: 1),
        curve: Curves.fastLinearToSlowEaseIn,
      );
    });
  }

  Future<void> reconnectWebsocket() async {
    _channel.sink.close();
    await Future.delayed(const Duration(seconds: 5));
    connectToWebSocket();
  }

  void disconnectWebsocket() {
    _channel.sink.close();
  }

  void websocket(String text) {
    try {
      _channel.sink.add(text);
    } catch (_) {}
  }

  Future<void> readConnSet() async {
    final p = await SharedPreferences.getInstance();
    setState(() { _isWebsocket = p.getBool("isWebsocket") ?? false; });
  }

  void _addItem(String text, String mode, {bool isBulletin = false}) {
    setState(() {
      items.add(text);
      times.add(DateFormat('yyyy/MM/dd HH:mm:ss').format(DateTime.now()));
      modes.add(mode);
      bulletins.add(isBulletin);
    });
  }

  void addViewAndAnim(String text, String historyViewMode, {bool isBulletin = false}) {
    _addItem(text, historyViewMode, isBulletin: isBulletin);
    txc.clear();
    scc.animateTo(
      scc.position.maxScrollExtent + 87,
      duration: const Duration(seconds: 1),
      curve: Curves.fastLinearToSlowEaseIn
    );
  }

  void send(Map payload, {bool bulletinResend = false}) {
    final payloadjson = jsonEncode(payload);
    String historyViewMode;
    if (payload["mode"] == "nomal" && payload["textmsg"] != "") {
      if (!bulletinResend) se.playSe(SeSoundIds.send);
      if (_isWebsocket) {
        historyViewMode = "text (advanced/WS)";
        websocket(payloadjson);
      } else {
        historyViewMode = "text (nomal/OSC)";
        final message = OSCMessage("/chatbox/input", arguments: [payload["textmsg"], true]);
        const port = 9000;
        RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
          socket.send(message.toBytes(), InternetAddress(_ipAddr), port);
          socket.close();
        }).catchError((_) {});
      }
      if (!bulletinResend) {
        addViewAndAnim(payload["textmsg"], historyViewMode, isBulletin: _isBulletinMode);
        if (_isBulletinMode) {
          _bulletinText = payload["textmsg"] as String;
          _startBulletinLoop();
        }
      }
    } else if (payload["mode"] == "paste" && payload["textmsg"] != "" && _isWebsocket) {
      historyViewMode = "paste (mobile→PC)";
      websocket(payloadjson);
      if (!bulletinResend) addViewAndAnim(payload["textmsg"], historyViewMode);
    } else if (payload["mode"] == "copy" && payload["textmsg"] == "" && _isWebsocket) {
      historyViewMode = "copy (PC→mobile)";
      websocket(payloadjson);
    }
  }

  void submit2() => send({"mode": "nomal", "textmsg": txc.text});

  void pressedit(int i) {
    setState(() {
      txc.text = items[i];
    });
  }

  void _sendTypingOsc() {
    final message = OSCMessage("/chatbox/typing", arguments: [true]);
    const port = 9000;
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((socket) {
      socket.send(message.toBytes(), InternetAddress(_ipAddr), port);
      socket.close();
    }).catchError((e) {
      debugPrint('Error: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xff221c27) : const Color(0xfff3edf7);
    final cardColor = isDark ? const Color(0xff2e2438) : Colors.white;
    const accentColor = Color(0xff9c6fde);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: bgColor,
    ));

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: bgColor.withValues(alpha: 0.85),
            ),
          ),
        ),
        centerTitle: true,
        elevation: 0.0,
        title: const Text(
          "remote vrc-chatbox",
          style: TextStyle(fontSize: 24, fontFamily: "Din"),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
              setState(() {
                SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                  systemNavigationBarColor: isDark
                      ? const Color(0xfff3edf7)
                      : const Color(0xff221c27),
                ));
              });
            },
            icon: const FaIcon(FontAwesomeIcons.circleHalfStroke, size: 20),
          ),
        ],
      ),
      drawer: InDrawerWidget(
        reconnectWebsocketCallback: reconnectWebsocket,
        releadConnSetting: readConnSet,
        disconnectWebsocket: disconnectWebsocket,
        onTypingToggle: _onTypingToggle,
        onContinuousModeToggle: _onContinuousModeToggle,
        onBulletinModeToggle: _onBulletinModeToggle,
        onIpSaved: _onIpSaved,
      ),
      body: ListView.builder(
        controller: scc,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
          bottom: 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final isBulletin = index < bulletins.length && bulletins[index];
          final isLatestBulletin = isBulletin &&
              index == items.length - 1 &&
              _isBulletinMode;
          final metaColor = (isDark ? Colors.white : Colors.black)
              .withValues(alpha: 0.45);

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      "${times[index]}  ·  ${modes[index]}",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: "Din",
                                        color: metaColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    if (isBulletin) ...[
                                      const SizedBox(width: 5),
                                      FaIcon(
                                        FontAwesomeIcons.signHanging,
                                        size: 11,
                                        color: metaColor,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    items[index],
                                    softWrap: false,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontFamily: "Murecho",
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => pressedit(index),
                            icon: FaIcon(
                              FontAwesomeIcons.pen,
                              size: 17,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isLatestBulletin)
                      LinearProgressIndicator(
                        value: _bulletinProgress,
                        backgroundColor: Colors.transparent,
                        color: accentColor.withValues(alpha: 0.55),
                        minHeight: 3,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: bgColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          12, 10, 12,
          10 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _isContinuousMode
                        ? () {
                            if (isListenning) { _stopNative(); }
                            else { _startNative(); }
                          }
                        : null,
                    onTapDown: _isContinuousMode
                        ? null
                        : (details) {
                            if (!isListenning) { _startNative(); }
                          },
                    onTapUp: _isContinuousMode
                        ? null
                        : (detail) { _stopNative(sendResult: true); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isListenning
                            ? accentColor
                            : (isDark
                                ? const Color(0xff3a2f4a)
                                : const Color(0xffe8dff0)),
                      ),
                      child: Center(
                        child: FaIcon(
                          isListenning && _isContinuousMode
                              ? FontAwesomeIcons.microphoneLines
                              : FontAwesomeIcons.microphone,
                          size: 18,
                          color: isListenning
                              ? Colors.white
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : Colors.black.withValues(alpha: 0.55)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Material(
                      color: isDark
                          ? const Color(0xff3a2f4a)
                          : const Color(0xffe8dff0),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        onPressed: !_isWebsocket
                            ? null
                            : () {
                                if (txc.text == "") {
                                  send({"mode": "copy", "textmsg": ""});
                                } else {
                                  send({"mode": "paste", "textmsg": txc.text});
                                }
                              },
                        padding: EdgeInsets.zero,
                        icon: FaIcon(
                          FontAwesomeIcons.solidPaste,
                          size: 18,
                          color: _isWebsocket
                              ? (isDark
                                  ? Colors.white.withValues(alpha: 0.7)
                                  : Colors.black.withValues(alpha: 0.55))
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.2)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextFormField(
                        onEditingComplete: () {
                          send({"mode": "nomal", "textmsg": txc.text});
                        },
                        style: const TextStyle(
                          fontSize: 20,
                          fontFamily: "Murecho",
                        ),
                        textAlignVertical: TextAlignVertical.center,
                        cursorHeight: 30,
                        scrollPadding: EdgeInsets.zero,
                        controller: txc,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: cardColor,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: accentColor,
                              width: 1.5,
                            ),
                          ),
                          prefixIcon: IconButton(
                            onPressed: !_isTextFieldEmpty
                                ? () => showTextModal(context, txc)
                                : null,
                            splashRadius: 20,
                            iconSize: 15,
                            padding: EdgeInsets.zero,
                            color: !_isTextFieldEmpty
                                ? (isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.black.withValues(alpha: 0.55))
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.2)),
                            icon: const FaIcon(FontAwesomeIcons.ellipsis),
                          ),
                          suffixIcon: IconButton(
                            splashRadius: 20,
                            color: !_isTextFieldEmpty
                                ? (isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : Colors.black.withValues(alpha: 0.55))
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.2)),
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            onPressed: !_isTextFieldEmpty ? submit2 : null,
                            icon: const FaIcon(FontAwesomeIcons.paperPlane),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (isListenning)
                Positioned(
                  bottom: 52,
                  left: 0,
                  child: Container(
                    height: 68,
                    width: 220,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      color: cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.4 : 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isContinuousMode
                              ? "連続認識中\n発話ごとに自動送信"
                              : "音声認識中\nPTT : 押してる間だけ",
                          style: const TextStyle(fontFamily: "Murecho", fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

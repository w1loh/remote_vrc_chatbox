import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:remote_vrc_chatbox/thirdparty_nts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InDrawerWidget extends StatefulWidget {
  final VoidCallback reconnectWebsocketCallback;
  final VoidCallback releadConnSetting;
  final VoidCallback disconnectWebsocket;
  final ValueChanged<bool> onTypingToggle;
  final ValueChanged<bool> onContinuousModeToggle;
  final ValueChanged<bool> onBulletinModeToggle;
  final VoidCallback onIpSaved;

  const InDrawerWidget({
    Key? key,
    required this.reconnectWebsocketCallback,
    required this.releadConnSetting,
    required this.disconnectWebsocket,
    required this.onTypingToggle,
    required this.onContinuousModeToggle,
    required this.onBulletinModeToggle,
    required this.onIpSaved,
  }) : super(key: key);

  @override
  InDrawerWidgetState createState() => InDrawerWidgetState();
}

class InDrawerWidgetState extends State<InDrawerWidget> {
  late bool _isWebsocket = false;
  late bool _isTypingEnabled = false;
  late bool _isContinuousMode = false;
  bool _isBulletinMode = false;

  @override
  void initState() {
    super.initState();
    readConnSet();
    _loadTypingSetting();
    _loadContinuousModeSetting();
    _loadBulletinModeSetting();
  }

  Future<void> _loadTypingSetting() async {
    final p = await SharedPreferences.getInstance();
    final value = p.getBool("isTypingEnabled") ?? false;
    setState(() { _isTypingEnabled = value; });
    widget.onTypingToggle(value);
  }

  Future<void> _saveTypingSetting(bool value) async {
    final p = await SharedPreferences.getInstance();
    p.setBool("isTypingEnabled", value);
  }

  Future<void> _loadContinuousModeSetting() async {
    final p = await SharedPreferences.getInstance();
    final value = p.getBool("isContinuousMode") ?? false;
    setState(() { _isContinuousMode = value; });
    widget.onContinuousModeToggle(value);
  }

  Future<void> _saveContinuousModeSetting(bool value) async {
    final p = await SharedPreferences.getInstance();
    p.setBool("isContinuousMode", value);
  }

  Future<void> _loadBulletinModeSetting() async {
    final p = await SharedPreferences.getInstance();
    final value = p.getBool("isBulletinMode") ?? false;
    setState(() { _isBulletinMode = value; });
    widget.onBulletinModeToggle(value);
  }

  Future<void> _saveBulletinModeSetting(bool value) async {
    final p = await SharedPreferences.getInstance();
    p.setBool("isBulletinMode", value);
  }

  Future<void> setIP(String value) async {
    final p = await SharedPreferences.getInstance();
    p.setString("ip", value);
  }

  Future<void> setConnectPtcl(bool value) async {
    final p = await SharedPreferences.getInstance();
    p.setBool("isWebsocket", value);
  }

  Future<void> readConnSet() async {
    bool value = false;
    try {
      final p = await SharedPreferences.getInstance();
      value = p.getBool("isWebsocket") ?? false;
    } catch (e) {
      debugPrint("$e");
    }
    setState(() { _isWebsocket = value; });
  }

  bool _isValidIPv4(String input) {
    final regex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    if (!regex.hasMatch(input)) return false;
    return input.split('.').map(int.parse).every((s) => s >= 0 && s <= 255);
  }

  Future<void> _showSettingDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xff2e2438) : Colors.white;
    const accentColor = Color(0xff9c6fde);
    final iptxconn = TextEditingController();

    void trySubmit() {
      if (_isValidIPv4(iptxconn.text)) {
        try { setIP(iptxconn.text); } catch (e) { debugPrint("$e"); }
        Navigator.pop(context);
        widget.onIpSaved();
        Fluttertoast.showToast(
          msg: "IP保存済み・再接続します",
          gravity: ToastGravity.BOTTOM,
          toastLength: Toast.LENGTH_LONG,
          fontSize: 20,
        );
      } else {
        Navigator.pop(context);
        Fluttertoast.showToast(
          msg: "有効なIPv4アドレスではありません",
          gravity: ToastGravity.BOTTOM,
          toastLength: Toast.LENGTH_LONG,
          fontSize: 20,
        );
      }
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("IP設定", style: TextStyle(fontFamily: "Murecho")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                controller: iptxconn,
                onFieldSubmitted: (_) => trySubmit(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cardColor,
                  hintText: '例 192.168.0.10',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  suffixIcon: IconButton(
                    onPressed: trySubmit,
                    icon: const FaIcon(FontAwesomeIcons.rotateLeft, size: 16),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: accentColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  text: "設定後はアプリを再起動してください。\nローカルIPの調べ方は ",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: "Murecho"),
                  children: [
                    TextSpan(
                      text: "こちら",
                      style: const TextStyle(
                        color: Color(0xff9c6fde),
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.bold,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          launchUrl(
                            Uri.parse("https://w1loh.com/other/remote_vrc_chatbox_tips/"),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                    ),
                    const TextSpan(text: " を参照"),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "キャンセル",
                style: TextStyle(
                  fontFamily: "Murecho",
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
                ),
              ),
            ),
            TextButton(
              onPressed: trySubmit,
              child: const Text("保存", style: TextStyle(color: Color(0xff9c6fde), fontFamily: "Murecho")),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xff221c27) : const Color(0xfff3edf7);
    final iconBg = isDark ? const Color(0xff3a2f4a) : const Color(0xffe8dff0);
    final iconColor = isDark ? Colors.white.withValues(alpha: 0.75) : Colors.black.withValues(alpha: 0.6);
    final dimColor = isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.2);
    final dividerColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    const accentColor = Color(0xff9c6fde);

    Widget iconBox(FaIconData icon, {bool enabled = true}) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: FaIcon(icon, size: 15, color: enabled ? iconColor : dimColor),
      ),
    );

    Widget tile({
      required FaIconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Widget? trailing,
      bool enabled = true,
    }) =>
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: iconBox(icon, enabled: enabled),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: "Murecho",
              fontSize: 15,
              color: enabled ? null : dimColor,
            ),
          ),
          subtitle: subtitle != null
              ? Text(subtitle, style: const TextStyle(fontSize: 12))
              : null,
          trailing: trailing,
          onTap: onTap,
        );

    WidgetStateColor switchTrack = WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return accentColor.withValues(alpha: 0.45);
      return (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
    });
    WidgetStateColor switchThumb = WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return accentColor;
      return isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.4);
    });

    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "remote vrc-chatbox",
                    style: TextStyle(fontFamily: "Din", fontSize: 26),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "made by うぃろー / w1loh",
                    style: TextStyle(
                      fontFamily: "Din",
                      fontSize: 10,
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: dividerColor, indent: 20, endIndent: 20),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  tile(
                    icon: FontAwesomeIcons.networkWired,
                    title: "IP設定",
                    subtitle: "VRChatが起動しているPC、またはquestのLocal-IP",
                    onTap: () => _showSettingDialog(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: iconBox(FontAwesomeIcons.keyboard),
                      title: const Text("タイピング中表示", style: TextStyle(fontFamily: "Murecho", fontSize: 15)),
                      subtitle: const Text("テキストボックスが空でない場合、・・・を頭上に表示します", style: TextStyle(fontSize: 12)),
                      trackColor: switchTrack,
                      thumbColor: switchThumb,
                      value: _isTypingEnabled,
                      onChanged: (v) {
                        setState(() { _isTypingEnabled = v; });
                        _saveTypingSetting(v);
                        widget.onTypingToggle(v);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: iconBox(FontAwesomeIcons.microphone),
                      title: const Text("音声入力モード", style: TextStyle(fontFamily: "Murecho", fontSize: 15)),
                      subtitle: const Text("OFF : PTT (押してる間) / ON : 連続認識", style: TextStyle(fontSize: 12)),
                      trackColor: switchTrack,
                      thumbColor: switchThumb,
                      value: _isContinuousMode,
                      onChanged: (v) {
                        setState(() { _isContinuousMode = v; });
                        _saveContinuousModeSetting(v);
                        widget.onContinuousModeToggle(v);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: iconBox(FontAwesomeIcons.signHanging),
                      title: const Text("掲示モード", style: TextStyle(fontFamily: "Murecho", fontSize: 15)),
                      subtitle: const Text("最新の送信を20秒ごとにループ送信します", style: TextStyle(fontSize: 12)),
                      trackColor: switchTrack,
                      thumbColor: switchThumb,
                      value: _isBulletinMode,
                      onChanged: (v) {
                        setState(() { _isBulletinMode = v; });
                        _saveBulletinModeSetting(v);
                        widget.onBulletinModeToggle(v);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: iconBox(FontAwesomeIcons.sliders),
                      title: const Text("通信方式", style: TextStyle(fontFamily: "Murecho", fontSize: 15)),
                      subtitle: const Text("nomal ↔ advanced", style: TextStyle(fontSize: 12)),
                      trackColor: switchTrack,
                      thumbColor: switchThumb,
                      value: _isWebsocket,
                      onChanged: (v) {
                        setState(() { _isWebsocket = v; });
                        try { setConnectPtcl(v); } catch (e) { debugPrint("$e"); }
                        widget.releadConnSetting();
                        if (!_isWebsocket) {
                          widget.disconnectWebsocket();
                        } else {
                          Fluttertoast.showToast(
                            msg: "接続中… 5秒以上要します🍵",
                            gravity: ToastGravity.BOTTOM,
                            toastLength: Toast.LENGTH_LONG,
                            backgroundColor: const Color(0xff2e2438),
                            textColor: Colors.white,
                            fontSize: 20,
                          );
                          widget.reconnectWebsocketCallback();
                        }
                      },
                    ),
                  ),
                  tile(
                    icon: FontAwesomeIcons.arrowsRotate,
                    title: "再接続",
                    subtitle: "advancedモードのみ",
                    enabled: _isWebsocket,
                    onTap: !_isWebsocket
                        ? null
                        : () {
                            Navigator.pop(context);
                            widget.reconnectWebsocketCallback();
                            Fluttertoast.showToast(
                              msg: "再接続中… 5秒以上要します🍵",
                              gravity: ToastGravity.BOTTOM,
                              toastLength: Toast.LENGTH_LONG,
                              backgroundColor: const Color(0xff2e2438),
                              textColor: Colors.white,
                              fontSize: 20,
                            );
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Divider(height: 1, thickness: 1, color: dividerColor),
                  ),
                  tile(
                    icon: FontAwesomeIcons.link,
                    title: "作者のリンク集",
                    onTap: () => launchUrl(Uri.parse("https://dev.w1loh.com/"), mode: LaunchMode.externalApplication),
                    trailing: FaIcon(FontAwesomeIcons.upRightFromSquare, size: 13, color: dimColor),
                  ),
                  tile(
                    icon: FontAwesomeIcons.book,
                    title: "マニュアル・プライバシーポリシー",
                    onTap: () => launchUrl(Uri.parse("https://github.com/w1loh/remote_vrc_chatbox"), mode: LaunchMode.externalApplication),
                    trailing: FaIcon(FontAwesomeIcons.upRightFromSquare, size: 13, color: dimColor),
                  ),
                  tile(
                    icon: FontAwesomeIcons.scaleBalanced,
                    title: "法的表示",
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const LicenceView()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

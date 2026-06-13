import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class ThemeProvider with ChangeNotifier {
  bool _isDarkTheme;

  ThemeProvider({bool isDarkTheme = true}) : _isDarkTheme = isDarkTheme;

  bool get isDarkTheme => _isDarkTheme;

  void toggleTheme() {
    _isDarkTheme = !_isDarkTheme;
    notifyListeners();
    _saveTheme();
  }

  Future<void> _saveTheme() async {
    final p = await SharedPreferences.getInstance();
    p.setBool("isDarkTheme", _isDarkTheme);
  }
}

import 'package:flutter/material.dart';

/// 心情枚举：手账记录时的情绪状态。
enum Mood {
  happy('happy', '开心', '😄', Color(0xFFFFB74D)),
  calm('calm', '平静', '😌', Color(0xFF81C784)),
  excited('excited', '兴奋', '🤩', Color(0xFFFF7043)),
  tired('tired', '疲惫', '😪', Color(0xFF9575CD)),
  sad('sad', '难过', '😢', Color(0xFF64B5F6)),
  angry('angry', '生气', '😠', Color(0xFFE57373)),
  anxious('anxious', '焦虑', '😰', Color(0xFF4DB6AC)),
  moved('moved', '感动', '🥹', Color(0xFFF06292)),
  grateful('grateful', '感恩', '🙏', Color(0xFFAED581)),
  neutral('neutral', '一般', '😐', Color(0xFF90A4AE));

  const Mood(this.id, this.label, this.emoji, this.color);

  final String id;
  final String label;
  final String emoji;
  final Color color;

  static Mood fromId(String? id) =>
      Mood.values.where((m) => m.id == id).firstOrNull ?? Mood.neutral;
}

/// 天气枚举：记录当天的天气。
enum Weather {
  sunny('sunny', '晴', '☀️', Color(0xFFFFB300)),
  cloudy('cloudy', '多云', '⛅', Color(0xFF78909C)),
  overcast('overcast', '阴', '☁️', Color(0xFF90A4AE)),
  lightRain('lightRain', '小雨', '🌧️', Color(0xFF64B5F6)),
  storm('storm', '雷雨', '⛈️', Color(0xFF5C6BC0)),
  snow('snow', '雪', '❄️', Color(0xFF81D4FA)),
  windy('windy', '大风', '💨', Color(0xFF4DD0E1)),
  foggy('foggy', '雾', '🌫️', Color(0xFFB0BEC5));

  const Weather(this.id, this.label, this.emoji, this.color);

  final String id;
  final String label;
  final String emoji;
  final Color color;

  static Weather fromId(String? id) =>
      Weather.values.where((w) => w.id == id).firstOrNull ?? Weather.sunny;
}

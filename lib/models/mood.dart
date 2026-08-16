import 'package:flutter/material.dart';

/// 心情枚举：手账记录时的情绪状态。
///
/// score 为 1–10 的情绪分值（REQ-05 心情趋势）：分值越低情绪越差。
enum Mood {
  happy('happy', '开心', '😄', Color(0xFFFFB74D), 9),
  calm('calm', '平静', '😌', Color(0xFF81C784), 6),
  excited('excited', '兴奋', '🤩', Color(0xFFFF7043), 10),
  tired('tired', '疲惫', '😪', Color(0xFF9575CD), 4),
  sad('sad', '难过', '😢', Color(0xFF64B5F6), 2),
  angry('angry', '生气', '😠', Color(0xFFE57373), 1),
  anxious('anxious', '焦虑', '😰', Color(0xFF4DB6AC), 3),
  moved('moved', '感动', '🥹', Color(0xFFF06292), 8),
  grateful('grateful', '感恩', '🙏', Color(0xFFAED581), 7),
  neutral('neutral', '一般', '😐', Color(0xFF90A4AE), 5);

  const Mood(this.id, this.label, this.emoji, this.color, this.score);

  final String id;
  final String label;
  final String emoji;
  final Color color;

  /// 情绪分值 1–10，用于心情趋势折线图。
  final int score;

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

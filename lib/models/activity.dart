/// 活动定义：手账可附加的当日活动（REQ-12）。
class Activity {
  const Activity(this.emoji, this.name);

  final String emoji;
  final String name;
}

/// 内置活动预设（≥12 个）。
const presetActivities = [
  Activity('🏃', '运动'),
  Activity('🚶', '散步'),
  Activity('📖', '阅读'),
  Activity('📝', '学习'),
  Activity('💻', '工作'),
  Activity('🍜', '美食'),
  Activity('☕', '咖啡'),
  Activity('🍳', '下厨'),
  Activity('🎬', '观影'),
  Activity('🎮', '游戏'),
  Activity('🎵', '音乐'),
  Activity('🛒', '购物'),
  Activity('🧹', '打扫'),
  Activity('💤', '早睡'),
  Activity('🌞', '早起'),
  Activity('🧘', '冥想'),
  Activity('✈️', '旅行'),
  Activity('👥', '聚会'),
];

/// 自定义活动的默认图标。
const customActivityEmoji = '✨';

/// 根据活动名查图标：预设命中返回预设图标，否则返回自定义图标。
String emojiOfActivity(String name) {
  for (final a in presetActivities) {
    if (a.name == name) return a.emoji;
  }
  return customActivityEmoji;
}

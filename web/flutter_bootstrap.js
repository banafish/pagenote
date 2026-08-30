{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    // CanvasKit 从本地部署加载（flutter build web 会把引擎自带 canvaskit/
    // 复制进产物根目录，与站点同源），不走默认的 gstatic.com——大陆网络
    // 不可达，引擎会一直卡在首帧之前。
    canvasKitBaseUrl: "/canvaskit/"
  }
});

import java.io.FileInputStream
import java.util.Properties
import groovy.json.JsonOutput
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Glance 小组件（REQ-14）依赖 Compose 编译器,需在 Kotlin 插件之后应用。
    id("org.jetbrains.kotlin.plugin.compose")
}

// 正式签名信息读取自 android/key.properties（不入库）；
// 密钥库为 android/app/pagenote-release.jks。缺少该文件时回退 debug 签名，
// 保证其他机器上 `flutter run` 不受影响。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.pagenote.pagenote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 要求开启核心库脱糖（REQ-07）。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pagenote.pagenote"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
            }
        }
    }

    buildTypes {
        release {
            // 关闭 R8 压缩：Room/WorkManager 等依赖反射加载的类（如 WorkDatabase_Impl）
            // 会被误删导致启动即崩溃（2026-08 排查结论）。
            isMinifyEnabled = false
            isShrinkResources = false
            // 有 key.properties 时用正式签名打包，否则回退 debug 签名。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // 桌面小组件（REQ-14,仅 Android）。
    implementation("androidx.glance:glance-appwidget:1.1.1")
}

flutter {
    source = "../.."
}

// —— Android release 花样字体瘦身 ——
// release 包只内置 bundledFontFiles 列出的字体，其余（从 pubspec fonts 段
// 提取的 fonts/*.ttf）在 Flutter 资产拷贝进合并目录后剔除、FontManifest
// 同步改写；运行时由 lib/services/font_loader_service.dart 从本地缓存或
// 远端（--dart-define=PAGENOTE_FONT_BASE_URL）按需注册。debug/profile
// 全量随包，本地开发与单元测试不受影响。
// 本清单须与 lib/models/app_fonts.dart 的 bundledFontAssets 一致
// （test/font_packaging_test.dart 校验）。MaterialIcons 等系统字体是
// .otf，不在 pubspec 提取范围内，天然不受影响。
val bundledFontFiles = setOf("LXGWWenKaiLite-Regular.ttf")

tasks.whenTaskAdded {
    // 注意挂在 copyFlutterAssetsRelease 而非 mergeReleaseAssets 上：
    // AGP 9 的 mergeReleaseAssets 输出里没有 flutter_assets，花样字体
    // 是 Flutter 插件在本任务中才拷入的，之后还有 compressReleaseAssets
    // 与打包，doLast 时机恰好卡在两者之间。
    if (name != "copyFlutterAssetsRelease") return@whenTaskAdded
    doLast {
        val pubspec = rootProject.file("../pubspec.yaml")
        if (!pubspec.isFile) return@doLast
        val declared = Regex("(?m)^\\s*-\\s*asset:\\s*fonts/(\\S+)\\s*\$")
            .findAll(pubspec.readText())
            .map { it.groupValues[1] }
            .toSet()
        val excluded = declared - bundledFontFiles
        if (excluded.isEmpty()) return@doLast

        // Flutter 插件会把 Android 构建目录重定向到 <仓库根>/build/<模块名>，
        // 各 Gradle 版本对该重定向在 buildDir / layout.buildDirectory 上的
        // 表现不一，因此从任务自身输出 + 两个构建目录属性多路定位合并产物，
        // 匹配条件严格（flutter_assets/fonts 下且文件名在剔除清单里），
        // 不会误伤其他位置。
        @Suppress("DEPRECATION")
        val roots = buildSet {
            outputs.files.forEach { if (it.isDirectory) add(it) }
            add(project.buildDir.resolve("intermediates/assets/release"))
            add(layout.buildDirectory.get().dir("intermediates/assets/release").asFile)
        }

        var removed = 0
        val manifests = mutableListOf<File>()
        for (root in roots) {
            if (!root.isDirectory) continue
            root.walkTopDown().forEach { file ->
                if (!file.isFile) return@forEach
                val parent = file.parentFile
                val grand = parent.parentFile
                if (parent.name == "fonts" && grand.name == "flutter_assets" &&
                    file.name in excluded && file.delete()
                ) {
                    removed++
                } else if (file.name == "FontManifest.json" &&
                    parent.name == "flutter_assets"
                ) {
                    manifests.add(file)
                }
            }
        }
        if (manifests.isEmpty()) {
            println("字体瘦身：未定位到合并资产目录（roots=${roots.map { it.path }}），本次未剔除")
            return@doLast
        }

        // FontManifest 只保留资产仍在盘上的字体条目，避免引擎启动时
        // 尝试加载已剔除的字体。
        var droppedEntries = 0
        for (manifest in manifests) {
            val parsed = JsonSlurper().parse(manifest) as? List<*>
                ?: continue
            val fontsDir = manifest.parentFile.resolve("fonts")
            val kept = parsed.filter { entry ->
                val specs = (entry as? Map<*, *>)?.get("fonts") as? List<*>
                    ?: return@filter true
                specs.all { spec ->
                    val asset = (spec as? Map<*, *>)?.get("asset") as? String
                    asset.isNullOrEmpty() || !asset.startsWith("fonts/") ||
                        fontsDir.resolve(asset.removePrefix("fonts/")).isFile
                }
            }
            if (kept.size != parsed.size) {
                manifest.writeText(JsonOutput.toJson(kept))
                droppedEntries += parsed.size - kept.size
            }
        }
        println(
            "字体瘦身：release 合并资产剔除 $removed 个花样字体文件，" +
                "FontManifest 移除 $droppedEntries 个字体条目"
        )
    }
}

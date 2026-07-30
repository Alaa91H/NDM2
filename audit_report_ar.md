# تقرير التدقيق المجهري الشامل لمشروع NOVA

**التاريخ:** 29 يوليو 2026  
**النطاق:** 80+ ملف Rust عبر 19 وحدة  
**الأسطر المفحوصة:** ~15,000+ سطر

---

## جدول المحتويات
1. [نظرة عامة على البنية](#نظرة-عامة-على-البنية)
2. [الكود الميت (Dead Code)](#الكود-الميت-dead-code)
3. [مشاكل تزامن وسباق (Concurrency)](#مشاكل-تزامن-وسباق-concurrency)
4. [مشاكل إدارة الذاكرة](#مشاكل-إدارة-الذاكرة)
5. [مشاكل أداء](#مشاكل-أداء)
6. [مشاكل أمان الشبكة](#مشاكل-أمان-الشبكة)
7. [مشاكل libcurl (FFI الخام)](#مشاكل-libcurl-ffi-الخام)
8. [مشاكل معمارية](#مشاكل-معمارية)
9. [تضخم الكود والازدواجية](#تضخم-الكود-والازدواجية)
10. [خرائط التدفق](#خرائط-التدفق)
11. [قائمة الأولويات للتصليح](#قائمة-الأولويات-للتصليح)

---

## نظرة عامة على البنية

```
nova-tauri/
├── src/
│   ├── main.rs                          # نقطة الدخول
│   ├── lib.rs                           # تكوين Tauri، مسح المنافذ
│   ├── native_host.rs                   # تواصل مع إضافة المتصفح
│   └── daemon/
│       ├── mod.rs                       # إعداد الخادم، التوجيه
│       ├── state.rs                     # AppState (25+ نظام فرعي)
│       ├── types.rs                     # الأنواع الأساسية
│       ├── persist.rs                   # حفظ/تحميل الحالة
│       ├── utils.rs                     # أدوات مساعدة
│       ├── direct.rs                    # محلل URL المباشر (libcurl FFI)
│       ├── diagnostics.rs              # تشخيص E2E
│       ├── engine_capabilities.rs       # قدرات المحرك
│       ├── telegram.rs                  # بوت تلغرام
│       ├── ytdlp.rs                     # مدير عملية yt-dlp
│       ├── static_files.rs             # خدمة الملفات الثابتة
│       ├── curl/                       # 7 ملفات - دورة حياة التحميل
│       ├── engine/                     # 19 ملفًا - محرك التحميل
│       ├── adaptive/                   # 9 ملفات - التكيفي
│       ├── resource_intelligence/      # 8 ملفات - استخبار الموارد
│       ├── routes/                     # 9 ملفات - نقاط API
│       └── external_tools/             # 10 ملفات - إدارة الأدوات الخارجية
```

---

## الكود الميت (Dead Code)

### المستوى الحرج

| # | الموقع | الوصف | التأثير |
|---|--------|-------|---------|
| C1 | `daemon/engine/chunk_manager.rs` | الملف بأكمله `#[allow(dead_code)]` على `struct ChunkManager` و `impl` | وحدة كاملة ~150 سطرًا غير مستخدمة |
| C2 | `daemon/engine/die_orchestrator.rs` | الملف بأكمله `#[allow(dead_code)]` على `struct DieOrchestrator` و `impl` | وحدة كاملة لا تفعل شيئًا سوى استدعاء ChunkManager |
| C3 | `daemon/engine/adaptive/mod.rs` | `#![allow(dead_code)]` عالمي على مستوى الملفولم يتم تضمين أي من دوال الصيانات العامة | وحدة التكيف بالكامل غير متصلة |
| C4 | `daemon/adaptive/mod.rs` | `#![allow(dead_code)]` عالمي | 9 ملفات غير متصلة تمامًا |
| C5 | `daemon/adaptive/segment_controller.rs` | `allow(dead_code)` على `SegmentPlan`, `SegmentController` | نظام تجزئة كامل غير مستخدم |
| C6 | `daemon/adaptive/disk_writer.rs` | `allow(dead_code)` عالمي | كاتب قرص غير متصل |
| C7 | `daemon/adaptive/buffer_manager.rs` | `allow(dead_code)` على معظم الدوال | مدير مخازن مؤقتة غير متصل |
| C8 | `daemon/adaptive/convergence.rs` | `allow(dead_code)` عالمي | كاشف تقارب غير متصل |
| C9 | `daemon/adaptive/resource_monitor.rs` | `allow(dead_code)` عالمي | مراقب موارد غير متصل |
| C10 | `daemon/adaptive/server_profiler.rs` | `allow(dead_code)` عالمي | ملف تعريف خادم غير متصل |
| C11 | `daemon/adaptive/protocol_adapter.rs` | `allow(dead_code)` عالمي | مهايئ بروتوكول غير متصل |
| C12 | `daemon/engine/adaptive_connections.rs` | `allow(dead_code)` على `AdaptiveConnections` | وحدة اتصالات تكيفية غير متصلة |

### المستوى المتوسط

| # | الموقع | الوصف |
|---|--------|-------|
| M1 | `daemon/state.rs:110` | `#[allow(dead_code)]` على حقل `adaptive_engine` في `AppState` |
| M2 | `daemon/state.rs:133` | `#[allow(dead_code)]` على حقل `unified_profile_store` |
| M3 | `daemon/state.rs:141` | `#[allow(dead_code)]` على حقل `self_healer` في `EngineState` |
| M4 | `daemon/state.rs` | `shared_extractor_registry` تم تضمينه ولكنه لا يُستخدم في أي مسار استخدام فعلي |
| M5 | `daemon/routes/engine.rs` | نقاط نهاية API لـ `engine/checksum` و `engine/chunk-manager` و `engine/scheduler` بدون متصل حقيقي |
| M6 | `daemon/engine/config.rs` | `#[allow(dead_code)]` على `BandwidthConfig::dynamic_adjustment` و `BufferConfig::adaptive` |
| M7 | `daemon/engine/thread_pool.rs:71` | `spawn()` public ولكن لا يُستخدم (يُستخدم `#[allow(dead_code)]`) |
| M8 | `daemon/engine/resource_manager.rs` | `update_network()` و `current_memory_pressure()` مع `#[allow(dead_code)]` |
| M9 | `daemon/resource_intelligence/retry_intel.rs` | `retry_decisions` field في `ResourceIntelligenceEngine` مع `#[allow(dead_code)]` |
| M10 | `daemon/resource_intelligence/strategy.rs` | `MIRRORED` و `ADAPTIVE` و `AUTHENTICATED` استراتيجيات غير متصلة |
| M11 | `daemon/engine/extractor.rs` | `SharedExtractorRegistry` تم تضمينه ولكنه لا يُستخدم (تم تسجيل extractor واحد فقط) |
| M12 | `daemon/external_tools/process.rs` | كامل مع `#[allow(dead_code)]` |

### إجمالي الكود الميت
- **3 ملفات كاملة مع `#![allow(dead_code)]` عام**: `adaptive/mod.rs` و `adaptive/segment_controller.rs` و `adaptive/server_profiler.rs` و `adaptive/protocol_adapter.rs` و `adaptive/convergence.rs` و `adaptive/resource_monitor.rs` و `adaptive/disk_writer.rs`
- **وحدتان كاملتان غير متصلتين**: `chunk_manager.rs` و `die_orchestrator.rs`
- **9+ دوال وهياكل مع `#[allow(dead_code)]` موضعي**
- **تقدير: ~40% من قاعدة كود المحرك غير مستخدم فعليًا**

---

## مشاكل تزامن وسباق (Concurrency)

### BUG-HIGH-1: تناقض ترتيب القفل (ميتة قفل محتملة)
**الموقع:** `daemon/engine/profiles.rs:203-214`  
**الوصف:** `active_profile()` يقفل `active_profile` ثم `profiles`. الدالة `set_active()` تقفل `active_profile` فقط. التعليق يقول "تجنب ABBA deadlock" لكن `ProfileManager` يستخدم قفلين مع ترتيب مختلف في طرق مختلفة.

### BUG-MED-1: قفل Mutex متعدد عبر `resource_manager.snapshot()`
**الموقع:** `daemon/engine/adaptive/mod.rs:106` → `resource_monitor.rs:51`  
**الوصف:** `sample()` يقفل `System` mutex (WinAPI). يتم الاحتفاظ بالقفل عبر استدعاءات دوال متعددة.

### BUG-MED-2: Poisoned Mutex يتم تجاهله
**الموقع:** `daemon/engine/extractor.rs:88-90`  
**الوصف:** `shared.all()` يستخدم `.unwrap_or_default()` على mutex poisoned ← يعيد مصفوفة فارغة بصمت.

### BUG-MED-3: تنافس على Atomic في ThreadPool
**الموقع:** `daemon/engine/thread_pool.rs:41-44`  
**الوصف:** `fetch_add` مع `Relaxed` ← ترتيب الذاكرة ضعيف جدًا. لا يضمن رؤية `active_count` الصحيحة.

### BUG-LOW-1: Mutex مقفل عبر `.await`
**الموقع:** `daemon/routes/external_tools.rs:42-44`  
**الوصف:** `lock_or_err!` يمسك القفل، ثم `drop(manager)` يحرره. آمن حاليًا لكنه هش - إضافة `.await` قبله سيسبب ميتة قفل.

### BUG-LOW-2: قفل Mutex في `telegram_notify`
**الموقع:** `daemon/telegram.rs:449-454`  
**الوصف:** يتم قفل `telegram_config` مباشرة بدلاً من استخدام `lock_or_err!`.

---

## مشاكل إدارة الذاكرة

### BUG-HIGH-2: استخدام `unsafe` مع عدم التحقق من النتائج
**الموقع:** `daemon/engine/resource_manager.rs:85-93`  
**الوصف:** `unsafe { let mut status: MemoryStatusEx = mem::zeroed(); ... }` — عدم التحقق من صحة `dw_length` قبل الاستدعاء.

### BUG-HIGH-3: عدم التحقق من حجم المخزن عند libcurl FFI
**الموقع:** `daemon/curl/easy_config.rs`  
**الوصف:** `setopt_raw_str` و `setopt_raw_ptr` تستدعي `CString::new(url).unwrap()` ← إذا احتوى الـ URL على `\0` داخلي، سينهار البرنامج.

### BUG-MED-4: `Vec::with_capacity` في `percent_decode_str` قد يكون غير دقيق
**الموقع:** `daemon/routes/common.rs:309`  
**الوصف:** الحجم المحجوز `bytes.len()` صحيح، ولكن الترميز إلى UTF-8 قد ينتج عنه بايتات أكثر.

### BUG-LOW-3: `String::from_utf8_lossy` مع فقدان بيانات
**الموقع:** متعدد - `daemon/diagnostics.rs:99`, `daemon/routes/extension.rs:619`  
**الوصف:** استخدام `from_utf8_lossy` على خرج الأدوات الخارجية قد يفقد البيانات أو يبدلها.

---

## مشاكل أداء

### PERF-1: Busy-wait في `hidden_output_timed`
**الموقع:** `daemon/routes/common.rs:48-70`  
**الوصف:** حلقة `sleep(50ms)` تنتظر انتهاء العملية. هذه دالة محظورة (blocking) لذا لا تمنع المفاعل، لكنها تستنزف موارد النظام.

### PERF-2: `serde_json::from_str` متكرر على نفس البيانات
**الموقع:** `daemon/engine/engine_capabilities.rs`  
**الوصف:** يتم تحليل JSON لنتائج curl كل مرة بدلاً من التخزين المؤقت.

### PERF-3: `Duration::from_millis(50)` في حلقات التحديث
**الموقع:** متعدد - `daemon/telegram.rs:243`, `daemon/external_tools/health.rs:125`  
**الوصف:** حلقات استقصاء بفاصل 50ms تستهلك وحدة المعالجة بدون داع.

### PERF-4: تكرار قفل/فتح mutex في `discover_inner`
**الموقع:** `daemon/external_tools/mod.rs:49-56`  
**الوصف:** يتم فتح `registry` ثم فتح `resolver` بشكل منفصل بدلاً من الاحتفاظ بهما معًا.

### PERF-5: `block_in_place` + `block_on` في `installer.rs`
**الموقع:** `daemon/external_tools/installer.rs:52-53`  
**الوصف:** استخدام `block_in_place` + `handle.block_on()` لطلبات HTTP — يمكن استخدام `reqwest::blocking` مباشرة.

---

## مشاكل أمان الشبكة

### SEC-1: مسار التحقق من SSRF غير مكتمل
**الموقع:** `daemon/utils.rs`  
**الوصف:** `is_safe_target_url` يتحقق من العناوين الخاصة ولكن قد لا يغطي جميع حالات DNS rebinding.

### SEC-2: كشف مسار الملف في رسائل الخطأ
**الموقع:** `daemon/routes/downloads.rs`، `daemon/telegram.rs:516-518`  
**الوصف:** رسائل الخطأ تكشف مسارات النظام (`path.to_string_lossy()`).

### SEC-3: استخدام URL غير محقق في `telegram_api_url`
**الموقع:** `daemon/telegram.rs:113-117`  
**الوصف:** `normalize_api_base` يقوم بالتحقق، ولكن إذا فشل فإنه يعود إلى الـ URL الافتراضي بدلاً من إرجاع خطأ.

### SEC-4: `serde_json::from_str` في `ytdlp_probe_for_analyze` بدون حد للحجم
**الموقع:** `daemon/routes/extension.rs:1211`  
**الوصف:** يمكن أن يتسبب تحليل JSON خبيث في استهلاك ذاكرة غير محدود.

---

## مشاكل libcurl (FFI الخام)

### CURL-1: `CString::new()` مع `unwrap()` ← panic على URL يحتوي NUL
**الموقع:** `daemon/curl/easy_config.rs` — دوال `setopt_raw_str/ptr`

### CURL-2: `curl_easy_setopt` يمكن أن يفشل بصمت
**الموقع:** `daemon/curl/easy_config.rs`  
**الوصف:** دوال `setopt_*` لا تتحقق من كود الخطأ CURLcode في معظم الحالات.

### CURL-3: لا يوجد معالج لأخطاء `curl_multi_info_read`
**الموقع:** `daemon/curl/multi.rs`  
**الوصف:** قراءة رسائل الخطأ من multi handle بدون تحقق من كود CURLMsg.

### CURL-4: `curl_share_handle` بدون تكوين
**الموقع:** `daemon/curl/mod.rs`  
**الوصف:** يتم إنشاء share handle ولكن لا يتم تكوين مشاركة DNS/SSL session.

### CURL-5: عدم استخدام HTTP/2 أو HTTP/3
**الموقع:** `daemon/curl/easy_config.rs`  
**الوصف:** لم يتم تعيين `CURLOPT_HTTP_VERSION` ← سيستخدم HTTP/1.1 افتراضيًا.

---

## مشاكل معمارية

### ARCH-1: وحدتان تكيفيتان منفصلتان غير متصلتين
- `daemon/engine/adaptive/` و `daemon/adaptive/` — نسختان منفصلتان من نظام التحميل التكيفي، كلتاهما `#[allow(dead_code)]`
- لا يوجد كود يربط أيًا منهما بمحرك التحميل الفعلي

### ARCH-2: ازدواجية تامة بين `engine/adaptive/` و `adaptive/`
- كلا الوحدتين تحتويان على ملفات متطابقة وظيفيًا:
  - `segment_controller.rs` في كليهما
  - `buffer_manager.rs` في engine/adaptive فقط
  - `disk_writer.rs` في engine/adaptive فقط
  - `convergence.rs` في engine/adaptive فقط
  - إلخ.

### ARCH-3: `EngineState` ← `AppState` هرمية أحادية
- معظم الأنظمة (`SharedState`) تعيش في `Arc<Mutex<...>>` واحدة → قفل واحد يمنع النظام بأكمله
- لا يوجد تقسيم إلى أقفال دقيقة (fine-grained locks)

### ARCH-4: جهازي استراتيجية منفصلين
- `resource_intelligence/strategy.rs` يحلل الاستراتيجية الموصى بها
- `engine/adaptive_connections.rs` يحسب الاتصالات التكيفية
- `policy_engine.rs` يتخذ القرارات النهائية
- لا يوجد تنسيق بين الثلاثة

### ARCH-5: `PluginApi` مع `api_version` ثابتة
**الموقع:** `daemon/engine/plugin_api.rs:49`  
**الوصف:** نسخة API مثبتة كسلسلة نصية (`"1.0.0"`) — لا يوجد تحقق فعلي من التوافق.

---

## تضخم الكود والازدواجية

### DUP-1: ملفان `segment_controller.rs`
- `daemon/engine/adaptive/segment_controller.rs` (347 سطرًا)
- `daemon/adaptive/segment_controller.rs` (~300 سطر)
- كود متطابق وظيفيًا مع `#[allow(dead_code)]` على كليهما

### DUP-2: `hidden_command` و `hidden_output` مكرران
- `daemon/routes/common.rs:20-30` — `hidden_command()` و `hidden_output()`
- `daemon/external_tools/process.rs:24-29` — نفس النمط

### DUP-3: `hex_pair_to_byte` محدد محليًا
**الموقع:** `daemon/routes/common.rs:348-358`  
**الوصف:** يوجد `hex_pair_to_byte` محلي في `common.rs` بدلاً من مكتبة قياسية (`hex` crate).

---

## خرائط التدفق

### خريطة تدفق تنفيذ الخادم

```
main.rs
  └─ panic_hook()
  └─ config file → EngineConfig (OnceLock)
  └─ lib.rs::run()
       ├─ port_scan() → find_available_port()
       ├─ daemon::setup_server()
       │    ├─ AppState::new()
       │    │    ├─ BandwidthManager, MetadataCache, ExtractorRegistry
       │    │    ├─ ExternalToolManager (ffmpeg + yt-dlp)
       │    │    ├─ ProfileManager (4 builtins)
       │    │    ├─ ResourceIntelligenceEngine
       │    │    ├─ DownloadRuleEngine
       │    │    └─ PluginApi
       │    ├─ register_routes()
       │    │    ├─ /api/downloads/* (CRUD)
       │    │    ├─ /api/engine/* (capabilities, mirrors, rules)
       │    │    ├─ /api/probes/* (HEAD/GET probes)
       │    │    ├─ /api/diagnostics
       │    │    ├─ /api/dns/ping-all
       │    │    ├─ /api/telegram/*
       │    │    ├─ /api/external-tools/*
       │    │    ├─ /api/browser-extension/*
       │    │    ├─ /v1/* (protocol v1 for extension)
       │    │    └─ /* (SPA fallback)
       │    ├─ start_telegram_bot() [blocking thread]
       │    └─ scheduler loop [blocking thread]
       └─ axum::serve() on found port
```

### خريطة تدفق التحميل (Download Lifecycle)

```
HTTP POST /api/downloads
  │
  ├─ download_body 검증
  ├─ extractor_registry.validate() → curl / yt-dlp
  │
  ├─ [curl] create_curl_task()
  │    ├─ DirectDownloadPlan (url, segments, config)
  │    ├─ CurlMultiGuard 생성 (multi handle)
  │    ├─ CurlTransferConfig (proxy, TLS, speed)
  │    ├─ curl_multi_add_handle() for each segment
  │    ├─ event_bus → "download.added"
  │    └─ Task struct { status: "downloading", ... }
  │
  ├─ transfer loop (CurlMultiGuard::poll)
  │    ├─ curl_multi_perform()
  │    ├─ curl_multi_info_read() → completed/failed
  │    ├─ progress callback → downloaded_bytes
  │    ├─ disk_writer (direct I/O — no buffering)
  │    ├─ retry loop (max_retries, backoff, jitter)
  │    └─ event_bus → "download.progress"
  │
  └─ [complete]
       ├─ checksum verify (SHA256/SHA1/MD5)
       ├─ merge segments (if segmented)
       ├─ event_bus → "download.completed"
       └─ task.status = "completed"

Hooks:
  ├─ Pause: curl_multi_pause → task.status = "paused"
  ├─ Resume: curl_multi_resume → task.status = "downloading"
  └─ Cancel: curl_multi_remove_handle → task.status = "cancelled"
```

### خريطة تبعيات الوحدات

```
  main.rs
    └─ lib.rs
         ├─ daemon/mod.rs
         │    ├─ state.rs ──────────────────────────────┐
         │    ├─ types.rs ←─────────────────────────────┤
         │    ├─ utils.rs ←─────────────────────────────┤
         │    ├─ direct.rs → libcurl FFI                │
         │    ├─ diagnostics.rs                         │
         │    ├─ engine_capabilities.rs                 │
         │    ├─ telegram.rs → curl module              │
         │    ├─ ytdlp.rs                               │
         │    ├─ persist.rs                             │
         │    ├─ curl/ ─────────────────────────────────┤
         │    │    ├─ easy_config.rs → raw libcurl FFI  │
         │    │    ├─ transfer_config.rs                 │
         │    │    ├─ transfer.rs                        │
         │    │    ├─ multi.rs                           │
         │    │    ├─ task_api.rs                        │
         │    │    └─ args.rs                            │
         │    ├─ engine/ ───────────────────────────────┤
         │    │    ├─ config.rs (OnceLock)               │
         │    │    ├─ bandwidth.rs                       │
         │    │    ├─ scheduler.rs                       │
         │    │    ├─ event_bus.rs                       │
         │    │    ├─ {chunk_manager, die_orchestrator}  │
         │    │    │    ← DEAD CODE                      │
         │    │    ├─ {rules, profiles, extractor}       │
         │    │    ├─ {retry, priority_queue, checksum}  │
         │    │    ├─ {mirror, self_healing}             │
         │    │    └─ adaptive/ ← DEAD CODE             │
         │    ├─ adaptive/ ← DUPLICATE DEAD CODE        │
         │    │    └─ profile_store.rs                   │
         │    ├─ resource_intelligence/ ────────────────┤
         │    │    ├─ mod.rs (3-stage pipeline)          │
         │    │    └─ url_intel.rs                       │
         │    ├─ routes/ ───────────────────────────────┤
         │    │    ├─ downloads.rs (CRUD + SSE)          │
         │    │    ├─ engine.rs (capabilities)           │
         │    │    ├─ probes.rs (HEAD/GET)               │
         │    │    ├─ diagnostics.rs                     │
         │    │    ├─ extension.rs (v1 protocol)         │
         │    │    └─ external_tools (API endpoints)     │
         │    └─ external_tools/ ────────────────────────┤
         │         ├─ mod.rs (ExternalToolManager)        │
         │         ├─ discovery.rs, health.rs             │
         │         ├─ installer.rs, registry.rs           │
         │         └─ tools/{ffmpeg, yt_dlp}.rs          │
         └─ native_host.rs
```

---

## قائمة الأولويات للتصليح

### فوري (P0) — يمنع التشغيل أو يسبب أعطالًا

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P0-1 | `easy_config.rs` | `CString::new(url).unwrap()` ← panic على NUL bytes | استبدال بـ `CString::new(url).map_err()` |
| P0-2 | `resource_manager.rs:85` | `unsafe` بدون تحقق من قيم الهيكل | إضافة تحقق من `dw_length` ودالة آمنة |
| P0-3 | `profiles.rs:203-214` | ترتيب قفل غير متناسق | توحيد ترتيب الأقفال عبر ProfileManager بأكمله |

### عالي (P1) — يسبب مشاكل في الإنتاج

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P1-1 | `adaptive/*.rs` + `engine/adaptive/*.rs` | 18 ملف كود ميت مكرر | حذف النسخة المكررة (`adaptive/`)، توصيل `engine/adaptive/` بالتدفق الفعلي OR حذف الكل |
| P1-2 | `chunk_manager.rs`, `die_orchestrator.rs` | ~300 سطر كود ميت | حذف الملفين بالكامل |
| P1-3 | `curl/easy_config.rs` | `setopt_*` بدون تحقق من CURLcode | إضافة معالجة أخطاء |
| P1-4 | `curl/multi.rs` | `curl_multi_info_read` بدون تحقق | إضافة معالجة رسائل الخطأ |
| P1-5 | `routes/extension.rs:1211` | JSON parse بدون حد للحجم | استخدام `serde_json::from_reader` مع حد |

### متوسط (P2) — يحسن الاستقرار والأداء

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P2-1 | `engine/mod.rs` | وحدة التكيف (adaptive) غير متصلة بالتدفق | ربط AdaptiveEngine مع CurlMultiGuard |
| P2-2 | `routes/common.rs:48-70` | Busy-wait في `hidden_output_timed` | استبدال بـ `std::sync::mpsc` + child wait |
| P2-3 | `thread_pool.rs:41` | Atomic `Relaxed` | استخدام `Acquire`/`Release` لضمان الرؤية |
| P2-4 | `external_tools/installer.rs` | `block_in_place` + `block_on` | استخدام `reqwest::blocking` مباشرة |
| P2-5 | `telegram.rs:449-454` | قفل مباشر لـ Mutex | استخدام `lock_or_err!` |
| P2-6 | `rules.rs:75-77` | `regex::Regex::new(pattern).ok()` يفشل بصمت | تسجيل تحذير عند فشل compile الـ regex |

### منخفض (P3) — تحسينات نظافة الكود

| # | الموقع | المشكلة | الإجراء |
|---|--------|---------|---------|
| P3-1 | `routes/common.rs:348` | `hex_pair_to_byte` مكرر | استيراد من crate `hex` |
| P3-2 | `types.rs:226-244` | `InstallProgress` و `InstallPhase` و `ToolSource` و `PlatformPattern` مع `#[allow(dead_code)]` | حذف أو توصيل |
| P3-3 | `resource_intelligence/retry_intel.rs` | `retry_decisions` غير مستخدم | حذف الحقل |
| P3-4 | `engine_capabilities.rs` | تخزين مؤقت للنتائج | إضافة `OnceLock` أو `MetadataCache` |
| P3-5 | `diagnostics.rs:134-211` | `test_ssl_cert` لا يعمل على Windows بشكل موثوق | تحسين أو إزالة |

---

## ملخص إحصائي

| الفئة | العدد | الخطورة |
|-------|-------|---------|
| كود ميت (ملفات كاملة) | 3 وحدات (~18 ملف) | عالية — يضلل المطورين ويصعب الصيانة |
| كود ميت (دوال/حقول) | 25+ | متوسطة |
| مشاكل تزامن | 5 | 1 عالية، 2 متوسطة، 2 منخفضة |
| مشاكل libcurl FFI | 5 | 2 عالية، 3 متوسطة |
| مشاكل أمان | 4 | متوسطة |
| مشاكل أداء | 5 | متوسطة |
| ازدواجية | 3 | متوسطة |
| مشاكل معمارية | 5 | عالية |

**التقدير الإجمالي:** ~40% من قاعدة الكود إما كود ميت أو مكرر. النظام يعمل حاليًا عبر curl module + yt-dlp module فقط — جميع الأنظمة التكيفية والاستخبارية غير متصلة.

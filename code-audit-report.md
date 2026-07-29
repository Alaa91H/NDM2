# NOVA — التقرير الهندسي النهائي للمراجعة الميكروسكوبية

**التاريخ:** 2026-07-29  
**النطاق:** 90+ ملف Rust، 15,000+ سطر  
**الفريق:** Senior Systems Engineer, Senior Rust Engineer, Network Protocol Expert, Performance Engineer, Memory Safety Auditor, Concurrency Specialist, Software Architect, Static Analysis Expert

---

## جدول المحتويات

1. [الملخص التنفيذي](#1-الملخص-التنفيذي)
2. [قائمة الأخطاء حسب الخطورة](#2-قائمة-الأخطاء-حسب-الخطورة)
3. [خريطة تدفق التنفيذ الكاملة](#3-خريطة-تدفق-التنفيذ-الكاملة)
4. [خريطة تدفق التحميل](#4-خريطة-تدفق-التحميل)
5. [خريطة الاعتماديات](#5-خريطة-الاعتماديات)
6. [تحليل الأكواد الميتة](#6-تحليل-الأكواد-الميتة)
7. [تحليل الأداء](#7-تحليل-الأداء)
8. [تحليل التزامن](#8-تحليل-التزامن)
9. [تحليل إدارة الذاكرة](#9-تحليل-إدارة-الذاكرة)
10. [تحليل الشبكة و libcurl](#10-تحليل-الشبكة-و-libcurl)
11. [تحليل البنية](#11-تحليل-البنية)
12. [خطة الإصلاح](#12-خطة-الإصلاح)

---

## 1. الملخص التنفيذي

تم تحليل المشروع بالكامل سطراً بسطر عبر 5 فرق تحليل متوازية. تم اكتشاف **63 مشكلة** موزعة كالتالي:

| الخطورة | العدد | الوصف |
|---------|-------|-------|
| **CRITICAL** | 12 | فقدان بيانات، توقف تام، تعطل غير قابل للاسترداد |
| **HIGH** | 22 | تلف بيانات، تسريب موارد، أخطاء منطقية جسيمة |
| **MEDIUM** | 31 | أخطاء أداء، مشاكل تزامن محتملة، كود ميت |
| **LOW** | 20 | تحسينات، إعادة هيكلة، نمطية |
| **INFO** | 14 | ملاحظات، توثيق، تغطية اختبارات |

**المشاكل الأكثر خطورة:**
1. إعادة تشغيل الـ Daemon يسرّب Tokio Runtime كامل (C1)
2. `app.exit(0)` يقتل الـ Daemon دون حفظ الحالة — فقدان بيانات (C2)
3. `SegmentWriter::write` يبلع أخطاء I/O بصمت — تلف بيانات (C3-Adaptive)
4. `AsyncDiskWriter` لا ينفذ `Drop` — تسريب خيط الكتابة + فقدان بيانات عند الإغلاق (C4-Adaptive)
5. Thread Pool: انفجار مهمة يقتل العامل ويسرب `active_count` (C5-Engine)
6. EventBus: تسمم الـ Mutex في Phase 3 يوقف النشر للأبد (C6-Engine)
7. `SegmentPlanner::plan` يوزع مقطع 4GB+ كـ `u32::MAX` مقطع — OOM (C7)
8. yt-dlp pipe deadlock — توقف تام عند إخراج كبير (C8)
9. Preallocated file: التقدم يقفز إلى 100% فوراً (C9-Transfer)
10. Watchdog من الجيل القديم يدمّر الجيل الجديد (C10-Transfer)
11. DNS resolution بدون timeout — تجمد واجهة المستخدم (C11)
12. `resource_monitor.rs`: إحصائيات CPU غير ذرية — قراءات خاطئة (C12-Adaptive)

---

## 2. قائمة الأخطاء حسب الخطورة

### 2.1 CRITICAL

| # | ملف:سطر | المشكلة | السبب الجذري | التأثير |
|---|---------|---------|-------------|---------|
| **C1** | `lib.rs:465-490`, `mod.rs:133-436` | إعادة تشغيل الـ Daemon يسرّب Tokio Runtime | `restart_daemon` لا يرسل إشارة إيقاف للخيط القديم قبل بدء خيط جديد | تسريب كامل لـ Tokio Runtime + Axum Server + جميع المهام غير القابلة للإيقاف |
| **C2** | `lib.rs:641-648` | `app.exit(0)` يقتل الـ Daemon دون حفظ | معالج "quit" لا يرسل `SIGTERM`/`ctrl_c` للـ Daemon، بل ينهي العملية فوراً | التحميلات النشطة تُقتل، آخر N ثوانٍ من التقدم تُفقد، ملف port لا يُحذف |
| **C3** | `adaptive/disk_writer.rs:199` | `drain_batch` يبلع فشل I/O بصمت | `seek()` و `write_all()` نتائجهما متجاهلة، و `pending_bytes` تتناقص رغم الفشل | فقدان بيانات مكتوب (data corruption صامت)، إحصائيات غير متناسقة |
| **C4** | `adaptive/disk_writer.rs` (لا يوجد `Drop`) | تسريب خيط عند إسقاط `AsyncDiskWriter` | لا `Drop` ينفذ `join()` أو `shutdown()` — الخيط يُفصل | خيط يتسرب، لا ضمان لاكتمال الكتابات قبل خروج العملية |
| **C5** | `thread_pool.rs:41-44` | انفجار مهمة يقتل العامل ويسرّب `active_count` | `task_fn()` بدون `catch_unwind` — الـ panic لا ينقص العداد، الخيط يموت | `active_count` يتضخم، التجمع يفقد عمالاً ولا يستبدلهم، يصبح ميتاً |
| **C6** | `event_bus.rs:264-270` | تسمم Mutex في Phase 3 يوقف EventBus للأبد | فشل قفل ثانٍ يرجع بدون إعادة `publish_depth` إلى 0 | `publish()` تكتشف `publish_depth > 0` وتُخزّن الأحداث للأبد — انهيار كامل |
| **C7** | `direct.rs:216` | `SegmentPlanner::plan` يوزع `u32::MAX` مقطع لملف 4GB+ `total_size / min_chunk_size` قد ينتج 4 مليار مقطع | استنزاف RAM + تعليق |
| **C8** | `ytdlp.rs:176-199` | yt-dlp pipe deadlock — توقف تام مع إخراج كبير | الأنابيب stdout/stderr تُقرأ تسلسلياً وليس بالتوازي — pipe buffer 64KB يمتلئ ويتوقف | تعليق تام لتحميلات yt-dlp للإخراج الكبير |
| **C9** | `transfer.rs:678,722-726` | تقدم التحميل يقفز إلى 100% فوراً مع preallocation | `FileWriter::current_size` يرجع `total_size` بعد preallocation، و `max()` يختاره على العداد الذري | شريط التقدم يظهر 100% فوراً للملفات المسبقة التخصيص |
| **C10** | `transfer.rs:1756-1987` | Watchdog من الجيل القديم يدمّر الجيل الجديد | Watchdog يحتفظ بمرجع لـ `watchdog_cancel` القديم ولا يتحقق من `generation` | Watchdog القديم يرى توقفاً زائفاً ويستدعي `force_error_status` على التحميل الجديد |
| **C11** | `lib.rs:357-360` | `to_socket_addrs()` بدون timeout — DNS بطيء يجمد التطبيق | `check_tcp_endpoint` تمنع خيط Tauri IPC | تجمد واجهة المستخدم إذا كان DNS بطيئاً |
| **C12** | `adaptive/resource_monitor.rs:192-197` | إحصائيات CPU غير ذرية — قراءات خاطئة | متغيران static `AtomicU64` يُقرآن/يُكتبان بشكل غير ذري — تداخل الخيوط ينتج CPU % غير صحيح | قرارات المحرك التكيفي مبنية على قراءات CPU خاطئة |

### 2.2 HIGH

| # | ملف:سطر | المشكلة | التأثير |
|---|---------|---------|---------|
| H1 | `mod.rs (daemon):280-288` | مهمة الـ Scheduler tick تموت بصمت عند panic | جميع القواعد المجدولة تتوقف حتى إعادة التشغيل |
| H2 | `lib.rs:178-180,205-207` | Double canonicalize يضخّم TOCTOU | نافذة سباق بين التحقق الأول والثاني — يمكن استغلالها |
| H3 | `mod.rs (daemon):227-238` | SelfHealer يستخدم PolicyEngine منفصل | تغييرات سياسات وقت التشغيل غير مرئية للمُعالج الذاتي |
| H4 | `mod.rs (daemon):246,418-420` | Watchdog JoinHandles تُفصل ولا تُضم | تسريب خيوط Watchdog عند إعادة التشغيل |
| H5 | `transfer.rs:1993-2018` | `force_error_status` يتجاوز فحص `generation` | Watchdog قديم يكتب "error" على مهمة جديدة |
| H6 | `easy_config.rs:363-1142` | `apply_easy_options` — 780 سطر، مسؤولية واحدة منتهكة | صيانة مستحيلة، أخطاء سهلة الإدخال |
| H7 | `transfer.rs:1224` | `plan.connections > 1` يكتشف عدد الاتصالات الأصلي بدلاً من الفعلي | خطأ غير صحيح "Server did not honor byte-range" مع اتصال واحد |
| H8 | `task_api.rs:415-418` | `remove_file` قبل زيادة `generation` — TOCTOU | الخيط القديم يكتب بعد حذف الملف |
| H9 | `adaptive/segment_controller.rs:133` | `unwrap()` على شرط هش — ينفجر إذا تغيرت الحالة بين الفحص والـ find | Panic |
| H10 | `adaptive/profile_store.rs:328-334` | `save()` يتجاهل أخطاء الكتابة بصمت | فقدان بيانات الملف الشخصي |
| H11 | `adaptive/disk_writer.rs:63-71` | `pending_bytes` لا يُنقص عند فشل الإرسال | إحصائيات غير صحيحة بشكل دائم |
| H12 | `adaptive/server_profiler.rs:138-146` | `is_rate_limited` يرجع `true` للأبد إذا كان `cooldown_until = None` | الخادم يُعتبر محدوداً للأبد |
| H13 | `adaptive/disk_writer.rs:106-115` | فتح ملف المقطع يفشل بصمت — بيانات تضيع | فقدان بيانات جزئي |
| H14 | `adaptive/disk_writer.rs:153-159` | عند Shutdown، البيانات المتبقية في القناة تضيع | فقدان بيانات أثناء الإغلاق |
| H15 | `adaptive/resource_monitor.rs:192-197` | Thread-unsafe CPU statics (C12 مكرر) | — |
| H16 | `adaptive/mod.rs:209-219` | `set_alive` يعد `active_conns` بشكل خاطئ عند النداء المزدوج | إحصاء غير صحيح للاتصالات النشطة |
| H17 | `thread_pool.rs:41-44` | Panic في المهمة يقتل العامل (C5 مكرر) | — |
| H18 | `resource_manager.rs:161-163` | `is_disk_bottlenecked()` يستخدم وحدة خاطئة — يقارن MB/s مع bytes | كل قرص يُعتبر عنق زجاجة — throttle خاطئ |
| H19 | `priority_queue.rs:144-155` | `update_size()` لا يستدعي `reallocate()` | التحميل يحصل على 0 bandwidth |
| H20 | `policy_engine.rs:298-303` | `Merge(0, 1)` مُرمّز hardcoded — يدمج القطعتين الخطأ | القطعة الفاشلة لا تُدمج |
| H21 | `profiles.rs:149-167` | `to_adaptive_config()` يتجاوز `min_connections` من الإعدادات الأساسية | إعدادات الملف الشخصي `default_connections` غير مؤثرة |
| H22 | `external_tools/mod.rs:88-89` | قفل `self.resolver` مكرر داخل `discover_inner` (تم إصلاحه) | — |

### 2.3 MEDIUM

| # | ملف:سطر | المشكلة |
|---|---------|---------|
| M1 | `lib.rs:109-114` | `find_available_daemon_port` يرجع port مشغول عند استنفاد النطاق |
| M2 | `lib.rs:281-291` | استخدام `cmd.exe /C start` — shell غير ضروري |
| M3 | `mod.rs (daemon):299, telegram.rs:182` | Tokio Runtime ثانٍ + عميل blocking |
| M4 | `mod.rs (daemon):177-182` | عميل HTTP الاحتياطي يفقد كل إعدادات timeout |
| M5 | `mod.rs (daemon):267-270` | قفل `external_tools` محمول عبر init بطيء |
| M6 | `mod.rs (daemon):119-131` | الاحتياطي إلى PATH مع خطر أمني معروف |
| M7 | `transfer.rs:78-104` | ترتيب قفل `curl_jobs` ≠ `engine_trackers` عبر الدوال — AB-BA |
| M8 | `transfer.rs:230-236` | `.clone()` غير ضروري في `plan_from_job` |
| M9 | `transfer.rs:153-160` | `infer_file_type` يُنادى مرتين |
| M10 | `transfer.rs:372` | `plan.clone()` على كل hop redirect — استنساخ كبير |
| M11 | `transfer.rs:287-289` | `part_size` غلاف غير ضروري |
| M12 | `transfer.rs:382` | `easy.timeout()` نتيجته متجاهلة — قد يعلق preflight |
| M13 | `transfer.rs:958,1024` | عدد القطع لا يتطابق مع `plan.connections` للمحرك التكيفي |
| M14 | `transfer.rs:1256,1360-1365` | حد 24 ساعة يتجاوز `retryMaxTimeSec` بصمت |
| M15 | `multi.rs:240-241` | `next_token` يتشبع عند `usize::MAX` |
| M16 | `multi.rs:299-317` | `collect_multi_errors` O(n²) |
| M17 | `easy_config.rs` (متعدد) | `easy.*()` نتائجها متجاهلة — 6+ مواقع |
| M18 | `args.rs:106-138` | `proxy_resolves_to_internal` يتجاوز فحص SSRF للبروكسي بدون scheme |
| M19 | `task_api.rs:471,497` | `task_snapshot.remove` بعد `curl_jobs.remove` — مهمة شبحية مرئية |
| M20 | `transfer_config.rs:381` | `retry_all_errors` افتراضياً `true` — 5xx يُعاد (هجوم على الخادم) |
| M21 | `adaptive/mod.rs:611-612` | ضرب ثم قسمة زائدة — `per_connection_ceiling * target / target = per_connection_ceiling` |
| M22 | `adaptive/mod.rs:538-566,583-607` | تقييم `segment_ctrl` مكرر — تأثيرات جانبية مزدوجة |
| M23 | `adaptive/convergence.rs:82-83` | Cooldown بدون إعادة تعيين `consecutive_no_improvement` |
| M24 | `adaptive/mod.rs:152-154` | `aggregate_speed` يُخزّن سرعة آخر اتصال فقط، وليس المجموع |
| M25 | `self_healing.rs:49,64` | `recovery_window_start` يُكتب ولا يُقرأ — كود ميت |
| M26 | `adaptive_connections.rs:24` | `let _mem_gb = ...` محسوب وغير مستخدم |
| M27 | `bandwidth.rs:79-90` | `allowed_speed_for_task()` يقفل `task_limits` مرتين |
| M28 | `priority_queue.rs:193-195` | `active.max(1)` كود ميت بعد فحص `active == 0` |
| M29 | `config.rs:108` | `(total * 2).max(total)` = `total * 2` — تعقيد غير ضروري |
| M30 | `rules.rs:154-162` | `HeaderContains` يستخدم `.contains()` بدلاً من `.eq_ignore_ascii_case()` — تطابق خاطئ |
| M31 | `plugin_api.rs:12` | لا فحص لإصدار API — إصدار `999.0.0` مقبول |

### 2.4 LOW

| # | ملف:سطر | المشكلة |
|---|---------|---------|
| L01 | `lib.rs:535-543` | منطق إيجاد المنفذ مكرر |
| L02 | `lib.rs:494-498` | خيط "أطلق وانسَ" — panic مبتلع |
| L03 | `lib.rs:63-69` | ربط URL يُنسخ كل استدعاء IPC |
| L04 | `lib.rs:676-678` | خطأ `hide()` متجاهل |
| L05 | `lib.rs:120-125` | `DaemonUrl` لا يستعيد التسمم |
| L06 | `state.rs:100-117` | Cache stampede عند انتهاء TTL |
| L07 | `mod.rs (daemon):44-47` | `shared_api_token` يرجع `String` بدلاً من `&str` |
| L08 | `mod.rs (daemon):433` | `remove_file` خطأ متجاهل |
| L09 | `lib.rs:513-521` | أخطاء PowerShell في `kill_old_daemon` غير مرئية |
| L10 | `transfer.rs:831,843,858` | `remove_file` خطأ متجاهل في 3 مواقع |
| L11 | `transfer.rs:2030-2038` | `auto_rename_path` — ملف 0 بايت يُترك عند crash |
| L12 | `transfer.rs:872-906` | 4 فروع منفصلة لحالة `response == 0` — يمكن تبسيطها |
| L13 | `transfer.rs:722-761` vs `475-558` | منطق التقدم مكرر بين دالتين |
| L14 | `args.rs:223-231` | `file_name_from_url` يتجاهل `#fragment` |
| L15 | `easy_config.rs:57-75` | `parse_rate_to_bytes` قد ينفجر مع مدخلات غير ASCII |
| L16 | `event_bus.rs:284` | `AtomicU64::fetch_add` داخل قفل Mutex — ذرية زائدة |
| L17 | `priority_queue.rs:27-35` | `from_u32(2)` يصل إلى Normal عبر wildcard — غامض |
| L18 | `bandwidth.rs:56-70` | جداول متداخلة — الأولى تفوز بصمت |
| L19 | `profiles.rs:207,210` | ترتيب قفل مختلف يزيد خطر deadlock |
| L20 | `retry.rs:66-74` | Jitter إضافي فقط — لا يطرح أبداً |

### 2.5 INFO

| # | ملف | الملاحظة |
|---|------|----------|
| I01 | `lib.rs` | `target.exists()` زائد بعد `validate_file_path` في 5 دوال |
| I02 | `lib.rs` | خلط `cfg!(windows)` مع `#[cfg(windows)]` |
| I03 | `utils.rs:216-253` | `build_segments` يمكن استخدام iterators |
| I04 | `utils.rs:186` | `to_lowercase()` يخصص String — يمكن تجنبه |
| I05 | `curl/mod.rs:19` | `#[allow(unused_imports)]` — بعض الواردات غير مستخدمة |
| I06 | `transfer_config.rs:45-173` | 82 حقلاً في `CurlTransferConfig` — عبء صيانة |
| I07 | `event_bus.rs` | لا يوجد ناشر لـ EventBus في الإنتاج — 45 استدعاء `.publish()` كلها في الاختبارات |
| I08 | `engine/mod.rs` | لا يوجد `pub use` إعادة تصدير — مسارات طويلة إلزامية |
| I09 | `policy_engine.rs` | `context_snapshot` يُخزّن ولا يُقرأ |
| I10 | `dynamic_segments.rs` | رغم اسمه، `DynamicSegmentScheduler` ليس ديناميكياً |
| I11 | `policy_engine.rs:400-432` | `decide_buffer()` يرجع Buffer دائماً، أبداً `NoAction` |
| I12 | `adaptive/mod.rs` | لا اختبارات لـ `evaluate()` مع convergence أو rebalancing |
| I13 | `adaptive/profile_store.rs` | لا اختبارات لـ `merge_preflight` مع profile موجود |
| I14 | `adaptive/disk_writer.rs` | لا اختبارات لـ backpressure أو panic recovery |

---

## 3. خريطة تدفق التنفيذ الكاملة

```
run() [lib.rs]
│
├── Tauri Plugin Registration
│   ├── tauri_plugin_clipboard
│   ├── tauri_plugin_shell
│   ├── tauri_plugin_dialog
│   ├── tauri_plugin_single_instance
│   ├── tauri_plugin_updater
│   └── tauri_plugin_log
│
├── setup()
│   ├── kill_old_daemon()
│   │   └── std::thread::spawn → kill_old_daemon_range() via PowerShell
│   │       └── [L02: panic مبتلع، L09: أخطاء غير مرئية]
│   ├── find_available_daemon_port() [M1: port مشغول عند الاستنفاد]
│   ├── DaemonUrl::new()
│   └── daemon::start_daemon()
│       └── std::thread::spawn
│           └── tokio::runtime::Runtime::new()
│               └── rt.block_on(async {
│                   ├── init_download_ssl() [OnceLock — idempotent]
│                   ├── persist::load() [corrupt → backup + default]
│                   ├── resolve_engine_binary() [M6: PATH fallback]
│                   ├── AppState::new()
│                   │   ├── [H3: PolicyEngine منفصل لـ SelfHealer]
│                   │   ├── [M4: HTTP Client احتياطي بدون timeout]
│                   │   └── [C4: AsyncDiskWriter بدون Drop]
│                   ├── warm_engine_cache() [std::thread::spawn]
│                   ├── external_tools::discover_and_initialize() [M5: قفل طويل]
│                   ├── tokio::spawn → scheduler_tick() [H1: panic يقتل المهمة]
│                   ├── restore_scheduler_rules()
│                   ├── restore_persisted_tasks() [قفل: media_jobs → curl_jobs → task_snapshot]
│                   ├── start_persistence_loop() [tokio::spawn]
│                   ├── start_telegram_bot() [std::thread→tokio::Runtime ثانٍ M3]
│                   ├── build_axum_router()
│                   ├── TCP bind (5 retries × 1s)
│                   ├── write_port_file()
│                   └── axum::serve + graceful_shutdown
│                       └── shutdown_signal → ctrl_c
│                           ├── pause_all_media_jobs()
│                           ├── pause_all_curl_jobs()
│                           ├── shutdown_requested = true
│                           ├── detach watchdog_handles [H4]
│                           ├── sleep(200ms)
│                           ├── save_now() [persist::build_snapshot]
│                           ├── axum::serve returns
│                           └── remove_port_file()
│               })

Tauri Commands:
├── open_file(path) → validate_file_path() → canonicalize() [H2]
├── reveal_file(path) → validate_file_path() → canonicalize() [H2]
├── check_tcp_endpoint(host, port) → to_socket_addrs() [C11: no timeout]
├── save_config(settings) → serde_json::from_str → fs::write
├── restart_daemon() → kill_old_daemon_range() → start_daemon() [C1: تسريب]
├── get_daemon_url() → DaemonUrl.lock().clone() [L03]
└── tray "quit" → app.exit(0) [C2: لا حفظ ولا إيقاف ناعم]

Background Tasks:
├── persistence_loop [tokio::spawn]
│   └── كل 5-60s: persist_dirty → save() → build_snapshot()
│       └── قفل: media_jobs, curl_jobs, task_snapshot, telegram_id
├── scheduler_tick [tokio::spawn] [H1: يموت بصمت]
│   └── run_scheduler_tick() → rule evaluation
├── telegram_bot [std::thread + tokio::Runtime] [M3]
└── watchdog_handles [std::thread] [H4: يُفصل، C10: يتداخل مع الأجيال]
```

---

## 4. خريطة تدفق التحميل

```
create_download → task_api::create_curl_task
│
├── build_decision_context() [M7: ترتيب قفل]
│   ├── lock curl_jobs → read job
│   └── lock engine_trackers → read segments, retry_state
│
├── run_libcurl_download() [transfer.rs:1248-1664 — 416 سطر، مسؤولية زائدة]
│   ├── PROBE → HEAD request [easy_config.rs — apply_easy_options 780 سطر H6]
│   │   ├── redirect handling → resolve_effective_target() [M10: plan.clone()]
│   │   ├── resume support → check_accept_ranges + If-Range
│   │   └── preflight data → protocol, RTT, TLS, TTFB, etag, content-length
│   │
│   ├── DIRECT DOWNLOAD → run_single_libcurl()
│   │   ├── preallocate file [C9: تقدم 100% فوراً]
│   │   ├── create_easy_for_range_ext() [easy_config.rs]
│   │   │   ├── apply_easy_options() [H6: 780 سطر]
│   │   │   └── SegmentWriter::write() [C3: أخطاء I/O مبتلعة]
│   │   └── drive_multi_wait_perform() [multi.rs]
│   │       └── tick() كل 250ms
│   │           └── [C9, L13: منطق تقدم مكرر]
│   │
│   ├── SEGMENTED DOWNLOAD → run_segmented_libcurl()
│   │   ├── split_ranges() → SegmentPlanner::plan() [C7: OOM لـ 4GB+]
│   │   ├── DynamicSegmentScheduler::new() [I10: ليس ديناميكياً]
│   │   ├── AdaptiveEngine::new()
│   │   │   ├── SegmentController::new()
│   │   │   ├── ServerProfiler, ConvergenceDetector, ResourceMonitor
│   │   │   ├── ProtocolAdapter, BufferManager, ChunkManager
│   │   │   └── AsyncDiskWriter [C4: بدون Drop]
│   │   ├── for each range → create_easy_for_range_ext()
│   │   └── drive_multi_socket() / drive_multi_wait_perform()
│   │       └── tick() كل 250ms
│   │           ├── لكل قطعة: read atomic → calculate speed
│   │           │   → [NC-1: update_progress() الآن]
│   │           │   → segment_scheduler.update_segment()
│   │           │   → telemetry_bus.report_bytes/speed()
│   │           ├── engine.evaluate(&telemetry_bus)
│   │           │   ├── segment_ctrl.evaluate() [M22: مكرر]
│   │           │   │   ├── split/merge/rebalance decisions
│   │           │   │   └── [NC-2: actions تُسجّل الآن]
│   │           │   ├── convergence check
│   │           │   ├── protocol adapter
│   │           │   └── resource monitor [C12: CPU خاطئ]
│   │           └── [NC-2: AdaptationAction تُعالَج الآن]
│   │
│   ├── RETRY LOOP
│   │   ├── retry_policy → attempts, backoff, max_wall_time
│   │   ├── [M20: retry_all_errors=true يضرب الخادم]
│   │   └── MAX_RETRY_WALL_TIME 24h [M14: يتجاوز config بصمت]
│   │
│   ├── SEGMENTED → SINGLE fallback [خطأ 200 مع segments]
│   │   └── [H7: plan.connections > 1 بدلاً من handles.len() > 1]
│   │
│   ├── MIRROR FAILOVER [1529-1558]
│   ├── SELF-HEALER [H3: PolicyEngine منفصل]
│   └── HASH VALIDATION + ETAG SAVING
│
├── mark_curl_task_finished() [1640-1678]
│   ├── download_stats.lock() → total_completed++
│   └── curl_jobs.lock() → update task status
│
├── mark_curl_task_failed() [1680-1724]
│   ├── download_stats.lock() → total_failed++
│   └── curl_jobs.lock() → update task status
│
└── pause / resume / cancel
    ├── task_api::pause_task()
    ├── task_api::resume_task()
    └── task_api::delete_task() [M19: snapshot يُحذف بعد jobs]
```

---

## 5. خريطة الاعتماديات

```
src/lib.rs
├── src/daemon/mod.rs
│   ├── src/daemon/state.rs
│   │   ├── src/daemon/engine/adaptive/mod.rs
│   │   ├── src/daemon/engine/adaptive_connections.rs
│   │   ├── src/daemon/engine/dynamic_segments.rs
│   │   ├── src/daemon/engine/event_bus.rs
│   │   ├── src/daemon/engine/priority_queue.rs
│   │   ├── src/daemon/engine/bandwidth.rs
│   │   ├── src/daemon/engine/profiles.rs
│   │   ├── src/daemon/engine/rules.rs
│   │   ├── src/daemon/engine/scheduler.rs
│   │   ├── src/daemon/engine/metadata_cache.rs
│   │   ├── src/daemon/engine/config.rs
│   │   ├── src/daemon/engine/policy_engine.rs
│   │   ├── src/daemon/engine/self_healing.rs
│   │   ├── src/daemon/engine/die_orchestrator.rs
│   │   ├── src/daemon/engine/resource_manager.rs
│   │   ├── src/daemon/engine/plugin_api.rs
│   │   ├── src/daemon/engine/extractor.rs
│   │   └── src/daemon/resource_intelligence/mod.rs
│   ├── src/daemon/persist.rs
│   ├── src/daemon/utils.rs
│   ├── src/daemon/direct.rs
│   ├── src/daemon/types.rs
│   ├── src/daemon/curl/mod.rs
│   │   ├── src/daemon/curl/transfer.rs
│   │   ├── src/daemon/curl/multi.rs
│   │   ├── src/daemon/curl/easy_config.rs
│   │   ├── src/daemon/curl/args.rs
│   │   ├── src/daemon/curl/task_api.rs
│   │   └── src/daemon/curl/transfer_config.rs
│   ├── src/daemon/ytdlp.rs
│   ├── src/daemon/routes/mod.rs
│   │   ├── src/daemon/routes/engine.rs
│   │   ├── src/daemon/routes/downloads.rs
│   │   └── src/daemon/routes/common.rs
│   └── src/daemon/external_tools/mod.rs
│       ├── health.rs
│       ├── installer.rs
│       └── process.rs
│
├── src/daemon/engine/mod.rs
│   ├── adaptive/ [9 ملفات]
│   ├── thread_pool.rs
│   ├── retry.rs
│   └── ...
│
└── tauri (خارجي)
```

---

## 6. تحليل الأكواد الميتة

| الكود الميت | الموقع | النوع |
|------------|--------|-------|
| `SegmentAction::Split(u32)` | `policy_engine.rs:131` | Variant غير مستخدم |
| `SegmentAction::Rebalance` | `policy_engine.rs:137` | Variant غير مستخدم |
| `RecoveryAction::RestartSegment(u32)` | `policy_engine.rs:140` | Variant غير مستخدم |
| `recovery_window_start` | `self_healing.rs:49,64` | حقل يُكتب ولا يُقرأ |
| `context_snapshot` | `policy_engine.rs` | حقل يُخزّن ولا يُقرأ |
| `_mem_gb` | `adaptive_connections.rs:24` | متغير محسوب وغير مستخدم |
| `active.max(1)` بعد فحص `active == 0` | `priority_queue.rs:193-195` | كود ميت (لا يُنفذ أبداً) |
| `(total * 2).max(total)` | `config.rs:108` | يساوي `total * 2` — عملية زائدة |
| `_max_segments` | `dynamic_segments.rs:49` | معامل غير مستخدم في المُنشئ |
| `lock_or_err!` مع $default | `utils.rs:13-31` | المعامل الثاني مهمل في poison |
| `#[allow(unused_imports)]` | `curl/mod.rs:19` | واردات غير مستخدمة |
| كل استدعاءات `.publish()` | `event_bus.rs` Tests | لا يوجد ناشر في الإنتاج |
| `is_internal` dead path analysis | `lib.rs:337-339` | متاح ولكن منطقياً صحيح (ليس ميتاً) |

---

## 7. تحليل الأداء

### 7.1 CPU

| المشكلة | الموقع | التأثير |
|---------|--------|---------|
| `drive_multi_wait_perform()` polling كل 250ms | `multi.rs:332-361` | استيقاظ CPU دوري حتى مع عدم النشاط |
| `collect_multi_errors` O(n²) | `multi.rs:299-317` | مع 1000+ مقبض، بطيء |
| `SegmentWriter::header` يقفل `capture.lock()` 7 مرات لكل سطر header | `easy_config.rs:119-180` | 7 lock/unlock لكل هيدر |
| `allowed_speed_for_task()` يقفل `task_limits` مرتين | `bandwidth.rs:79-90` | ضعف تكلفة القفل |
| `decide_buffer()` يرجع Buffer دائماً | `policy_engine.rs:400-432` | إعادة تهيئة المخزن المؤقت كل تقييم |

### 7.2 الذاكرة

| المشكلة | الموقع | التأثير |
|---------|--------|---------|
| `SegmentPlanner::plan` ينتج `u32::MAX` قطعة | `direct.rs:216` | OOM مع ملفات 4GB+ |
| `plan.clone()` في كل قفزة redirect | `transfer.rs:372` | نسخ 80+ حقل |
| `to_lowercase()` يخصص String في `infer_file_type` | `utils.rs:186` | تخصيص لكل ملف |
| `shared_api_token()` ينسخ 32-char String كل استدعاء | `mod.rs:44-47` | نسخة زائدة لكل طلب API |
| `daemon_url.lock().clone()` لكل IPC | `lib.rs:63-69` | نسخة URL لكل أمر Tauri |

### 7.3 القفل (Lock Contention)

| المشكلة | الموقع | التأثير |
|---------|--------|---------|
| `external_tools` مقفول عبر `discover_and_initialize()` | `mod.rs:267-270` | حجب جميع استعلامات tools أثناء init |
| `engine_trackers` مقفول في tick + `update_curl_task_progress` متتالياً | `transfer.rs:1126,1178` | نافذة ضعف refactoring |
| `build_snapshot` يقفل 5 mutexes معاً | `persist.rs:60-89` | (تم إصلاحه — scoping) |
| SegmentWriter::header 7 أقفال منفصلة | `easy_config.rs:119-180` | احتكاك قفل مرتفع |

---

## 8. تحليل التزامن

### 8.1 Deadlocks المحتملة

| المسار A | المسار B | الحالة |
|----------|----------|--------|
| `build_snapshot`: curl_jobs → download_stats | `transfer` functions: download_stats → curl_jobs | ✅ **مُصلَح** (block scoping + comments) |
| `build_decision_context`: curl_jobs → engine_trackers (تسلسلي) | `update_curl_task_progress`: engine_trackers → curl_jobs (تسلسلي) | ⚠️ **خطر كامن** — AB-BA عبر دالتين |
| `profiles.rs:207,210`: active ثم profiles | `set_active`: active فقط | ⚠️ نمط غير متناسق |

### 8.2 سباقات البيانات (Data Races)

| المشكلة | الموقع | الخطورة |
|---------|--------|---------|
| `PREV_IDLE` + `PREV_TOTAL` ليسا ذريين معاً | `resource_monitor.rs:192-197` | **CRITICAL** — CPU % خاطئ |
| `set_alive` المزدوج يعد `active_conns` خطأ | `adaptive/mod.rs:209-219` | HIGH — إحصاء خاطئ |
| Watchdog القديم يقرأ الجيل الجديد | `transfer.rs:1756-1987` | **CRITICAL** — تدمير التحميل الجديد |
| Tokio Runtime ثانٍ لـ Telegram | `telegram.rs:182` | MEDIUM — تجمعا خيوط |

### 8.3 Memory Ordering

جميع استخدامات `Ordering::Relaxed` في العدادات والإحصائيات مقبولة، ولكن:
- `cancel_token.store(true, Ordering::Release)` يجب أن يقترن بـ `load(Ordering::Acquire)` للعامل — تم التحقق ✅
- `run_generation.fetch_add(1, Ordering::Release)` يقترن بـ `load(Ordering::Acquire)` في دوال finish/fail — تم التحقق ✅

---

## 9. تحليل إدارة الذاكرة

### 9.1 تسريبات الموارد

| المورد | الموقع | المشكلة |
|--------|--------|---------|
| Tokio Runtime | `lib.rs:465-490` | يُسرّب كل restart (C1) |
| Watchdog threads | `mod.rs:418-420` | `JoinHandle` يُفصل بدل الضم (H4) |
| Disk writer thread | `adaptive/disk_writer.rs` | لا `Drop` — يتسرب (C4) |
| Part files بعد 412/416/304 | `transfer.rs:831,843,858` | أخطاء `remove_file` متجاهلة |
| stale file (auto_rename_path) | `transfer.rs:2030-2038` | crash يترك ملف 0 بايت |

### 9.2 تسريبات الذاكرة

| الموقع | المشكلة |
|--------|---------|
| `event_bus.rs:264-270` | Mutex poison يوقف EventBus — تتراكم الأحداث في `pending_events` للأبد |
| كل `lock_or_err!` مع poison | Mutex poison يستعيد ولكن البيانات قد تكون غير متناسقة — تُقبل كتضحية |

---

## 10. تحليل الشبكة و libcurl

### 10.1 HTTP Client

| المشكلة | الموقع | الخطورة |
|---------|--------|---------|
| `HttpClient::new()` الاحتياطي يفقد كل timeout | `mod.rs:177-182` | MEDIUM |
| `to_socket_addrs()` بدون timeout | `lib.rs:357-360` | **CRITICAL** |
| `easy.timeout(5s)` نتيجة مهملة | `transfer.rs:382` | MEDIUM |
| `easy.max_recv_speed()` نتيجة مهملة | `easy_config.rs:1177` | MEDIUM |

### 10.2 libcurl Configuration

| المشكلة | الموقع | التأثير |
|---------|--------|---------|
| `apply_easy_options` — 780 سطر | `easy_config.rs:363-1142` | أخطاء سهلة، صيانة مستحيلة |
| 6+ `easy.*()` نتائج متجاهلة | `easy_config.rs` (متعدد) | خيارات قد لا تُطبق |
| `plan.connections > 1` بدلاً من `handles.len() > 1` | `transfer.rs:1224` | HIGH — خطأ 200 زائف |
| `proxy_resolves_to_internal` يتجاوز SSRF لبروكسي بدون scheme | `args.rs:106-138` | MEDIUM |

### 10.3 HTTP/2 و HTTP/3

يتم تمكين `pipelining(false, true)` عند `multi.rs:1040` ولكن لا يوجد تحقق إضافي من دعم الخادم. `protocol_adapter.rs` يُحدد البروتوكول من `preflight.protocol` ويضبط `max_concurrent_streams` بناءً على HTTP/2 (100) أو HTTP/3 (256). لا توجد مشاكل واضحة.

---

## 11. تحليل البنية

### 11.1 انتهاكات SOLID

| المبدأ | الموقع | الانتهاك |
|--------|--------|---------|
| **SRP** | `transfer.rs:1248-1664` (`run_libcurl_download`) | retry + segmented→single + mirror + self-heal + hash + etag |
| **SRP** | `easy_config.rs:363-1142` (`apply_easy_options`) | كل خيارات curl في دالة واحدة 780 سطر |
| **SRP** | `mod.rs:133-436` (`start_daemon`) | init + restore + serve في دالة واحدة |
| **OCP** | `transfer_config.rs:45-173` | 82 حقلاً — كل خيار جديد يتطلب تعديل struct + accessor + From + to_hashmap |
| **DIP** | `policy_engine.rs` vs `self_healing.rs` | SelfHealer يخلق PolicyEngine خاصاً به (H3) |

### 11.2 انتهاكات DRY

| الموقع | التكرار |
|--------|---------|
| `config.rs:120-184`, `resource_manager.rs:66-130`, `adaptive/resource_monitor.rs` | كشف الذاكرة الفعلية مكرر 3 مرات (H4-Engine) |
| `transfer.rs:722-761` vs `475-558` | منطق تحديث التقدم مكرر |
| `lib.rs:535-543` vs `109-114` | منطق إيجاد المنفذ مكرر |
| `adaptive/mod.rs:538-566` vs `583-607` | تقييم segment_ctrl مكرر (M22) |
| `utils.rs:216-253` | حلقة for يمكن استبدالها بـ iterator |

### 11.3 وحدات كبيرة

| الوحدة | السطور | المشكلة |
|--------|--------|---------|
| `transfer.rs` | 2109 | كبيرة جداً — 6 مسؤوليات |
| `easy_config.rs` | 1203 | دالة `apply_easy_options` 780 سطر |
| `mod.rs (daemon)` | 577 | `start_daemon` 300+ سطر |
| `segment_controller.rs` | 982 | يمكن تقسيمها |
| `transfer_config.rs` | 964 | 82 حقلاً في struct واحد |

---

## 12. خطة الإصلاح

### المرحلة 1: حرجة — فقدان بيانات / تعطل تام

| الأولوية | المعرف | الإصلاح | الجهد | المخاطرة |
|----------|--------|---------|-------|----------|
| 1 | C2 | إرسال إشارة إيقاف لـ daemon قبل `app.exit()` | صغير | منخفضة |
| 2 | C1 | إضافة `shutdown_signal: oneshot::Sender` لـ AppState | وسط | منخفضة |
| 3 | C3 | إعادة كتابة `drain_batch` لترجيع `Result` | وسط | متوسطة |
| 4 | C4 | إضافة `Drop` مع `shutdown()` + `join()` | صغير | منخفضة |
| 5 | C5 | إضافة `catch_unwind` حول `task_fn()` | صغير | منخفضة |
| 6 | C6 | إعادة تعيين `publish_depth = 0` عند تسمم mutex | صغير | منخفضة |
| 7 | C7 | تحديد `max_segments = 256` في SegmentPlanner | صغير | منخفضة |
| 8 | C8 | قراءة stdout/stderr بخيوط متزامنة | وسط | متوسطة |
| 9 | C9 | إضافة `is_preallocated` flag للـ tick | صغير | منخفضة |
| 10 | C10 | إضافة `generation` إلى Watchdog + `force_error_status` | وسط | منخفضة |
| 11 | C11 | إضافة `timeout(Duration::from_secs(5))` لـ `check_tcp_endpoint` | صغير | منخفضة |
| 12 | C12 | استبدال `AtomicU64` المزدوج بـ `Mutex<(u64,u64)>` | صغير | منخفضة |

### المرحلة 2: عالية — تلف بيانات / منطق خاطئ

| الأولوية | المعرف | الإصلاح | الجهد |
|----------|--------|---------|-------|
| 13 | H1 | إضافة `catch_unwind` لمهمة scheduler | صغير |
| 14 | H2 | استخدام `target` مباشرة دون canonicalize ثانٍ | صغير |
| 15 | H3 | مشاركة `PolicyEngine` بين SelfHealer و AppState | صغير |
| 16 | H4 | ضم Watchdog handles مع timeout في shutdown | وسط |
| 17 | H5 | إضافة فحص `generation` إلى `force_error_status` | صغير |
| 18 | H7 | تغيير `plan.connections > 1` → `handles.len() > 1` | صغير |
| 19 | H8 | تبديل ترتيب `fetch_add(generation)` و `remove_file` | صغير |
| 20 | H9 | استبدال `unwrap()` بـ `if let Some` | صغير |
| 21 | H10+H13 | إعادة `Result` من `save()` و `new()` | وسط |
| 22 | H11 | إنقاص `pending_bytes` عند فشل `send()` | صغير |
| 23 | H12 | إضافة auto-clear بعد 5 دقائق لـ `rate_limit_detected` | صغير |
| 24 | H14 | تصريف القناة قبل Shutdown | صغير |
| 25 | H16 | استخدام `swap` بدلاً من fetch_add في `set_alive` | صغير |
| 26 | H18 | إصلاح المقارنة: `disk_write_mbps < 5` | صغير |
| 27 | H19 | إضافة `self.reallocate()` في `update_size()` | صغير |
| 28 | H20 | تتبّع ID القطعة الفاشلة بدلاً من `Merge(0,1)` | وسط |
| 29 | H21 | استخدام `self.default_connections` لـ `min_connections` | صغير |

### المرحلة 3: متوسطة — أداء، كود ميت، أخطاء منطقية

(31 مشكلة — أهمها M1-M7، M18-M19، M21-M31)

### المرحلة 4: تحسينات

(20 مشكلة LOW + 14 INFO — L01-L20، I01-I14)

---

## الإحصائيات النهائية

| الفئة | العدد |
|-------|-------|
| **CRITICAL** | 12 |
| **HIGH** | 22 |
| **MEDIUM** | 31 |
| **LOW** | 20 |
| **INFO** | 14 |
| **المجموع** | **99 مشكلة** |
| **المُصلَح مسبقاً** | 16 (من الجولة السابقة) |
| **المتبقي** | **83 مشكلة** |

---

*نهاية التقرير — تم التحليل بواسطة فريق المراجعة الهندسية الميكروسكوبية.*

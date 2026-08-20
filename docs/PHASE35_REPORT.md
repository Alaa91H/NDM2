# NDM2 Phase 3.5 — إغلاق الفجوات والتحقق المتكامل

**التاريخ:** 20 أغسطس 2026  
**النطاق:** عميل NDM2 الأصلي فقط، مع استهلاك NOVA Core الحالي بوصفه المصدر الوحيد للحالة والتنفيذ.  
**الحالة:** مكتمل ضمن القدرات التي يثبتها Core وبيئة Linux المتاحة؛ لا توجد مطالبة بتكافؤ متعدد المنصات أو تحقق يدوي من عناصر سطح المكتب غير المتاحة في الجلسة.

> يحافظ هذا الإصدار على React/Tauri كواجهة مرجعية. لا يستبدل محرك التنزيل أو libcurl أو الطابور أو القواعد أو الجدولة أو yt-dlp أو FFmpeg، ولا يفتح مستمع شبكة جديدًا للمتصفح.

## 1. ما اكتمل

أُغلقت فجوة الوسائط بصورة فعلية. ثُبّت `yt-dlp` وجرى اكتشافه مع `FFmpeg` من الـdaemon الحقيقي. كشف الاختبار عيبًا محددًا في دالة Core ذات المهلة: كانت تشغّل العملية دون توصيل `stdout` و`stderr`، ولذلك يعيد `wait_with_output()` مخازن فارغة. التعديل الأدنى في `src-tauri/src/daemon/routes/common.rs` يوصّل المخرجات قبل `spawn` فقط، من دون تغيير عقد API أو منطق المحرك. بعد إعادة البناء، أعاد `/api/ytdlp/probe` صيَغًا فعلية من Archive.org، وأنشأ Core مهمة yt-dlp واكتمل تنزيل ملف OGV حجمه **46,935,223 بايت** إلى القرص.

جرى بناء امتداد Chromium المنتج وإصلاح اعتماد معلن مفقود هو `lucide-react`. ثُبّت Manifest المضيف الأصلي المؤقت باسم `com.nova.downloadmanager` مع origin الامتداد المقيد. تحميل الامتداد في Chromium headless على تنزيل عام أنشأ مهمة Core فعلية بوصف `Browser extension capture via runtime-verified libcurl multi`؛ اكتملت المهمة بحجم **1,048,576 بايت**. كما اختُبر الغلاف الثنائي القياسي لـNative Messaging مباشرةً مع المضيف الأصلي ومسار `/v1/add`، مع auto-pairing والمصادقة القائمة.

تتضمن واجهة NDM2 الآن صفحة وسائط تنفذ probe عبر Core، تعرض الصيغ التي يصدرها yt-dlp فقط، ولا تسمح بالإنشاء حتى اختيار `format_id` مصدره Core. إنشاء المهمة يرسل `mediaOptions` إلى المحوّل الحالي ولا ينفذ yt-dlp داخل الواجهة. توسعت صفحة الأتمتة بمؤلف موجّه ومحرر JSON كامل البنية لقواعد التنزيل وScheduler؛ الحمولة الخام تمر إلى الغلاف `rule` الذي يطلبه Core. يعرض التشخيص قدرات Core والسجل المصفّى وآثار المهمة مع حجب أنماط bearer/token قبل العرض أو النسخ. أضيفت سياسة retry Core إلى الإعدادات، واختبر التبديل بين `conservative` و`default` ثم الاستعادة.

| المجال | المنجز فعليًا | الحد المقصود |
|---|---|---|
| Browser handoff | Chromium → الامتداد → Native Messaging → daemon → Core → تنزيل فعلي | لا مستمع بديل ولا رمز مضمن في الامتداد |
| Media | Probe وصيغ حقيقية وFFmpeg ومهمة yt-dlp وتنزيل حقيقي | لا محرك وسائط داخل NDM2 |
| Rules | قائمة/إضافة/حذف ومؤلف JSON لكل schema مثبت | لا تحديث/enable مزيف لأن Core لا يقدم endpoint لذلك |
| Scheduler | إنشاء/تحديث/تعطيل/حذف مع TimeWindow وBandwidthBelow وQueueEmpty وAllComplete والإجراءات المثبتة | لا recurring-days أو queue-selection أو simultaneous-limit لأنها ليست في SchedulerRule المدقق |
| Settings | سمة/لغة/اتجاه/كثافة وإشعارات محلية، Profile/Bandwidth/Retry Core | لا عناصر بلا أثر |
| Diagnostics | صحة وإحصاء وقدرات وسجل آمن وTask trace | لا tokens أو أسرار في العرض |

## 2. مصفوفة قدرة Core

| الميزة | دعم Core | API | NDM2 | E2E حي | النتيجة |
|---|---:|---:|---:|---:|---|
| Browser handoff | نعم | `/v1/add` وNative Messaging | نعم | نعم | مكتمل على Chromium/Linux |
| Probe الوسائط | نعم | `/api/ytdlp/probe` | نعم | نعم | مكتمل بعد إصلاح capture الأدنى |
| تنـزيل وسائط | نعم | `/api/downloads` مع `mediaOptions` | نعم | نعم | مكتمل من صيغة Core فعلية |
| FFmpeg capability | نعم | `/api/ytdlp/ffmpeg` | نعم | نعم | مكتمل |
| أولوية الطابور | نعم | `/api/engine/queue` | نعم | نعم، في المراحل السابقة | مكتمل |
| ترتيب صفوف يدوي | لا | لا | متعمد عدم التنفيذ | لا ينطبق | غير متاح في Core؛ لا ترتيب محلي مزيف |
| قواعد التنزيل | نعم | `/api/engine/rules` | نعم | نعم | إضافة/تطبيق/حذف مثبتة |
| تحرير أو enable للقواعد | لا | لا | متعمد عدم التنفيذ | لا ينطبق | لا endpoint مدقق |
| Scheduler | نعم | `/api/engine/scheduler` و`/update` | نعم | نعم | إنشاء/تحديث/قائمة/حذف مثبتة |
| Profiles وBandwidth | نعم | مسارات engine/profile القائمة | نعم | نعم، في المراحل السابقة | مكتمل |
| Retry policy | نعم | `/api/engine/retry-policy` | نعم | نعم | conservative ثم default مثبتة |
| سجلات وTask trace | نعم | مسارات التشخيص القائمة | نعم | جزئي آليًا | عرض آمن؛ يلزم فحص بصري يدوي للنسخ |
| Notifications | انتقالات حالة Core موجودة | محلي عبر Qt tray | نعم | آلي جزئي | لا يمكن إثبات توصيل نظام إشعارات في headless |
| System tray | Qt/QSystemTrayIcon | محلي | نعم | آلي جزئي | لا تحقق يدوي من قائمة صينية بلا جلسة سطح مكتب |

المصفوفة المقروءة آليًا موجودة في [`feature-matrix.phase35.json`](feature-matrix.phase35.json).

## 3. دليل E2E الفعلي

| الاختبار | الدليل | النتيجة |
|---|---|---|
| Probe الوسائط | استجاب Core بصيغ Archive.org حقيقية، منها format `0` بحجم 46,935,223 بايت | نجاح |
| تنزيل وسائط | مهمة yt-dlp وصلت `completed`، والملف `/tmp/Big Buck Bunny.ogv` موجود بالحجم نفسه وبصمة SHA-256 مسجلة خلال الاختبار | نجاح |
| Native Messaging | رسالة بطول little-endian إلى `nova --native-host` أعادت `accepted:true` و`taskId` حقيقيًا | نجاح |
| Browser handoff | امتداد Chromium محمّل مع origin مقيد أنشأ مهمة `1Mb.dat` بوصف browser-extension واكتملت بحجم 1 MiB | نجاح |
| Rule matching | قاعدة `HostnameContains(proof.ovh.net) → SetCategory(phase35-ruled)` عُولجت عند إنشاء مهمة حقيقية | نجاح |
| Scheduler lifecycle | TimeWindow + SetBandwidthLimit: إنشاء، تحديث إلى disabled، قراءة ثم حذف عبر المسارات الفعلية | نجاح |
| Retry policy | قراءة policy، تعيين conservative، ثم استعادة default | نجاح |
| NDM2/QML startup | NDM2 اتصل بـdaemon حي في offscreen من دون أخطاء QML | نجاح |
| High DPI startup | 100% و125% و150% و200% من دون خطأ QML | نجاح آلي |

اختبار الاستمرارية لمهمة معلقة أظهر أن المهمة المحددة لم تعد في قائمة daemon بعد إعادة التشغيل في بيئة الاختبار المعزولة؛ لا يُعد ذلك نجاحًا. تُسجّل هذه الملاحظة كقيد يتطلب تحقيقًا مستقلاً في تخزين المهام المعلقة قبل إعلان استمرارية شاملة.

## 4. البناء والانحدار

| التحقق | النتيجة |
|---|---|
| CTest / `NDM2ModelTests` | نجح: 1/1 |
| Rust Core | نجح: 712/712 |
| CMake Debug | نجح |
| CMake Release | نجح |
| تثبيت Release | نجح إلى `dist/bin/NDM2` |
| تحقق Core غير المعدل | التغيير محصور في `common.rs` لتوصيل stdout/stderr؛ موثق في `CORE_CHANGELOG_PHASE35.md` |

## 5. حالة المنصات

| المنصة | البناء | التشغيل | الفحص اليدوي | القيود |
|---|---|---|---|---|
| Linux (Ubuntu sandbox) | ناجح | daemon حي وNDM2 offscreen وChromium headless | جزئي | لا جلسة سطح مكتب حقيقية لصينية النظام/الإشعارات/تخطيط بصري |
| Windows | غير متاح | غير متاح | غير متاح | لا بيئة Windows في هذه الجلسة |
| macOS | غير متاح | غير متاح | غير متاح | لا بيئة macOS في هذه الجلسة |

لا يعني دعم Qt النظري تحققًا متعدد المنصات.

## 6. الأمن

تم التحقق من أن `/api/health` يرفض الطلب بلا bearer token (`401`). يرفض محوّل NDM2 endpoints غير loopback في `CoreAdapter.cpp`. ارتباط Chrome Native Messaging مقيد إلى origin الامتداد المحسوب من المفتاح العام، ولم يُنشأ مستمع شبكة جديد. مسح الملفات المتعقبة لم يجد أنماط مفاتيح AWS أو GitHub أو OpenAI أو private key. لا توجد رموز اختبار ضمن الملفات التي ستُرفع.

## 7. الفجوات المتبقية الفعلية

لا يوفر Core واجهة ترتيب يدوي ثابتة للطابور، لذلك لم تُضف واجهة drag-and-drop وهمية. كما لا يوفر endpoint مدققًا لتحرير القاعدة أو enable/disable؛ NDM2 يعرض هذه الحدود بدل محاكاتها. Scheduler لا يثبت recurring days أو queue selection أو simultaneous download limit في schema الحالي. يحتاج أداء 100/500/1000 سجلًا تاريخيًا مصدره Core حقيقيًا؛ لم يُفبرك dataset لهذه الغاية. ولا يمكن في بيئة headless إثبات عرض Notification أو التفاعل اليدوي مع system tray، ولا التحقق البصري الشامل من RTL/LTR وHigh DPI.

## 8. جاهزية Phase 4

**ليست جاهزة بعد لادعاء Phase 4 كاملة.** المسارات ذات الأولوية (المتصفح والوسائط) أصبحت مثبتة، لكن قبل مرحلة visual excellence ينبغي حسم استمرارية المهمة المعلقة، واختبار يدوي لصينية النظام والإشعارات وRTL/LTR على سطح مكتب حقيقي، وبناء/تشغيل Windows وmacOS، واختبار أداء على تاريخ Core حقيقي واسع. يمكن بدء تحسين بصري محدود بالتوازي، لكن لا ينبغي وصفه بأنه انتقال نهائي إلى Phase 4 حتى إغلاق هذه الأدلة.

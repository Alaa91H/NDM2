# Phase 3.5 — مصفوفة تكافؤ الإعدادات

| الإعداد المرجعي | التصنيف | تنفيذ NDM2 | الأثر القابل للملاحظة |
|---|---|---|---|
| Theme | محلي للتطبيق | مكتمل | يغير سمة Qt المحفوظة |
| Language / RTL | محلي للتطبيق | مكتمل | يغير `layoutDirection` المحفوظ |
| Density | محلي للتطبيق | مكتمل | يغير كثافة الواجهة المحفوظة |
| Notifications | محلي للتطبيق | مكتمل | يضبط استدعاءات إشعارات Qt للحالات القادمة |
| Active profile | Core-backed | مكتمل | يبدل profile Core النشط |
| Global bandwidth | Core-backed | مكتمل | يغير حد bandwidth Core |
| Retry policy | Core-backed | مكتمل في Phase 3.5 | يغير سياسة backoff/retries عبر `/api/engine/retry-policy` |
| Browser extension health | Core-backed، للعرض | مكتمل | يعرض الصحة؛ التثبيت تابع للامتداد/المضيف الأصلي |
| Media tools health | Core-backed، للعرض | مكتمل | يعرض اكتشاف yt-dlp/FFmpeg دون تزييف |
| Log level | Core-backed | مكتمل | يغير مستوى سجل Core |
| Diagnostics / task trace | Core-backed، للعرض | مكتمل | يعرض سجلًا وقدرات وآثارًا مع حجب الأنماط الحساسة |
| Download defaults المتقدمة | Core-backed/Legacy | غير معروض كإعداد عام | لا API عامة مدققة تغطي كل شاشة legacy؛ لا عنصر بلا أثر |
| VPN/Telegram/Backup/reset/أدوات خارجية | Legacy أو قدرة منفصلة | غير معروض | لا يرحّل كتحكم عام حتى يثبت عقد Core القابل للاستهلاك في NDM2 |
| Browser extension installation | متعلق بالمنصة | لا تحكم وهمي | يستخدم manifest والمضيف الأصلي القائم؛ تم اختبار Chromium في Linux |

> لا تُضاف عناصر واجهة من أجل المظهر فقط. كل إعداد معروض في NDM2 إما يغير `QSettings` المحلي أو يستدعي Core موثقًا ومصادقًا عليه.

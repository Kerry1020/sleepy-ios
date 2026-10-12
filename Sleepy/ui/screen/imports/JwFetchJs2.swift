// JwFetchJs2.swift — ← JwWebViewLoginScreen.kt v1.0.60 (WHUT/EAMS5/EAMS5_AHU/BJTU 续集)
//
// 接续 JwFetchJs.swift 的另 4 个 fetch JS 块(分文件避免单文件过大)。
// 桥回调统一 WKScriptMessage postMessage。

import Foundation

// MARK: - WHUT_FETCH_JS(← JwWebViewLoginScreen.kt WHUT_FETCH_JS 原文移植)
//
// 武汉理工大学 (whut.edu.cn, EMAP homeapp 角色机制): 切本科生 appRole → currentUser
// 取学期 → jcjcx.do 做 DM→物理节映射 → wdkbby/cxxszhxqkb.do 主通道, 空时回退
// 旧 kcbcxby/cxxskcb.do。
enum WhutFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('whut.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入武汉理工教务后再点导入'})});
          return;
        }
        var post = function(url, body){
          return fetch(url, {
            method:'POST',
            headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'},
            body: body || '',
            credentials:'include'
          }).then(function(r){ return r.json(); });
        };
        // 0) 切到本科生角色 (EMAP homeapp 角色机制; 值为 WHUT 全站固定的本科生 appRole GUID,
        //    与 iwut 掌上吾理 bachelor-import 一致)。失败不阻断 — 有些账号可能只有单角色。
        fetch('/jwapp/sys/homeapp/api/home/changeAppRole.do?appRole=ef212c48c8f84be79acbd9d81b090f51',
          {method:'POST', credentials:'include', headers:{'Content-Type':'application/x-www-form-urlencoded; charset=UTF-8','X-Requested-With':'XMLHttpRequest'}})
        .catch(function(){})
        .then(function(){
        // 1) 当前学期 (学号在 wdkbby 通道不需要 — 服务端按会话返回本人数据)
        return fetch('/jwapp/sys/homeapp/api/home/currentUser.do', {credentials:'include'})
        .then(function(r){ return r.json(); })
        .then(function(u){
          var d = u.datas || {};
          var xh = d.userId || '';
          var xnxq = (d.welcomeInfo && d.welcomeInfo.xnxqdm) || '';
          if (!xnxq) throw new Error('未取到当前学期, 请确认已登录本科教务');
          // 2) 节次 DM→物理节映射: jcjcx.do 按名称含"节"计数 (中课1/晚课等不带"节"的跳过)。
          //    2026-09 采集包实锤: DM 表 = 1..5,8..12,14..16, 与 fallback 一致。
          var fallbackMap = {"1":1,"2":2,"3":3,"4":4,"5":5,"8":6,"9":7,"10":8,"11":9,"12":10,"14":11,"15":12,"16":13};
          var sectionMap = {};
          var mapReady = post('/jwapp/sys/wdkbby/modules/dzkz/jcjcx.do', '').then(function(j){
            try {
              var rows = (j.datas && j.datas.jcjcx && j.datas.jcjcx.rows) || [];
              var n = 0;
              for (var i = 0; i < rows.length; i++) {
                var mc = String(rows[i].MC || '');
                if (mc.indexOf('节') >= 0) { n += 1; sectionMap[String(rows[i].DM)] = n; }
              }
              if (n < 10) sectionMap = fallbackMap;
            } catch(e) { sectionMap = fallbackMap; }
          }).catch(function(){ sectionMap = fallbackMap; });
          var applyMap = function(rows){
            for (var i = 0; i < rows.length; i++) {
              var r = rows[i];
              if (sectionMap[r.KSJC] != null) r.KSJC = String(sectionMap[r.KSJC]);
              if (sectionMap[r.JSJC] != null) r.JSJC = String(sectionMap[r.JSJC]);
            }
          };
          return mapReady.then(function(){
            // 3) 主通道: wdkbby/学生课程表 cxxszhxqkb.do (2026-09 用户采集包实锤 —
            //    学生"我的课表"页面走这条: POST XNXQDM → datas.cxxszhxqkb.rows[],
            //    字段 KCM/SKXQ/KSJC/JSJC/SKZC 与解析内核同构, KSJC 为 DM 值)。
            //    旧 kcbcxby/cxxskcb.do 是"教室课表"(教师端)微应用, 学生账号常 403/空。
            return post('/jwapp/sys/wdkbby/modules/xskcb/cxxszhxqkb.do', 'XNXQDM=' + encodeURIComponent(xnxq))
            .then(function(k){
              var rows = (k.datas && k.datas.cxxszhxqkb && k.datas.cxxszhxqkb.rows) || [];
              if (rows.length > 0) {
                applyMap(rows);
                window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:JSON.stringify(k), periods:[]})});
                return null;
              }
              // 4) 兜底: 老 kcbcxby/cxxskcb.do 通道 (部分老版本部署仍用它)
              return post('/jwapp/sys/kcbcxby/modules/xskcb/cxxskcb.do', 'XH=' + encodeURIComponent(xh) + '&XNXQDM=' + encodeURIComponent(xnxq))
              .then(function(k2){
                var rows2 = (k2.datas && k2.datas.cxxskcb && k2.datas.cxxskcb.rows) || [];
                if (rows2.length === 0) throw new Error('课表为空: 请确认已在教务"我的课表"页可见本学期课程');
                applyMap(rows2);
                window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:JSON.stringify(k2), periods:[]})});
              });
            });
          });
        });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - EAMS5_FETCH_JS(← JwWebViewLoginScreen.kt EAMS5_FETCH_JS 原文移植)
//
// 合肥工业大学 (jxglstu.hfut.edu.cn) EAMS5: course-table 拿 studentId + semesterId
// → course-table/info 拿 bizTypeId → get-data 拿 lessonIds → POST datum 拿完整课表。
// 显式拦截 one.hfut.edu.cn 门户(只有本周/下周预览, 完整学期在 jxglstu)。
// 兼容 cumtb.edu.cn(中国矿业大学北京, 同 EAMS5 协议族)。
// __EAMS5_PREFIX__ 运行时由 Kotlin 端用 Eams5PathPrefix.compute() 替换。
enum Eams5FetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname === 'one.hfut.edu.cn') {
          // issue #25: 门户 (统一信息门户) 不是教务 — 且 'one.hfut.edu.cn'.indexOf('hfut.edu.cn')
          // >= 0 会误过下方弱包含守卫。显式拦截并引导用户去 jxglstu 教务入口。
          // issue #46 (2026-09): 门户上线了课表预览卡 (/api/operation/course-timetable/search/<n>/<date>,
          // Bearer token, 只有本周+下周), 全学期课表仍只有 jxglstu 的 datum 有 — 拦截策略不变, 文案改准确。
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,
            err:'检测到您在合工大统一信息门户 (one.hfut.edu.cn)。门户里只有本周/下周的课表预览, 完整学期课表请到"我的学校"选择合肥工业大学, 进入 jxglstu 教务系统后再点导入'})});
          return;
        }
        if (location.hostname.indexOf('hfut.edu.cn') < 0 && location.hostname.indexOf('jxglstu') < 0
            && location.hostname.indexOf('ahu.edu.cn') < 0 && location.hostname.indexOf('cumtb.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入合工大教务后再点导入'})});
          return;
        }
        var PREFIX = '__EAMS5_PREFIX__';
        // 合工大当前课表页把当前学期放在 #allSemesters 的 selected option 中，
        // 而不是写成 semesterId=...；没有它时 get-data 会返回 500 (issue #46).
        var extractSemesterId = function(source) {
          var options = source.match(/<option\\b[^>]*>/gi) || [];
          for (var oi = 0; oi < options.length; oi++) {
            if (!/\\bselected(?:\\s*=\\s*["']?selected["']?)?\\b/i.test(options[oi])) continue;
            var selectedValue = options[oi].match(/\\bvalue\\s*=\\s*["']?(\\d+)/i);
            if (selectedValue) return selectedValue[1];
          }
          var explicit = source.match(/semesterId\\s*[=:]\\s*["']?(\\d+)/i);
          if (explicit) return explicit[1];
          return null;
        };
        // 1) GET course-table 拿 studentId (Cookie 已带)。
        //    fetch 默认跟随重定向: 已登录 → /for-std/course-table 重定向到
        //    /for-std/course-table/info/<studentId>, 页面 HTML <script> 段里有
        //    `var studentId = '2024210001';` 或对象字面量 `studentId:'2024210001',`。
        //    未登录 → 重定向到 /eams5-student/login, 页面无 studentId。
        fetch(PREFIX + '/for-std/course-table', {credentials:'include'})
        .then(function(r){
          if (!r.ok) throw new Error('course-table 取 studentId 失败 HTTP ' + r.status + '（请确认已在教务主页登录）');
          return r.text().then(function(html){ return {html: html, finalUrl: r.url || ''}; });
        })
        .then(function(ctx){
          var html = ctx.html || '';
          var extractedSemester = extractSemesterId(html);
          // 检测会话失效: 最终 URL 含 /login (302 落到登录页)
          if (ctx.finalUrl.indexOf('/login') >= 0 || ctx.finalUrl.indexOf('login?') >= 0) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'登录态已失效,请在教务主页重新登录后再试'})});
            return null;
          }
          // 多形态匹配 — 2026-09 用户反馈 + 跨仓验证 (Chiu-xaH/HFUT-Schedule,
          //   JxglstuService.kt:34-41 + JxglstuRepository.kt:60-66)
          // 形如:
          //   var studentId = '2024210001';
          //   studentId: '2024210001',
          //   studentId: 2024210001,
          //   studentId = 2024210001;
          // 抓 group 1 (quoted / numeric), 失败回退更宽 [A-Za-z0-9]+ 兜底学号。
          var m = html.match(/studentId\\s*[:=]\\s*(?:["']([0-9]{6,20})["']|([0-9]{6,20}))/);
          var studentId = '';
          if (m) studentId = m[1] || m[2] || '';
          if (!studentId) {
            var m2 = html.match(/studentId\\s*[:=]\\s*(?:["']([A-Za-z0-9]+)["']|([A-Za-z0-9]+))/);
            if (m2) studentId = m2[1] || m2[2] || '';
          }
          if (!studentId) throw new Error('未取到 studentId: 请确认已在教务主页登录, 且当前域名属于 EAMS5 系列');
          // 2) 拿 bizTypeId: 解析 /for-std/course-table/info/<studentId> HTML
          //    多形态正则覆盖 (参考仓 parseBizTypeId 共识 + issue #46):
          //   bizTypeId: 23,  /  bizTypeId = '23'  /  bizTypeId: '23',
          fetch(PREFIX + '/for-std/course-table/info/' + encodeURIComponent(studentId), {credentials:'include'})
          .then(function(r2){
            if (!r2.ok) throw new Error('course-table/info 取 bizTypeId 失败 HTTP ' + r2.status);
            return r2.text();
          })
          .then(function(infoHtml){
            var bz = infoHtml.match(/bizTypeId\\s*[:=]\\s*(?:["']?(\\d+)/i);
            var bizTypeId = bz ? bz[1] : '23';
            var semesterParam = extractedSemester ? '&semesterId=' + encodeURIComponent(extractedSemester) : '';
            // 3) get-data 拿 lessonIds
            return fetch(PREFIX + '/for-std/course-table/get-data?bizTypeId=' + encodeURIComponent(bizTypeId) +
                         '&dataId=' + encodeURIComponent(studentId) + semesterParam,
                         {credentials:'include'})
            .then(function(r3){
              if (!r3.ok) throw new Error('get-data 取 lessonIds 失败 HTTP ' + r3.status);
              return r3.json().catch(function(){ return null; });
            })
            .then(function(gd){
              var lessonIds = [];
              try {
                if (gd) {
                  if (Array.isArray(gd.lessonIds)) lessonIds = gd.lessonIds;
                  else if (gd.result && Array.isArray(gd.result.lessonIds)) lessonIds = gd.result.lessonIds;
                  else if (Array.isArray(gd.data)) lessonIds = gd.data;
                }
              } catch(e) {}
              // 兜底: lessonIds 为空数组时 datum 仍会 500 (参考仓 JxglstuService.kt:53 注释),
              // 但本 JS 跨 cumtb 共用, 不因 HFUT 异常让其它 EAMS5 校整体失败 — 透传空数组过去。
              var studentIdParam;
              if (/^\\d+$/.test(studentId)) studentIdParam = parseInt(studentId, 10);
              else studentIdParam = studentId;
              // 4) POST datum 拿完整课表
              return fetch(PREFIX + '/ws/schedule-table/datum', {
                method:'POST',
                credentials:'include',
                headers:{'Content-Type':'application/json','X-Requested-With':'XMLHttpRequest'},
                body: JSON.stringify({lessonIds: lessonIds, studentId: studentIdParam, weekIndex: ''})
              }).then(function(r4){
                return r4.text().then(function(txt){
                  if (!r4.ok) throw new Error('datum 接口失败 HTTP ' + r4.status + '（登录态可能已过期, 请刷新重登）');
                  window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({
                    ok:true,
                    data:txt,
                    eams5: {
                      studentId: studentId,
                      bizTypeId: bizTypeId,
                      semesterId: extractedSemester || '',
                      prefix: PREFIX
                    }
                  })});
                });
              });
            });
          });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e && e.message || e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - EAMS5_AHU_FETCH_JS(← JwWebViewLoginScreen.kt EAMS5_AHU_FETCH_JS 原文移植)
//
// 安徽大学 (one.ahu.edu.cn + jxglstu.ahu.edu.cn) EAMS5: 与合工大 EAMS5 协议同源
// 但走 CAS (统一身份认证) — 登录态判定更严: 302 落 /cas/login OR 200 落 CAS 登录页
// (双字段 name="lt" + name="execution")。
enum Eams5AhuFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('ahu.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入安徽大学教务后再点导入'})});
          return;
        }
        var PREFIX = '__EAMS5_PREFIX__';
        // 1) GET course-table HTML, 提取 allSemesters (学期 JSON 数组) + 检测登录态
        fetch(PREFIX + '/for-std/course-table', {credentials:'include', redirect:'follow'})
        .then(function(r){
          // 会话失效判定 (Zeraora client.ts:608-617 + abydym SessionAuthenticator.kt + Landon-3314 isLoginExpired 共识):
          //   1) 302-399 redirect + Location 落到 CAS (/cas/login, one.ahu.edu.cn/cas)
          //   2) 200 OK + HTML 含 'name="lt"' AND 'name="execution"' 双字段 (CAS 登录页)
          //   3) URL 含 casloginform / 统一身份认证 / 请重新登录 (兜底)
          // 5 仓 cross-verified 2026-09-06 (a999c385/aa707ac2033872402 agents)
          var status = r.status;
          var locHeader = r.headers.get('location') || '';
          var isCasRedirect = status >= 300 && status < 400
            && (locHeader.indexOf('one.ahu.edu.cn/cas') >= 0
                || /\\/cas\\/login/.test(locHeader)
                || /\\/cas\\b/.test(locHeader));
          // r.text() 单次消费 — 先一次性读再判
          return r.text().then(function(body){
            // 同时读 r.url, fetch redirect:'follow' 后 finalUrl 是最终 URL (CAS 登录页)
            var finalUrl = r.url || '';
            var hasLtField = /name=["']lt["']/i.test(body);
            var hasExecField = /name=["']execution["']/i.test(body);
            var hasCasLoginUi = /统一身份认证|请重新登录|session timeout|会话已过期|name=["']casloginform["']/i.test(body);
            var loginExpired = finalUrl.indexOf('/login') >= 0
                            || finalUrl.indexOf('cas/login') >= 0
                            || finalUrl.indexOf('one.ahu.edu.cn/cas') >= 0
                            || finalUrl.indexOf('casloginform') >= 0
                            || isCasRedirect
                            || (hasLtField && hasExecField)
                            || hasCasLoginUi;
            return {html: body, finalUrl: finalUrl, status: status, loginExpired: loginExpired};
          });
        })
        .then(function(ctx){
          if (ctx.loginExpired) {
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,
              err:'登录态已失效,请在教务主页重新登录后再试'})});
            return null;
          }
          var html = ctx.html || '';
          // 学期列表提取 — 5 仓共识 (a999c385 agent):
          //   AHU 是 Thymeleaf/J2EE 模板渲染, 学期列表嵌入 HTML 内
          //   `<select id="allSemesters"><option value="112">2024-2025-2</option>...`
          //   qiqqqqq517 ahu.js:37 / abydym CourseRepository.kt:119-167 / Zeraora client.ts:480-489
          var semesterId = null;
          var semesterMatch = html.match(/<select[^>]*id=["']allSemesters["'][^>]*>([\\s\\S]*?)<\\/select>/i);
          if (semesterMatch) {
            var selectedOpt = semesterMatch[1].match(/<option[^>]*\\bselected(?:\\s*=\\s*["']?selected["']?)?[^>]*value=["']?(\\d+)/i);
            if (selectedOpt) semesterId = selectedOpt[1];
            if (!semesterId) {
              var firstOpt = semesterMatch[1].match(/<option[^>]*value=["']?(\\d+)/i);
              if (firstOpt) semesterId = firstOpt[1];
            }
          }
          // 学号提取 (与合工大同多形态)
          var m = html.match(/studentId\\s*[:=]\\s*(?:["']([0-9]{6,20})["']|([0-9]{6,20}))/);
          var studentId = '';
          if (m) studentId = m[1] || m[2] || '';
          if (!studentId) {
            var m2 = html.match(/studentId\\s*[:=]\\s*(?:["']([A-Za-z0-9]+)["']|([A-Za-z0-9]+))/);
            if (m2) studentId = m2[1] || m2[2] || '';
          }
          if (!studentId) throw new Error('未取到 studentId: 请确认已在 AHU 教务主页登录, 且进入"我的课表"页');
          // 2) 拿 bizTypeId
          return fetch(PREFIX + '/for-std/course-table/info/' + encodeURIComponent(studentId), {credentials:'include'})
          .then(function(r2){
            if (!r2.ok) throw new Error('course-table/info 取 bizTypeId 失败 HTTP ' + r2.status);
            return r2.text();
          })
          .then(function(infoHtml){
            var bz = infoHtml.match(/bizTypeId\\s*[:=]\\s*(?:["']?(\\d+)/i);
            var bizTypeId = bz ? bz[1] : '23';
            var semesterParam = semesterId ? '&semesterId=' + encodeURIComponent(semesterId) : '';
            return fetch(PREFIX + '/for-std/course-table/get-data?bizTypeId=' + encodeURIComponent(bizTypeId) +
                         '&dataId=' + encodeURIComponent(studentId) + semesterParam,
                         {credentials:'include'})
            .then(function(r3){
              if (!r3.ok) throw new Error('get-data 取 lessonIds 失败 HTTP ' + r3.status);
              return r3.json().catch(function(){ return null; });
            })
            .then(function(gd){
              var lessonIds = [];
              try {
                if (gd) {
                  if (Array.isArray(gd.lessonIds)) lessonIds = gd.lessonIds;
                  else if (gd.result && Array.isArray(gd.result.lessonIds)) lessonIds = gd.result.lessonIds;
                  else if (Array.isArray(gd.data)) lessonIds = gd.data;
                }
              } catch(e) {}
              var studentIdParam;
              if (/^\\d+$/.test(studentId)) studentIdParam = parseInt(studentId, 10);
              else studentIdParam = studentId;
              return fetch(PREFIX + '/ws/schedule-table/datum', {
                method:'POST',
                credentials:'include',
                headers:{'Content-Type':'application/json','X-Requested-With':'XMLHttpRequest'},
                body: JSON.stringify({lessonIds: lessonIds, studentId: studentIdParam, weekIndex: ''})
              }).then(function(r4){
                return r4.text().then(function(txt){
                  if (!r4.ok) throw new Error('datum 接口失败 HTTP ' + r4.status + '（登录态可能已过期, 请刷新重登）');
                  window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({
                    ok:true,
                    data:txt,
                    eams5: {
                      studentId: studentId,
                      bizTypeId: bizTypeId,
                      semesterId: semesterId || '',
                      prefix: PREFIX
                    }
                  })});
                });
              });
            });
          });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e && e.message || e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - BJTU_FETCH_JS(← JwWebViewLoginScreen.kt BJTU_FETCH_JS 原文移植)
//
// 北京交通大学 (aa.bjtu.edu.cn): 并发取 stuschedule (个人课表) + schedule (含节次时间表) 两页,
// 解析 tr/th 抓节次时间 (第N节+HH:MM-HH:MM), 判登录态 (/client/login/), payload 透传 stuschedule HTML。
enum BjtuFetchJs {
    static let js = """
    (function(){
      function finish(payload) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
      }
      function err(msg) {
        finish({ok:false, err:msg});
      }
      try {
        if (location.hostname.indexOf('bjtu.edu.cn') < 0) {
          err('请先在北京交通大学教务页面 (aa.bjtu.edu.cn) 登录后再点导入');
          return;
        }
        var LABEL_RE = new RegExp('第\\\\s*(\\\\d+)\\\\s*节');
        var TIME_RE = new RegExp('(\\\\d{1,2}:\\\\d{2})\\\\s*[-–—~至]\\\\s*(\\\\d{1,2}:\\\\d{2})');
        function get(path) {
          return fetch(path, {credentials:'include'}).then(function(r){
            return r.text().then(function(body){ return {status: r.status, body: body}; });
          });
        }
        function isLoginExpired(ctx) {
          return (ctx.body || '').indexOf('/client/login/') >= 0 &&
                 (ctx.body || '').indexOf('星期一') < 0;
        }
        function periodsFrom(html) {
          var periods = [];
          try {
            var doc = new DOMParser().parseFromString(html, 'text/html');
            var rows = doc.querySelectorAll('tr');
            var seen = {};
            for (var i = 0; i < rows.length; i++) {
              var cell = rows[i].querySelector('th,td');
              if (!cell) continue;
              var text = cell.textContent || '';
              var lm = text.match(LABEL_RE);
              if (!lm) continue;
              var node = parseInt(lm[1], 10);
              if (seen[node]) continue;
              seen[node] = true;
              var tm = text.match(TIME_RE);
              periods.push({node: node, start: tm ? tm[1] : '', end: tm ? tm[2] : ''});
            }
            periods.sort(function(a,b){ return a.node - b.node; });
          } catch(e) { periods = []; }
          return periods;
        }
        Promise.all([
          get('/course_selection/courseselect/stuschedule/'),
          get('/course_selection/courseselecttask/schedule/')
        ]).then(function(results){
          var stuschedule = results[0];
          var schedule = results[1];
          if (isLoginExpired(stuschedule) || isLoginExpired(schedule)) {
            err('登录态已失效,请在 aa.bjtu.edu.cn 重新登录后再点导入');
            return;
          }
          if (!stuschedule || stuschedule.status !== 200) {
            err('个人课表接口失败 HTTP ' + (stuschedule ? stuschedule.status : 'null'));
            return;
          }
          var periods = periodsFrom(schedule ? schedule.body : '');
          finish({
            ok:true,
            data: stuschedule.body,
            periods: periods
          });
        }).catch(function(e){
          err(String(e && e.message ? e.message : e));
        });
      } catch(error) {
        err(String(error && error.message ? error.message : error));
      }
    })();
    """
}

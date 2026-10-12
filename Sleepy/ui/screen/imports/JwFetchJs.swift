// JwFetchJs.swift — ← JwWebViewLoginScreen.kt v1.0.60 (NUIT/KUST/NEU/YETHAN/CHAOXING/WHUT/EAMS5/EAMS5_AHU/BJTU)
// 教务 WebView 内 fetch 课表 JSON 脚本集合(8 个学校协议, 逐行移植自 v1.0.60)。
// 桥回调统一改 WKScriptMessage postMessage(window.webkit.messageHandlers.__sleepyBridge)。
// 派发入口见 JwWebViewLoginScreen.capture()。

import Foundation

// MARK: - NUIT_FETCH_JS(← JwWebViewLoginScreen.kt NUIT_FETCH_JS 原文移植)
//
// 南开大学 (jwapp 体系) 课表 JSON: currentUser 取学期 → student/courses 拉 JSON。
enum NuitFetchJs {
    static let js = """
    (function(){
      fetch('/jwapp/sys/homeapp/api/home/currentUser.do',{credentials:'include'})
        .then(function(r){return r.json();})
        .then(function(u){
          var term=u&&u.datas&&u.datas.welcomeInfo&&u.datas.welcomeInfo.xnxqdm;
          if(!term) throw new Error('无法识别当前学期');
          return fetch('/jwapp/sys/homeapp/api/home/student/courses.do?termCode='+encodeURIComponent(term),{credentials:'include'});
        })
        .then(function(r){return r.text();})
        .then(function(data){window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true,data:data})});})
        .catch(function(e){window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,err:String(e)})});});
    })();
    """
}

// MARK: - KUST_FETCH_JS(← JwWebViewLoginScreen.kt KUST_FETCH_JS 原文移植)
//
// 昆明理工大学: queryAllTerm 取学期 → queryAWeekSchedule 拉 JSON(列表形态, 见 JwKustParser)。
enum KustFetchJs {
    static let js = """
    (function(){
      fetch('/api/uppcard/kbsz/queryAllTerm',{credentials:'include'})
        .then(function(r){return r.json();})
        .then(function(terms){
          var list=terms&&terms.data||[]; var term=list[0]&&list[0].XNXQ;
          if(!term) throw new Error('无法识别昆明理工学期');
          return fetch('/api/uppcard/kbsz/queryAWeekSchedule?XNXQ='+encodeURIComponent(term),{credentials:'include'});
        })
        .then(function(r){return r.text();})
        .then(function(data){window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true,data:data})});})
        .catch(function(e){window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false,err:String(e)})});});
    })();
    """
}

// MARK: - NEU_FETCH_JS(← JwWebViewLoginScreen.kt NEU_FETCH_JS 原文移植)
//
// 东北大学 (jwxt.neu.edu.cn) 金智新版教务的课表 JSON 抓取。
// 课表页面没有可供 HTML parser 使用的课程数据。登录态下依次取得当前学期、可用校区,
// 再向 getMyScheduleDetail.do 提交表单;返回的 datas.arrangedList 由 JwNeuParser 解析。
//
// 兼容北京航空航天大学新本研教务 (byxt.buaa.edu.cn, 2026-09-19 9 仓 cross-verified):
//   协议层同源(金智 jwapp homeapp family),但 BUAA 在 21/21 仓均 campusCode=""
//   直接 POST 不取校区端点(该端点 byxt 可能不暴露或返回非预期)。按 host 分流,
//   NEU 走完整三步(currentUser → campus → schedule),byxt 走两步
//   (currentUser → schedule, campusCode 留空)。
enum NeuFetchJs {
    static let js = """
    (function(){
      function finish(payload) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(payload)});
      }

      function fetchJson(url, options) {
        var request = Object.assign({credentials:'include'}, options || {});
        return fetch(url, request).then(function(response) {
          return response.text().then(function(body) {
            if (!response.ok) throw new Error('请求失败 HTTP ' + response.status + ': ' + url);
            try {
              return JSON.parse(body);
            } catch (e) {
              throw new Error('接口返回不是 JSON: ' + url);
            }
          });
        });
      }

      // 兼容 NEU + byxt.buaa.edu.cn 同协议族 (金智 jwapp homeapp)
      var NEU_HOSTS = ['jwxt.neu.edu.cn', 'byxt.buaa.edu.cn'];

      try {
        var hostname = (location.hostname || '').toLowerCase();
        var isSupportedHost = NEU_HOSTS.indexOf(hostname) >= 0;
        if (!isSupportedHost) {
          finish({ok:false, err:'请先完成登录并进入教务系统 (东北大学 / 北京航空航天大学新本研) 后再点导入'});
          return;
        }

        // BUAA byxt.buaa.edu.cn: campusCode='' 直接 POST, 不取 getMyScheduledCampus
        //   9 仓实锤 (fontlos/buaa-api + BUAASubnet/UBAA + CoolwindHF/buaa2wakeup +
        //   cantBeFoundGroup/OpenBUAA + el-ev/BUAA-ics-gen + Krignd/KAgenda +
        //   Yiki21/iclass_buaa_tui + Lidozs55/BUAAer + Alyssumira/BUAA-Schedule),
        //   该端点在 byxt 未公开/不返回有效 campus 列表。
        var isBuaaByxt = hostname === 'byxt.buaa.edu.cn';

        fetchJson('/jwapp/sys/homeapp/api/home/currentUser.do')
        .then(function(userData) {
          var termCode = userData && userData.datas && userData.datas.welcomeInfo &&
            userData.datas.welcomeInfo.xnxqdm;
          if (!termCode) throw new Error('当前用户信息中没有学期代码，请重新登录后重试');

          if (isBuaaByxt) {
            var bodyBuaa = 'termCode=' + encodeURIComponent(String(termCode)) +
              '&campusCode=&type=term';
            return fetchJson('/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do', {
              method:'POST',
              headers:{
                'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8',
                'X-Requested-With':'XMLHttpRequest'
              },
              body:bodyBuaa
            });
          }

          return fetchJson(
            '/jwapp/sys/homeapp/api/home/student/getMyScheduledCampus.do?termCode=' +
            encodeURIComponent(String(termCode))
          ).then(function(campusData) {
            var campuses = campusData && campusData.datas;
            var campusCode = Array.isArray(campuses) && campuses[0] && campuses[0].id;
            if (campusCode === undefined || campusCode === null || campusCode === '') {
              throw new Error('当前学期没有可用校区信息');
            }

            var body = 'termCode=' + encodeURIComponent(String(termCode)) +
              '&campusCode=' + encodeURIComponent(String(campusCode)) + '&type=term';
            return fetchJson('/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do', {
              method:'POST',
              headers:{
                'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8',
                'X-Requested-With':'XMLHttpRequest'
              },
              body:body
            });
          });
        })
        .then(function(scheduleData) {
          var arranged = scheduleData && scheduleData.datas && scheduleData.datas.arrangedList;
          if (!Array.isArray(arranged)) throw new Error('课表响应中没有 arrangedList');
          finish({ok:true, data:JSON.stringify(scheduleData)});
        })
        .catch(function(error) {
          finish({ok:false, err:String(error && error.message ? error.message : error)});
        });
      } catch (error) {
        finish({ok:false, err:String(error && error.message ? error.message : error)});
      }
    })();
    """
}

// MARK: - YETHAN_FETCH_JS(← JwWebViewLoginScreen.kt YETHAN_FETCH_JS 原文移植)
//
// 西南交通大学逐专平台 (yhxt.swjtu.edu.cn): localStorage 'ytoken' 鉴权,
// 并发取 student-course-schedule + common-config 两个 JSON 接口。
// 区分微信扫码 / 账号密码登录页(不同错误文案, 2026-09-16 用户复测实锤)。
enum YethanFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname !== 'yhxt.swjtu.edu.cn') {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录西南交通大学逐专平台后再点导入'})});
          return;
        }
        var token = '';
        try { token = localStorage.getItem('ytoken') || ''; } catch(e) {}
        if (!token) {
          // 按页面标记区分卡点 (2026-09-16 用户复测: 微信扫码页点导入, 旧文案不指路):
          //   ① 微信扫码页: 「使用微信扫一扫登录」/「微信登录」入口标记
          //   ② 账号密码页: password 输入框
          //   ③ 其余: 通用文案
          var pageHint = '';
          try {
            var lower = (document.body ? document.body.innerText : '') || '';
            if (lower.indexOf('使用微信扫一扫登录') >= 0 || lower.indexOf('微信登录') >= 0) {
              pageHint = '当前停在微信扫码登录页：请用微信扫码并确认，或点「微信登录」旁的切换按钮改用账号密码登录，登录完成后再点导入';
            } else if (document.querySelector('input[type=\"password\"]')) {
              pageHint = '当前停在账号密码登录页：请输入学号密码和验证码完成登录，登录完成后再点导入';
            }
          } catch(e2) {}
          if (!pageHint) pageHint = '未取到登录凭据，请先登录逐专平台后再点导入';
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:pageHint})});
          return;
        }
        var headers = {Accept:'application/json', 'ytoken':token};
        var get = function(path) {
          return fetch(path, {method:'GET', credentials:'include', headers:headers}).then(function(r) {
            return r.text().then(function(txt) {
              if (!r.ok) throw new Error('HTTP ' + r.status);
              return txt;
            });
          });
        };
        Promise.all([
          get('/yethan/common/course-schedule/student-course-schedule'),
          get('/yethan/common-config')
        ]).then(function(values){
          var schedule = JSON.parse(values[0]);
          var config = JSON.parse(values[1]);
          if (!schedule || (schedule.code !== '00000' && schedule.code !== 0)) {
            var code = schedule && schedule.code ? String(schedule.code) : 'unknown';
            throw new Error('课表接口返回 ' + code + '（登录态可能已过期，请刷新重登）');
          }
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({
            ok:true,
            data:values[0],
            yethanConfig:config
          })});
        }).catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}

// MARK: - CHAOXING_FETCH_JS(← JwWebViewLoginScreen.kt CHAOXING_FETCH_JS 原文移植)
//
// 超星/教务管理 (吉林工商 等 /admin 前缀部署): getMenuList 取学期 → queryKbForGrdb
// 个人课表; 404 HTML 回退 sdpkkbList (需 xhid, 优先级: URL query → HTML → iframe URL)。
// 节次时间 getZclistByXnxq 尽力而为, 失败不阻断。
enum ChaoxingFetchJs {
    static let js = """
    (function(){
      try {
        // 管理前缀按入口 URL 推断: 部分部署挂 /admin 或 /admin/ (吉林工商), 部分无前缀
        // 修复: pathname 可能恰好是 '/admin' (无尾斜杠), 旧逻辑 indexOf('/admin/') === 0 判 false
        var base = /^\\/admin(\\/|$)/.test(location.pathname) ? '/admin' : '';
        var get = function(url){
          return fetch(url, {credentials:'include', headers:{'X-Requested-With':'XMLHttpRequest'}})
            .then(function(r){ return r.json(); });
        };
        var getText = function(url){
          return fetch(url, {credentials:'include', headers:{'X-Requested-With':'XMLHttpRequest'}})
            .then(function(r){ return r.text(); });
        };
        // 1) 当前学期 + 校区: getMenuList 响应含 jsxq.dataXnxq / xqid (session 态)
        var ctx = get(base + '/api/getMenuList').then(function(j){
          var jsxq = (j && (j.jsxq || (j.data && j.data.jsxq))) || {};
          return { xnxq: jsxq.dataXnxq || '', xqid: jsxq.xqid || '' };
        }).catch(function(){ return { xnxq: '', xqid: '' }; });
        ctx.then(function(c){
          if (!c.xnxq) {
            // getMenuList 缺 jsxq 时回退: 让服务端自己用会话学期 (queryKbForGrdb 无参)
          }
          // 2) 个人课表: 先试 queryKbForGrdb (无参), 若返回 HTML (404) 则回退 sdpkkbList
          return getText(base + '/pkgl/xskb/queryKbForGrdb?sf_request_type=ajax')
          .then(function(txt){
            if (txt.trim().startsWith('<')) {
              // 404 HTML — 回退 sdpkkbList (Syswin 变体, 需 xhid)
              // xhid 来源优先级: 本页 query → 本页 HTML → 同源 iframe 的 URL query
              // (门户壳结构: 主框 /admin 门户外壳, 课表页在 iframe 内, xhid 在其 URL)
              var xhid = '';
              try {
                var pm = location.search.match(/[?&]xhid=([A-Z0-9]+)/);
                if (pm) xhid = pm[1];
                if (!xhid) {
                  var m = document.body.innerHTML.match(/xhid['":\\s=]+['"]?([A-Z0-9]{60,})/);
                  if (m) xhid = m[1];
                }
                if (!xhid) {
                  var fs = document.querySelectorAll('iframe');
                  for (var fi = 0; fi < fs.length && !xhid; fi++) {
                    try {
                      var fm = fs[fi].contentWindow.location.search.match(/[?&]xhid=([A-Z0-9]+)/);
                      if (fm) xhid = fm[1];
                    } catch(e2) {}
                  }
                }
              } catch(e) {}
              if (!xhid) throw new Error('无法识别课表接口: 请先在教务里打开"我的课表"页再导入');
              return get(base + '/xsd/pkgl/xskb/sdpkkbList?xnxq=' + encodeURIComponent(c.xnxq) +
                        '&xhid=' + encodeURIComponent(xhid) + '&xqdm=' + encodeURIComponent(c.xqid) +
                        '&zdzc=&zxzc=&xskbxslx=0')
              .then(function(kb){ return kb.data || []; });
            }
            return JSON.parse(txt).data || [];
          })
          .then(function(rows){
            if (!rows || !rows.length) throw new Error('课表为空: 请先在教务里打开"我的课表"页再导入');
            // 3) 节次时间 (尽力而为, 失败不阻断 — periods 仅用于展示)
            return get(base + '/api/getZclistByXnxq?xnxq=' + encodeURIComponent(c.xnxq) +
                      '&xqid=' + encodeURIComponent(c.xqid) + '&role=&userId=&sf_request_type=ajax')
            .then(function(zc){
              var periods = [];
              try {
                var arr = zc.data.jcsjszList || [];
                for (var i = 0; i < arr.length; i++) {
                  periods.push({node: parseInt(arr[i].jc, 10), kssj: arr[i].kssj, jssj: arr[i].jssj});
                }
              } catch(e) {}
              var payload = JSON.stringify({
                xnxq: c.xnxq,
                dqzc: (zc && zc.data && zc.data.dqzc) || null,
                rows: rows,
                periods: periods
              });
              window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data: payload, periods: periods})});
            });
          });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(e) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
      }
    })()
    """
}

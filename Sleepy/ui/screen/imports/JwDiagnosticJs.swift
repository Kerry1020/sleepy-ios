// JwDiagnosticJs.swift — ← JwWebViewLoginScreen.kt 5 个诊断 JS 块
//  (CAPTURE_FRAMES_JS_TEMPLATE / DOM_INVENTORY_JS / STORAGE_JS / LINKS_JS /
//   DIAGNOSTIC_NETWORK_INSTALL_JS / DIAGNOSTIC_NETWORK_SNAPSHOT_JS)
//
// 排查全量包所需 — 失败弹窗时 evaluateJavascript 收集,落 zip frames/ dom-inventory.txt
// 5-storage/ 2-inline/links.json 等文件。
// 桥回调统一 WKScriptMessage postMessage。

import Foundation

// MARK: - CAPTURE_FRAMES_JS_TEMPLATE(原文移植)
//
// 遍历 window + frames/iframes, 抓每层 outerHTML, 跨域 frame 记域名。回传 JSON
// {ok, url, depth, frames:[{name, src, depth, path, html, blocked}]}。maxDepth 防深递归。
enum CaptureFramesJs {
    static let js = """
    (function(maxDepth){
      function snap(win, name, src, depth, path){
        var html = null, blocked = '';
        try { html = win.document.documentElement.outerHTML; }
        catch(e) {
          try { blocked = win.location.hostname || ''; } catch(_) { blocked = ''; }
          if (!blocked) { blocked = String(src || 'unknown'); }
        }
        return {name:(name===undefined||name==='')?null:name,
                src:(src===undefined||src==='')?null:src,
                depth:depth, path:path.slice(), html:html, blocked:blocked};
      }
      function walk(win, depth, path, out){
        if (depth > maxDepth) return;
        var d; try { d = win.document; } catch(e) { return; }
        if (depth === 0) { out.push(snap(win, '(top)', win.location.href, 0, [])); }
        var tags = ['frame','iframe'];
        for (var t = 0; t < tags.length; t++) {
          var els; try { els = d.getElementsByTagName(tags[t]); } catch(e) { els = []; }
          for (var i = 0; i < els.length; i++) {
            var el = els[i];
            var nm = el.name || el.id || (tags[t] + '_' + i);
            var p = path.concat([nm]);
            var cw = null;
            try { cw = el.contentWindow; } catch(e) { cw = null; }
            if (!cw) {
              out.push({name:nm, src:el.src||null, depth:depth+1, path:p, html:null,
                        blocked: el.src ? String(el.src) : 'no-contentWindow'});
              continue;
            }
            out.push(snap(cw, nm, el.src, depth+1, p));
            walk(cw, depth+1, p, out);
          }
        }
      }
      var out = [];
      walk(window, 0, [], out);
      return JSON.stringify({ok:true, url:location.href, depth:maxDepth, frames:out});
    })
    """
}

// MARK: - DOM_INVENTORY_JS(原文移植)
//
// 失败现场报告反循 — 扫 a/button/input/select/textarea/label 可点元素,带 rect/text/onclick/href
// 等字段; 跳过零尺寸隐藏控件; 字段原文保留供排查 EID/UID 异常。
enum DomInventoryJs {
    static let js = """
    (function(){
      function safe(t){return t==null?'':String(t);}
      function cls(el){return el && el.className ? String(el.className) : '';}
      function attrs(el){
        var o = {};
        try {
          var attrs = el.attributes || [];
          for (var i=0;i<attrs.length;i++){
            var a = attrs[i];
            if (a && a.specified !== false) o[a.name] = safe(a.value).slice(0,200);
          }
        } catch(e){}
        return o;
      }
      var CLICKABLE = ['a','button','input','select','textarea','label'];
      var items = [];
      var byTag = {};
      for (var i=0;i<CLICKABLE.length;i++){
        var tag = CLICKABLE[i];
        var nodes;
        try { nodes = document.getElementsByTagName(tag); } catch(e){ nodes = []; }
        for (var j=0;j<nodes.length;j++){
          var el = nodes[j];
          var rect = null;
          try { rect = el.getBoundingClientRect(); } catch(e){}
          if (rect && (rect.width===0 && rect.height===0)) continue;
          var text = '';
          try { text = (el.innerText || el.textContent || el.value || '').replace(/\\s+/g,' ').trim().slice(0,120); } catch(e){}
          items.push({
            tag: tag,
            id: safe(el.id),
            name: safe(el.name),
            type: safe(el.type),
            text: text,
            cls: cls(el),
            href: el.getAttribute ? safe(el.getAttribute('href')) : '',
            onclick: el.getAttribute ? safe(el.getAttribute('onclick')) : '',
            disabled: !!el.disabled,
            hidden: !!el.hidden || safe(el.style && el.style.display)==='none',
            rect: rect ? {x:Math.round(rect.x),y:Math.round(rect.y),w:Math.round(rect.width),h:Math.round(rect.height)} : null,
            attrs: attrs(el)
          });
        }
        byTag[tag] = nodes.length;
      }
      return JSON.stringify({url:location.href, total:items.length, byTag:byTag, items:items});
    })
    """
}

// MARK: - STORAGE_JS(原文移植)
//
// sessionStorage + localStorage 全键值(1B 不脱敏);按 origin 隔离, 当前文档 origin 即可。
enum StorageJs {
    static let js = """
    (function(){
      var out = {sessionStorage:{}, localStorage:{}, url:location.href};
      ['sessionStorage','localStorage'].forEach(function(sn){
        try {
          var st = window[sn]; var m = {};
          if (st) { for (var i=0;i<st.length;i++){ var k=st.key(i); try{ m[k]=String(st.getItem(k)); }catch(e){} } }
          out[sn] = m;
        } catch(e) {}
      });
      return JSON.stringify(out);
    })
    """
}

// MARK: - LINKS_JS(原文移植)
//
// 页面 a/iframe/form 链接全集绝对化 + select 枚举(学期码),适配者看导航面。
enum LinksJs {
    static let js = """
    (function(){
      function abs(h){ try { return new URL(h, location.href).href; } catch(e){ return h; } }
      var seen={}, links=[];
      var els=document.querySelectorAll('a[href],iframe[src],form[action]');
      for (var i=0;i<els.length;i++){
        var h=els[i].getAttribute('href')||els[i].getAttribute('src')||els[i].getAttribute('action')||'';
        if ((h.indexOf('http')===0||h.charAt(0)==='/') && !seen[h]) { seen[h]=1; links.push(abs(h)); }
      }
      var selects=[];
      var ss=document.querySelectorAll('select');
      for (var s=0;s<ss.length;s++){
        var opts=[];
        var os=ss[s].querySelectorAll('option');
        for (var o=0;o<os.length;o++){
          opts.push({v: os[o].getAttribute('value')||'', t: (os[o].textContent||'').trim().slice(0,60)});
        }
        if (opts.length) selects.push({sel:s, name:ss[s].getAttribute('name')||'', id:ss[s].id||'', opts:opts});
      }
      return JSON.stringify({url:location.href, links:links, selects:selects});
    })
    """
}

// MARK: - DIAGNOSTIC_NETWORK_INSTALL_JS(原文移植)
//
// Passive runtime network recorder — 保留原生 fetch/XHR 行为,只记录页面可观察的请求/响应。
// 500 行环形缓冲, body 上限 512KB 防爆; setInterval 兜底迟加载子帧。
enum DiagNetworkInstallJs {
    static let js = """
    (function(){
      if (window.__sleepyDiagNetworkInstalled) return;
      window.__sleepyDiagNetworkInstalled = true;
      var rows = window.__sleepyDiagNetworkRecords = [];
      var MAX_ROWS = 500, MAX_BODY = 512 * 1024;
      function trim(v){ v = v == null ? '' : String(v); return v.length > MAX_BODY ? v.slice(0, MAX_BODY) + '\\n[truncated]' : v; }
      function headers(h){ var o={}; try { h && h.forEach(function(v,k){o[k]=v;}); } catch(e) {} return o; }
      function push(x){ x.ts = Date.now(); rows.push(x); if(rows.length > MAX_ROWS) rows.shift(); }
      function instrument(win){
        try {
          if (!win || win.__sleepyDiagNetworkFramed) return;
          win.__sleepyDiagNetworkFramed = true;
          var nf = win.fetch;
          if (nf) win.fetch = function(input, init){
            var reqUrl = typeof input === 'string' ? input : (input && input.url) || '';
            var method = (init && init.method) || (input && input.method) || 'GET';
            var reqBody = init && init.body != null ? String(init.body) : '';
            var reqHeaders = {};
            try { if (input && input.headers) reqHeaders = headers(input.headers); } catch(e) {}
            try { if (init && init.headers) { var ih = headers(init.headers); for (var hk in ih) reqHeaders[hk]=ih[hk]; } } catch(e) {}
            return nf.apply(this, arguments).then(function(r){
              var x={source:'fetch',url:r.url || reqUrl,finalUrl:r.url || reqUrl,method:String(method).toUpperCase(),requestBody:trim(reqBody),requestHeaders:reqHeaders,status:r.status,ok:r.ok,responseHeaders:headers(r.headers),frame:win===window?'top':'frame'};
              try { x.redirected=!!r.redirected; } catch(e) {}
              return r.clone().text().then(function(b){ x.responseBody=trim(b); push(x); return r; },function(e){x.error=String(e);push(x);return r;});
            }, function(e){ push({source:'fetch',url:reqUrl,method:String(method).toUpperCase(),requestBody:trim(reqBody),status:0,error:String(e),frame:win===window?'top':'frame'}); throw e; });
          };
          var NX = win.XMLHttpRequest;
          if (NX) {
            var open = NX.prototype.open, send = NX.prototype.send, setHeader = NX.prototype.setRequestHeader;
            NX.prototype.open = function(method,url){ this.__sleepyDiag={method:String(method||'GET').toUpperCase(),url:String(url||''),headers:{}}; return open.apply(this,arguments); };
            NX.prototype.setRequestHeader = function(k,v){ if(this.__sleepyDiag) this.__sleepyDiag.headers[k]=String(v); return setHeader.apply(this,arguments); };
            NX.prototype.send = function(body){ var xhr=this, meta=this.__sleepyDiag || {method:'GET',url:''}; meta.requestBody=trim(body == null ? '' : body); function done(){ var x={source:'xhr',url:meta.url,finalUrl:meta.url,method:meta.method,requestBody:meta.requestBody,status:0,requestHeaders:meta.headers,frame:win===window?'top':'frame'}; try{x.status=xhr.status;x.responseHeaders=xhr.getAllResponseHeaders();x.responseBody=trim(typeof xhr.responseText==='string'?xhr.responseText:'');}catch(e){x.error=String(e);} push(x); } this.addEventListener('loadend',done,{once:true}); return send.apply(this,arguments); };
          }
        } catch(e) {}
      }
      instrument(window);
      try { for (var i=0;i<window.frames.length;i++) instrument(window.frames[i]); } catch(e) {}
      setInterval(function(){
        try { for (var j=0;j<window.frames.length;j++) instrument(window.frames[j]); } catch(e) {}
      }, 1500);
    })();
    """
}

// MARK: - DIAGNOSTIC_NETWORK_SNAPSHOT_JS(原文移植)
//
// 读 __sleepyDiagNetworkRecords 当前快照, 失败弹窗时 evaluateJavascript 拿。
enum DiagNetworkSnapshotJs {
    static let js = """
    (function(){ try { return JSON.stringify({live:window.__sleepyDiagNetworkRecords || []}); } catch(e) { return '{\\"live\\":[]}'; } })()
    """
}

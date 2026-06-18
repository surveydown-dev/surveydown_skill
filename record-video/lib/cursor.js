// Demo cursor overlay injected into the survey page for recordings.
// Provides a visible arrow cursor that glides to targets, plus a click
// ripple. Driven from R via window.__sdMove(selector) / window.__sdRipple().
// Everything is pointer-events:none so it never intercepts real interactions.
(function () {
  if (window.__sdCursorReady) return;

  var c = document.createElement('div');
  c.id = 'sd-rec-cursor';
  c.style.cssText =
    'position:fixed;z-index:2147483647;pointer-events:none;left:50%;top:40%;' +
    'margin-left:-3px;margin-top:-2px;' +
    'transition:left .55s cubic-bezier(.22,1,.36,1), top .55s cubic-bezier(.22,1,.36,1);' +
    'filter:drop-shadow(0 1px 1.5px rgba(0,0,0,.45));';
  c.innerHTML =
    '<svg width="26" height="26" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">' +
    '<path d="M4 2 L4 18.5 L8.2 14.3 L11 20.4 L13.7 19.2 L10.9 13.2 L16.8 13.2 Z" ' +
    'fill="#111" stroke="#fff" stroke-width="1.3" stroke-linejoin="round"/></svg>';
  document.body.appendChild(c);

  var st = document.createElement('style');
  st.textContent =
    '@keyframes sdRipple{0%{transform:translate(-50%,-50%) scale(.25);opacity:.55}' +
    '100%{transform:translate(-50%,-50%) scale(1.8);opacity:0}}' +
    '.sd-rec-ripple{position:fixed;z-index:2147483646;pointer-events:none;' +
    'width:42px;height:42px;border-radius:50%;background:rgba(40,110,240,.45);}' +
    // Cap long dropdowns so they scroll internally instead of spilling off a
    // short 16:9 viewport.
    '.selectize-dropdown-content{max-height:240px;overflow-y:auto;}' +
    // Strong highlight for the option the cursor is about to pick.
    '.sd-rec-pick{background:#cfe3ff !important;color:#0b1f44 !important;}';
  document.head.appendChild(st);

  window.__sdXY = { x: window.innerWidth * 0.5, y: window.innerHeight * 0.4 };

  // Glide the cursor to the center of the first element matching `sel`.
  // Button-group / image-card / radio inputs are often visually hidden (a
  // styled label is what the user sees), so if the matched element has no
  // real box, fall back to its nearest visible clickable ancestor.
  window.__sdMove = function (sel) {
    var el = document.querySelector(sel);
    if (!el) return false;
    var target = el;
    var r = target.getBoundingClientRect();
    var cs = getComputedStyle(target);
    if (r.width < 2 || r.height < 2 || cs.display === 'none' || cs.visibility === 'hidden') {
      var vis = el.closest('label, .btn, .sd-image-card, .form-check, button, .shiny-options-group .radio, .checkbox');
      target = vis || el.parentElement || el;
      r = target.getBoundingClientRect();
    }
    var x = r.left + r.width / 2, y = r.top + r.height / 2;
    var cur = document.getElementById('sd-rec-cursor');
    cur.style.left = x + 'px';
    cur.style.top = y + 'px';
    window.__sdXY = { x: x, y: y };
    return true;
  };

  // Emit a one-shot click ripple at the cursor's current position.
  window.__sdRipple = function () {
    var p = window.__sdXY || { x: 0, y: 0 };
    var d = document.createElement('div');
    d.className = 'sd-rec-ripple';
    d.style.left = p.x + 'px';
    d.style.top = p.y + 'px';
    d.style.animation = 'sdRipple .5s ease-out forwards';
    document.body.appendChild(d);
    setTimeout(function () { if (d.parentNode) d.parentNode.removeChild(d); }, 600);
  };

  window.__sdCursorReady = true;
})();

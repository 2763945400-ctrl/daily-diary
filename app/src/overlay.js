// 盖在页面上的东西：底部浮层（捕捉 / 待整理 / 日记详情）和居中对话框（清空确认）。
// 它们共用同一块遮罩，所以开关收在一处。
//
// 原来这段长在 today.js 里，关闭时挨个写死 id —— 每加一个浮层都得回来补一行，
// 漏了就会出现「遮罩关了浮层还在」。改成按 class 全关，以后加不用再动这里。

const el = (id) => document.getElementById(id);

export function openOverlay(id) {
  closeOverlays();
  el('scrim').hidden = false;
  el(id).hidden = false;
}

export function closeOverlays() {
  el('scrim').hidden = true;
  for (const box of document.querySelectorAll('.sheet, .dialog')) box.hidden = true;
}

/** 点遮罩关掉。所有页面共用，所以挂在这儿不挂在某一页里。 */
export function initOverlays() {
  el('scrim').addEventListener('click', closeOverlays);
}

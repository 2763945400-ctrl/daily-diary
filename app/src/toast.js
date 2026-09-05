// 轻提示。tokens 使用准则第 4 条：提示用 toast，只有需要用户做选择时才用对话框。
// 删除随手记不弹确认框，直接删 + 这里给几秒「撤销」（随手记案例 3 的拍板决定）。

let timer = null;

/** toast('已删除', { action: '撤销', onAction: restore }) */
export function toast(text, { action, onAction, duration = 4000 } = {}) {
  const box = document.getElementById('toast');
  const label = document.getElementById('toast-action');

  document.getElementById('toast-text').textContent = text;
  label.hidden = !action;
  label.textContent = action ?? '';
  label.onclick = action
    ? () => {
        hide();
        onAction?.();
      }
    : null;

  box.hidden = false;
  clearTimeout(timer);
  timer = setTimeout(hide, duration);
}

function hide() {
  clearTimeout(timer);
  document.getElementById('toast').hidden = true;
}

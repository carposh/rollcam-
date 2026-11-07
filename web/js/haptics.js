// Android: Vibration API. iPhone (iOS 18+): Safari gives a haptic tick when a
// <input type="checkbox" switch> is toggled, so we toggle a hidden one.
let label;

function iosTick() {
  if (!label) {
    label = document.createElement('label');
    label.setAttribute('aria-hidden', 'true');
    label.style.cssText = 'position:fixed;left:-200px;top:0;opacity:0;pointer-events:none;';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    input.tabIndex = -1;
    label.append(input);
    document.body.append(label);
  }
  label.click();
}

function buzz(pattern) {
  if (navigator.vibrate) navigator.vibrate(pattern);
  else iosTick();
}

export const tick = () => buzz(8);
export const heavy = () => buzz(25);
export const warn = () => { buzz([20, 60, 20]); if (!navigator.vibrate) setTimeout(iosTick, 90); };
export const success = () => buzz([15, 50, 30]);

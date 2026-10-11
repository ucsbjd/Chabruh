// Always play in landscape. When a phone is held upright (or its rotation lock
// is on) the whole game, canvas and UI, is turned sideways inside #stage, so
// turning the phone just works without the browser having to rotate.
const stage = document.getElementById('stage');
const isTouch = matchMedia('(pointer: coarse)').matches;

export const view = { rotated: false, w: window.innerWidth, h: window.innerHeight };

export function layout() {
  const W = window.innerWidth, H = window.innerHeight;
  view.rotated = isTouch && H > W;
  if (view.rotated) {
    view.w = H; view.h = W;
    stage.style.width = `${H}px`;
    stage.style.height = `${W}px`;
    stage.style.transform = `translateX(${W}px) rotate(90deg)`;
  } else {
    view.w = W; view.h = H;
    stage.style.width = '';
    stage.style.height = '';
    stage.style.transform = '';
  }
  const cl = document.documentElement.classList;
  cl.toggle('rotated', view.rotated);
  cl.toggle('compact', view.h <= 430);
  cl.toggle('narrow', view.w < 560);
  return view;
}

// Screen (client) coordinates to stage coordinates.
export function toStage(x, y) {
  if (!view.rotated) return { x, y };
  return { x: y, y: window.innerWidth - x };
}

layout();

// Paste this into the page's JavaScript console (or the browser tool's javascript_exec) on a YouTube watch page.
// It adds window.__show(t): pause the video, jump to t seconds, and paint that frame full-screen over the page,
// so a screenshot of the pane is a clean 800x449 picture of exactly that frame. Take one screenshot per frame
// (12 per second of footage is plenty) and save them in order; make_clip.py turns them into the motion clip.
// To find shot changes first, draw a labelled contact sheet of frames every 0.25-0.75 s and look for cuts.
window.__show = async (t) => {
  const v = document.querySelector('video'); v.pause();
  await new Promise(r => { const h = () => { v.removeEventListener('seeked', h); setTimeout(r, 250); }; v.addEventListener('seeked', h); v.currentTime = t; });
  let c = document.getElementById('frcv2');
  if (!c) {
    c = document.createElement('canvas'); c.id = 'frcv2'; c.width = 1280; c.height = 720;
    Object.assign(c.style, { position: 'fixed', left: '0', top: '0', width: '100vw', height: '100vh', zIndex: 2147483647, background: '#000' });
    document.body.appendChild(c);
  }
  c.getContext('2d').drawImage(v, 0, 0, 1920, 1080, 0, 0, 1280, 720);
  return 'ok ' + t;
};

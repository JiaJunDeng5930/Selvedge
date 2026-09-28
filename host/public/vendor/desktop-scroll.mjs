// Transplanted from Codex Desktop 26.917.71314. Callback bodies below are
// unchanged source slices; provenance records their UTF-16 source offsets and hashes.
// This shell binds the original refs/effects to Selvedge-owned DOM elements.
function tit(e){return Math.max(0,-e.scrollTop)}
function nit(e,t){let n=Math.max(0,t);e.scrollTop=n===0?0:-n}
function NV(e){if(e.borderBoxSize){let t=Array.isArray(e.borderBoxSize)?e.borderBoxSize[0]:e.borderBoxSize;return{width:t.inlineSize,height:t.blockSize}}return{width:e.contentRect.width,height:e.contentRect.height}}
const _ = tit, ce = nit, ge = NV;
const He = 260, Ue = 64, We = 8, Ge = 1000;
function Fe(){return 0}
function Ie(){return 0}
function Le(e,t){if(e.defaultPrevented||e.repeat)return null;let n=e.target;if(n instanceof HTMLElement&&n!==t&&(n.isContentEditable||n.closest(`input, select, textarea`)!=null||(e.key===` `||e.key===`Spacebar`)&&n.closest(`button, [role="button"]`)!=null))return null;switch(e.key){case`ArrowUp`:case`Home`:case`PageUp`:return`away`;case` `:case`Spacebar`:return e.shiftKey?`away`:`toward`;case`ArrowDown`:case`End`:case`PageDown`:return`toward`;default:return null}}
function Re(e){return _(e)<=24}
function ze(e,t){return Be(e)<=(t?Math.max(e.clientHeight,Ue):Ue)}
function Be(e){return e.scrollHeight-e.clientHeight-_(e)}

export function createDesktopScroll(scroll, content, footer, latest) {
  const g = true, v = false, y = false, he = true, x = 'bottom', b = 'default', S = 0;
  const h = undefined, u = undefined, d = undefined;
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  let _e = motion.matches;
  const reduced = () => { _e = motion.matches; };
  motion.addEventListener('change', reduced);
  const ref = current => ({ current });
  const C = ref(scroll), Ee = ref(null), w = ref(S), T = ref(null), De = ref(null), Oe = ref(null);
  const Ae = ref(new Set()), O = ref(new Set()), k = ref(null), A = ref(true), j = ref(false);
  const M = ref(null), N = ref(false), Me = ref(false), P = ref(null), F = ref(null), I = ref(null);
  const we = scrolled => { latest.hidden = !scrolled; };
  content.setAttribute('data-thread-user-message-navigation-content', '');
const V = ()=>C.current;
const Ke = V;
const qe = ()=>w.current;
const Je = qe;
const Ye = e=>(Ae.current.add(e),e(w.current),()=>{Ae.current.delete(e)});
const Xe = Ye;
const Ze = e=>(O.current.add(e),()=>{O.current.delete(e)});
const H = Ze;
const Qe = e=>{if(!g)return;T.current?.actualDistanceFromBottomPx!==e&&(T.current=null),w.current=e,x===`bottom`&&(De.current=Math.max(0,e-(h?.getHeightPx()??0)));let t=e<=24;u?.(e,t);for(let t of Ae.current)t(e);we(!t)};
const U = Qe;
const $e = ()=>{N.current=!1,I.current!=null&&(window.cancelAnimationFrame(I.current),I.current=null)};
const W = $e;
const et = ()=>{k.current=null,T.current=null,N.current=!0,I.current!=null&&(window.cancelAnimationFrame(I.current),I.current=null)};
const tt = et;
const nt = ()=>{P.current=null,F.current!=null&&(window.cancelAnimationFrame(F.current),F.current=null)};
const G = nt;
const rt = ()=>{let e=C.current,t=P.current;if(e==null||t==null)return null;let n=_(e),r=e.scrollHeight-t.scrollHeightPx;return r===0||n===t.distanceFromBottomPx?null:(G(),ce(e,n-r),_(e))};
const K = rt;
const it = (e,t)=>{let n=C.current;if(n==null)return;G();let r=Math.max(0,t(n));r!==_(n)&&(k.current=null),n.scrollTo({behavior:e,top:r===0?0:-r});let i=_(n);T.current=e===`instant`&&i!==r&&r>0&&r<n.scrollHeight-n.clientHeight?{requestedDistanceFromBottomPx:r,actualDistanceFromBottomPx:i}:null,U(i)};
const q = it;
const at = (e,t,n)=>{let r=n===void 0?`system`:n,i=w.current,a=Math.max(0,e);a>24&&W(),q(t,()=>a);let o=w.current;if(r===`user`&&o!==i)for(let e of O.current)e(o,i)};
const J = at;
const ot = e=>{N.current||q(`instant`,()=>e)};
const Y = ot;
const st = e=>{Me.current=e};
const ct = st;
const lt = ()=>{let e=C.current;if(N.current||e==null||P.current!=null)return;let t={distanceFromBottomPx:_(e),scrollHeightPx:e.scrollHeight};P.current=t,queueMicrotask(()=>{if(P.current!==t)return;if(e.scrollHeight===t.scrollHeightPx){G();return}let n=K();n!=null&&U(n)}),F.current=window.requestAnimationFrame(()=>{let e=K();G(),e!=null&&U(e)})};
const ut = lt;
const dt = async()=>{if(j.current||d==null)return;let e=M.current;j.current=!0,await(async()=>{try{for(;M.current===e&&C.current!=null&&ze(C.current,y);){let e=C.current.scrollHeight;if(await d()===`stop`||!v)break;let t=C.current;if(t!=null&&t.scrollHeight-t.clientHeight>Ue&&(!y||t.scrollHeight>e))break}}catch{}})().finally(()=>{j.current=!1,M.current!==e&&M.current?.()})};
const X = dt;
const ft = ()=>{let e=C.current;if(!g||!v||e==null||d==null)return;let t,n,r=()=>{let i=e.clientHeight,a=e.scrollHeight;M.current!==r||C.current!==e||i<=0||a-i>Ue||j.current||(t!==i||n!==a)&&(t=i,n=a,X())};M.current=r;let i=new ResizeObserver(r);i.observe(e);let a=e.firstElementChild;a!=null&&i.observe(a);let o=window.requestAnimationFrame(r);return()=>{M.current===r&&(M.current=null),window.cancelAnimationFrame(o),i.disconnect()}};
const mt = ()=>{let e=C.current;if(e==null)return;G();let t=_(e);if(_e||t<=24){q(`instant`,Ie),W();return}tt();let n=performance.now(),r=e=>{let i=C.current;if(i==null){W();return}let a=Math.min(1,(e-n)/He),o=1-(1-a)**3;if(ce(i,t*(1-o)),a<1&&!Re(i)){I.current=window.requestAnimationFrame(r);return}q(`instant`,Fe),W()};I.current=window.requestAnimationFrame(r)};
const ht = mt;
const gt = ()=>{let e=Oe.current;Oe.current={active:g,scrollOrigin:x};let t=C.current;if(!g||t==null){W();return}if(e==null||e.active!==g||e.scrollOrigin!==x){W(),T.current=null;let n=e!=null&&(!e.active||e.scrollOrigin===`top`),r=S;if(x===`top`)r=Math.max(0,t.scrollHeight-t.clientHeight);else if(n){let e=De.current;r=e==null?S:e+(h?.getHeightPx()??0)}ce(t,r),U(_(t)),A.current=x===`top`||_(t)-(h?.getHeightPx()??0)<=24}};
const vt = ()=>{let e=C.current;if(!g||x===`bottom`&&!he||e==null)return;let t=e.querySelector(`[data-thread-user-message-navigation-content]`);if(t==null)return;let n=Math.max(0,t.scrollHeight-(h?.getHeightPx()??0)),r=H(t=>{if(x===`top`){A.current=e.scrollHeight-e.clientHeight-t<=24;return}A.current=t<=24}),i=new ResizeObserver(()=>{let r=h?.getHeightPx()??0,i=Math.max(0,t.scrollHeight-r),a=i-n;n=i;let o=_(e);if(x===`bottom`&&o<=24&&(A.current=!0),x===`top`&&A.current){J(Math.max(0,e.scrollHeight-e.clientHeight),`instant`);return}if(a<=0)return;let s=o+a;A.current&&(s=Math.min(s,r)),Y(s)});return i.observe(t),x===`top`&&i.observe(e),()=>{r(),i.disconnect()}};
const bt = ()=>{let e=C.current;if(!g||e==null)return;let t=new AbortController,n={passive:!0,signal:t.signal},r=null,i=null,a=t=>{W(),T.current=null;let n=t===`away`?Be(e)>0:_(e)>0;k.current=n?{direction:t,lastAtMs:performance.now()}:null},o=()=>{let t=_(e);t<=24&&W(),U(t)},s=()=>{K();let t=w.current,n=i;if(n!=null){i=null;let r=_(e);e.scrollHeight===n.scrollHeightPx&&e.scrollTop!==n.scrollTopPx&&r!==t&&(k.current={direction:r>t?`away`:`toward`,lastAtMs:performance.now()})}let r=k.current;if(r==null){o();return}let a=performance.now();if(a-r.lastAtMs>Ge){k.current=null,o();return}o();let s=_(e);if((s>t?`away`:s<t?`toward`:null)===r.direction){r.lastAtMs=a,s>t&&ze(e,y)&&X();for(let e of O.current)e(s,t);s<=24&&(k.current=null)}},c=t=>{t.deltaY<0&&Be(e)<=0&&X(),t.deltaY!==0&&a(t.deltaY<0?`away`:`toward`)},l=t=>{let n=Le(t,e);n!=null&&(G(),a(n),n===`away`&&Be(e)<=0&&X())},ee=t=>{i=null,k.current=null,t.pointerType===`mouse`&&t.target===e&&(G(),W(),T.current=null,i={scrollHeightPx:e.scrollHeight,scrollTopPx:e.scrollTop})},u=()=>{i=null},d=e=>{r=e.touches.length===1?e.touches[0]:null},f=t=>{let n=t.touches.length===1?t.touches[0]:null;if(r==null||n==null||n.identifier!==r.identifier){r=null;return}let i=n.clientX-r.clientX,o=n.clientY-r.clientY;Math.max(Math.abs(i),Math.abs(o))<We||(r=null,Math.abs(o)>Math.abs(i)&&(G(),a(o>0?`away`:`toward`)),o>Math.abs(i)&&Be(e)<=0&&X())},p=()=>{r=null};return e.addEventListener(`pointerdown`,ee,n),e.addEventListener(`pointerup`,u,n),e.addEventListener(`pointercancel`,u,n),e.addEventListener(`keydown`,l,n),e.addEventListener(`touchstart`,d,n),e.addEventListener(`touchmove`,f,n),e.addEventListener(`touchend`,p,n),e.addEventListener(`touchcancel`,p,n),e.addEventListener(`wheel`,c,n),e.addEventListener(`scroll`,s,n),()=>{t.abort()}};
const St = ()=>()=>{G(),W()};
const Et = e=>{let{height:t}=ge(e),n=C.current;if(n==null)return;let r=Ee.current;r!==t&&(n.style.setProperty(`--thread-scroll-padding-bottom`,`${t+(b===`compact`?0:16)}px`),Ee.current=t,!(N.current||Me.current)&&(r==null||Re(n)||q(`instant`,e=>_(e)+t-r)))};
  gt();
  const cleanups = [ft(), vt(), bt(), St()];
  const observer = new ResizeObserver(entries => { for (const entry of entries) Et(entry); });
  observer.observe(footer);
  latest.onclick = ht;
  return {
    beforeUpdate: ut,
    end: ht,
    start: () => J(Math.max(0, scroll.scrollHeight - scroll.clientHeight), 'instant', 'user'),
    distance: () => _(scroll),
    get following() { return A.current; },
    dispose() {
      for (const cleanup of cleanups) cleanup?.();
      observer.disconnect(); motion.removeEventListener('change', reduced); latest.onclick = null;
    },
  };
}

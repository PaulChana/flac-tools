const SHOW_DELAY = 500;
const OFFSET = 8;

let tip: HTMLDivElement | null = null;
let current: HTMLElement | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;

function hide() {
  clearTimeout(timer);
  if (current) {
    const text = current.dataset.tip;
    if (text !== undefined && !current.hasAttribute("title")) current.setAttribute("title", text);
    current = null;
  }
  if (tip) {
    const old = tip;
    tip = null;
    old.classList.remove("visible");
    setTimeout(() => old.remove(), 150);
  }
}

function place(el: HTMLElement, box: HTMLDivElement) {
  const r = el.getBoundingClientRect();
  const b = box.getBoundingClientRect();
  let top = r.bottom + OFFSET;
  if (top + b.height > window.innerHeight - 4) top = r.top - b.height - OFFSET;
  const left = Math.max(4, Math.min(r.left + r.width / 2 - b.width / 2, window.innerWidth - b.width - 4));
  box.style.left = `${left}px`;
  box.style.top = `${Math.max(4, top)}px`;
}

function show(el: HTMLElement) {
  const text = el.dataset.tip;
  if (!text || !el.isConnected) return;
  tip = document.createElement("div");
  tip.className = "app-tooltip";
  tip.setAttribute("role", "tooltip");
  tip.textContent = text;
  document.body.appendChild(tip);
  place(el, tip);
  const shown = tip;
  requestAnimationFrame(() => shown.classList.add("visible"));
}

if (typeof document !== "undefined") {
  document.addEventListener("mouseover", (e) => {
    const el = (e.target as HTMLElement | null)?.closest?.<HTMLElement>("[title]") ?? null;
    if (el === current) return;
    hide();
    if (!el) return;
    const text = el.getAttribute("title") ?? "";
    if (!text) return;
    el.dataset.tip = text;
    el.removeAttribute("title");
    current = el;
    timer = setTimeout(() => current === el && show(el), SHOW_DELAY);
  });
  document.addEventListener("mouseout", (e) => {
    if (current && !current.contains(e.relatedTarget as Node | null)) hide();
  });
  for (const type of ["mousedown", "wheel", "keydown"]) document.addEventListener(type, hide, true);
}

// The interactive demo on the landing page: an HTML copy of the LumoBar window
// drives the light bar behind the monitor in the photo next to it.
//
// The photo is relit from two shots of the same scene: room-off.jpg (light bar off)
// and room-lit.jpg (light bar on, neutral white, full brightness). Their difference
// is the light the bar adds; the canvas shows  off + difference × colour × level.
//
// No dependencies. Without JavaScript the lit photo is shown and the controls do nothing.
(() => {
  const $ = (id) => document.getElementById(id);
  const demo = document.querySelector(".demo");
  if (!demo) return;

  const els = {
    power: $("power"),
    card: $("card"),
    stateText: $("stateText"),
    pct: $("pct"),
    expand: $("expand"),
    controls: $("controls"),
    bri: $("bri"),
    briVal: $("briVal"),
    temp: $("temp"),
    tempVal: $("tempVal"),
    field: $("field"),
    picker: $("picker"),
    dots: [...document.querySelectorAll(".dots button")],
  };

  // Same built-in scenes as the app (LightScenePreset): hue, saturation, brightness.
  const SCENES = {
    white: { h: 0, s: 0, bri: 100 },
    focus: { h: 42, s: 0.36, bri: 100 },
    relax: { h: 24, s: 0.76, bri: 78 },
    neon: { h: 278, s: 0.86, bri: 100 },
    night: { h: 220, s: 0.72, bri: 32 },
  };

  const state = { on: true, bri: 70, mode: "white", kelvin: 2700, h: 30, s: 0.8 };

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

  // Colour temperature to RGB (Tanner Helland's approximation).
  function kelvinToRGB(k) {
    const t = k / 100;
    const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
    const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
    const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
    return [r, g, b].map((c) => clamp(c, 0, 255));
  }

  function hsvToRGB(h, s) {
    const f = (n) => {
      const k = (n + h / 60) % 6;
      return 255 * (1 - s * Math.max(0, Math.min(k, 4 - k, 1)));
    };
    return [f(5), f(3), f(1)];
  }

  // --- The photo -----------------------------------------------------------

  const canvas = $("roomCanvas");
  const ctx = canvas && canvas.getContext("2d");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let off = null; // the "light bar off" photo
  let light = null; // canvas: what the light bar adds (lit − off)
  let tint = null; // scratch canvas: light × colour
  const shown = { rgb: [255, 167, 87], level: 0.77 };
  const target = { rgb: shown.rgb, level: shown.level };
  let frame = 0;
  const LIGHT_GAIN = 1.2;

  function loadImage(src) {
    const img = new Image();
    img.src = src;
    return img.decode().then(() => img);
  }

  function makeCanvas(w, h) {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    return c;
  }

  if (ctx) {
    Promise.all([loadImage("./room-off.jpg"), loadImage("./room-lit.jpg")])
      .then(([offImg, litImg]) => {
        const { width: w, height: h } = canvas;
        light = makeCanvas(w, h);
        const l = light.getContext("2d");
        l.drawImage(litImg, 0, 0, w, h);
        l.globalCompositeOperation = "difference";
        l.drawImage(offImg, 0, 0, w, h);
        // The bar in the photo is slightly warm (measured lit − off ≈ rgb 104 91 79):
        // neutralise it so a chosen colour comes out as that colour.
        l.globalCompositeOperation = "multiply";
        l.fillStyle = "rgb(194 222 255)";
        l.fillRect(0, 0, w, h);
        tint = makeCanvas(w, h);
        off = offImg;
        Object.assign(shown, { rgb: target.rgb, level: target.level });
        paint();
      })
      .catch(() => {}); // keep the lit photo from the CSS background
  }

  function paint() {
    if (!off) return;
    const { width: w, height: h } = canvas;
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    ctx.drawImage(off, 0, 0, w, h);
    if (shown.level < 0.003) return;
    const t = tint.getContext("2d");
    t.globalCompositeOperation = "source-over";
    t.drawImage(light, 0, 0);
    t.globalCompositeOperation = "multiply";
    t.fillStyle = `rgb(${shown.rgb.map(Math.round).join(" ")})`;
    t.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = "lighter";
    // Neutralising took some light away; add it back (alpha cannot go above 1, so draw twice).
    for (let alpha = shown.level * LIGHT_GAIN; alpha > 0.003; alpha -= 1) {
      ctx.globalAlpha = Math.min(1, alpha);
      ctx.drawImage(tint, 0, 0);
    }
  }

  // Ease the shown light towards the target, like a real bulb fading.
  function step() {
    frame = 0;
    const k = reduceMotion ? 1 : 0.2;
    shown.rgb = shown.rgb.map((c, i) => c + (target.rgb[i] - c) * k);
    shown.level += (target.level - shown.level) * k;
    const done =
      Math.abs(shown.level - target.level) < 0.002 && shown.rgb.every((c, i) => Math.abs(c - target.rgb[i]) < 0.5);
    if (done) Object.assign(shown, { rgb: target.rgb, level: target.level });
    paint();
    if (!done) frame = requestAnimationFrame(step);
  }

  function setLight(rgb, level) {
    Object.assign(target, { rgb, level });
    if (off && !frame) frame = requestAnimationFrame(step);
  }

  // --- The window -----------------------------------------------------------

  function render() {
    const rgb = state.mode === "white" ? kelvinToRGB(state.kelvin) : hsvToRGB(state.h, state.s);
    const level = state.on ? 0.12 + 0.88 * (state.bri / 100) : 0;
    demo.style.setProperty("--light", `rgb(${rgb.map(Math.round).join(" ")})`);
    demo.style.setProperty("--level", level.toFixed(3));
    setLight(rgb, level);

    els.power.setAttribute("aria-pressed", String(state.on));
    els.power.setAttribute("aria-label", state.on ? "Turn the light off" : "Turn the light on");
    els.card.classList.toggle("off", !state.on);
    els.stateText.textContent = state.on ? "On" : "Off";

    els.pct.textContent = els.briVal.textContent = `${state.bri}%`;
    els.bri.value = state.bri;
    els.temp.value = state.kelvin;
    els.tempVal.textContent = `${state.kelvin}K`;

    els.picker.style.left = `${(state.h / 360) * 100}%`;
    els.picker.style.top = `${state.s * 100}%`;
    els.field.classList.toggle("white-mode", state.mode === "white");
    els.field.setAttribute("aria-valuenow", String(Math.round(state.h)));
    els.field.setAttribute("aria-valuetext", `Hue ${Math.round(state.h)}°, saturation ${Math.round(state.s * 100)}%`);

    for (const dot of els.dots) {
      const match = state.mode === "color" && Number(dot.dataset.h) === state.h && Number(dot.dataset.s) === state.s;
      dot.setAttribute("aria-pressed", String(match));
    }
  }

  function setColor(h, s) {
    Object.assign(state, { mode: "color", h, s, on: true });
    render();
  }

  els.power.addEventListener("click", () => {
    state.on = !state.on;
    render();
  });

  els.expand.addEventListener("click", () => {
    const open = els.expand.getAttribute("aria-expanded") !== "true";
    els.expand.setAttribute("aria-expanded", String(open));
    els.expand.setAttribute("aria-label", open ? "Hide the controls" : "Show the controls");
    els.controls.hidden = !open;
  });

  els.bri.addEventListener("input", () => {
    Object.assign(state, { bri: Number(els.bri.value), on: true });
    render();
  });

  els.temp.addEventListener("input", () => {
    Object.assign(state, { kelvin: Number(els.temp.value), mode: "white", on: true });
    render();
  });

  for (const dot of els.dots) {
    dot.addEventListener("click", () => setColor(Number(dot.dataset.h), Number(dot.dataset.s)));
  }

  for (const chip of document.querySelectorAll(".chip")) {
    chip.addEventListener("click", () => {
      const scene = SCENES[chip.dataset.scene];
      Object.assign(state, { mode: "color", h: scene.h, s: scene.s, bri: scene.bri, on: true });
      render();
    });
  }

  // Colour field: hue left to right, saturation top (white) to bottom (full).
  function pick(event) {
    const box = els.field.getBoundingClientRect();
    const x = clamp((event.clientX - box.left) / box.width, 0, 1);
    const y = clamp((event.clientY - box.top) / box.height, 0, 1);
    setColor(Math.round(x * 360) % 360, Math.round(y * 100) / 100);
  }

  els.field.addEventListener("pointerdown", (event) => {
    els.field.setPointerCapture(event.pointerId);
    pick(event);
  });
  els.field.addEventListener("pointermove", (event) => {
    if (els.field.hasPointerCapture(event.pointerId)) pick(event);
  });
  els.field.addEventListener("keydown", (event) => {
    const steps = { ArrowLeft: [-10, 0], ArrowRight: [10, 0], ArrowUp: [0, -0.1], ArrowDown: [0, 0.1] };
    const step = steps[event.key];
    if (!step) return;
    event.preventDefault();
    const h = (state.h + step[0] + 360) % 360;
    const s = Math.round(clamp(state.s + step[1], 0, 1) * 100) / 100;
    setColor(h, s);
  });

  const time = new Date().toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  $("clock").textContent = time;
  $("synced").textContent = time;

  render();
})();

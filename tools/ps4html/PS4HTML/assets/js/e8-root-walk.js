(function () {
  "use strict";

  function register() {
    if (!window.PS4HTMLComputation) return;
    window.PS4HTMLComputation.register("proofscript/e8-root-walk-v1", async ({ component, compute, element }) => {
      const payload = component.payload || {};
      const controls = payload.controls || {};
      const stepsControl = controls.steps || {};
      const min = Number.isInteger(stepsControl.min) ? stepsControl.min : 1;
      const max = Number.isInteger(stepsControl.max) ? stepsControl.max : 240;
      const initial = Math.max(min, Math.min(max, Number(payload.defaultInput?.steps || 24)));
      const id = `e8-walk-${crypto.randomUUID()}`;
      element.innerHTML = `<div class="e8-walk-computation">
        <div class="e8-walk-toolbar">
          <label for="${id}-steps">Steps <output data-e8-walk-step-label>${initial}</output><input id="${id}-steps" type="range" min="${min}" max="${max}" value="${initial}"></label>
          <label for="${id}-family">Family<select id="${id}-family"><option value="all">All roots</option><option value="integral">Integral</option><option value="halfIntegral">Half-integral</option></select></label>
          <label for="${id}-projection">Projection<select id="${id}-projection"><option value="coordinates">Coordinates 0 and 1</option><option value="coxeterPlane">2D visualization projection</option></select></label>
          <span class="e8-walk-axes"><label for="${id}-x">x<select id="${id}-x"></select></label><label for="${id}-y">y<select id="${id}-y"></select></label></span>
        </div>
        <div class="e8-walk-stats"><span>Computed steps <strong data-e8-walk-computed>...</strong></span><span>Available roots <strong data-e8-walk-available>...</strong></span><span>Path length <strong data-e8-walk-length>...</strong></span><span>Norm squared <strong data-e8-walk-norm>...</strong></span></div>
        <canvas data-e8-walk-canvas tabindex="0" aria-label="E8 root walk"></canvas>
        <div class="e8-walk-current" data-e8-walk-current aria-live="polite">Computing path in Lean/Wasm...</div>
        <p class="e8-walk-message" data-e8-walk-message></p>
      </div>`;
      const steps = element.querySelector(`#${id}-steps`), family = element.querySelector(`#${id}-family`), projection = element.querySelector(`#${id}-projection`), x = element.querySelector(`#${id}-x`), y = element.querySelector(`#${id}-y`), canvas = element.querySelector("[data-e8-walk-canvas]"), message = element.querySelector("[data-e8-walk-message]"), current = element.querySelector("[data-e8-walk-current]");
      for (let i = 0; i < 8; i += 1) { x.add(new Option(String(i), String(i))); y.add(new Option(String(i), String(i))); }
      x.value = "0"; y.value = "1";
      y.querySelectorAll("option").forEach(option => { option.disabled = option.value === x.value; });
      family.value = ["all", "integral", "halfIntegral"].includes(payload.defaultInput?.family) ? payload.defaultInput.family : "all";
      projection.value = payload.defaultInput?.projection?.coordinates ? "coordinates" : "coxeterPlane";
      let response = null, selected = -1, pointer = null;
      // Lean.FromJson encodes the coordinates constructor as an object, not an array.
      function input() { return { steps: Number(steps.value), family: family.value, projection: projection.value === "coordinates" ? { coordinates: { x: Number(x.value), y: Number(y.value) } } : "coxeterPlane" }; }
      async function run() { element.dataset.loading = "true"; message.textContent = "Computing path in Lean/Wasm..."; try { const result = await compute(input()); if (!result.ok) throw new Error(result.error.message); response = result.value; selected = response.points.length - 1; renderStats(element, response); draw(canvas, response.points, selected, projection.value); renderCurrent(current, response.points[selected], response.normSquared); message.textContent = response.projectionDescription || "Computed by Lean/Wasm; path is a visualization only."; delete element.dataset.error; } catch (error) { message.textContent = error.message || String(error); element.dataset.error = "true"; } finally { delete element.dataset.loading; } }
      function redraw() { if (response) draw(canvas, response.points, selected, projection.value); }
      steps.addEventListener("input", () => { element.querySelector("[data-e8-walk-step-label]").textContent = steps.value; void run(); });
      x.addEventListener("change", () => { y.querySelectorAll("option").forEach(option => { option.disabled = option.value === x.value; }); if (y.value === x.value) y.value = x.value === "0" ? "1" : "0"; void run(); });
      [family, projection, y].forEach(control => control.addEventListener("change", run));
      canvas.addEventListener("pointermove", event => { const rect = canvas.getBoundingClientRect(), px = event.clientX - rect.left, py = event.clientY - rect.top; const point = (canvas.__e8WalkPoints || []).reduce((best, candidate, index) => { const distance = Math.hypot(candidate.x - px, candidate.y - py); return distance < best.distance ? { distance, index } : best; }, { distance: 18, index: -1 }); canvas.__e8WalkHit = point.index; if (point.index >= 0) { selected = point.index; renderCurrent(current, response.points[selected], response.normSquared); redraw(); } });
      canvas.addEventListener("pointerleave", () => { if (response) { selected = response.points.length - 1; renderCurrent(current, response.points[selected], response.normSquared); redraw(); } });
      canvas.addEventListener("pointerdown", event => { pointer = { x: event.clientX, y: event.clientY }; canvas.setPointerCapture(event.pointerId); });
      canvas.addEventListener("pointerup", event => { if (pointer && Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) < 5 && canvas.__e8WalkHit >= 0) { selected = canvas.__e8WalkHit; renderCurrent(current, response.points[selected], response.normSquared); redraw(); } pointer = null; });
      if (typeof ResizeObserver !== "undefined") new ResizeObserver(redraw).observe(canvas);
      await run();
    });
  }
  function project(point, projection) { if (projection === "coordinates") return { x: point.xNumerator / point.denominator, y: point.yNumerator / point.denominator }; return { x: point.xNumerator / point.denominator, y: point.yNumerator / point.denominator }; }
  function draw(canvas, points, selected, projection) { const box = canvas.getBoundingClientRect(), ratio = window.devicePixelRatio || 1, width = Math.max(1, box.width), height = Math.max(1, box.height), context = canvas.getContext("2d"); canvas.width = width * ratio; canvas.height = height * ratio; context.setTransform(ratio, 0, 0, ratio, 0, 0); context.fillStyle = "#f8fbff"; context.fillRect(0, 0, width, height); const raw = points.map(point => project(point, projection)), extent = Math.max(...raw.flatMap(point => [Math.abs(point.x), Math.abs(point.y)]), 1), scale = Math.min(width, height) * .42 / extent, screen = raw.map(point => ({ x: width / 2 + point.x * scale, y: height / 2 - point.y * scale })); context.strokeStyle = "#cbd5e1"; context.beginPath(); context.moveTo(width / 2, 0); context.lineTo(width / 2, height); context.moveTo(0, height / 2); context.lineTo(width, height / 2); context.stroke(); context.beginPath(); screen.forEach((point, index) => index ? context.lineTo(point.x, point.y) : context.moveTo(point.x, point.y)); context.strokeStyle = "#176b87"; context.lineWidth = 2; context.stroke(); screen.forEach((point, index) => { context.fillStyle = points[index].root.family === "halfIntegral" ? "#54a87a" : "#176b87"; context.beginPath(); context.arc(point.x, point.y, index === selected ? 6 : 3, 0, Math.PI * 2); context.fill(); }); canvas.__e8WalkPoints = screen; }
  function renderStats(element, response) { element.querySelector("[data-e8-walk-computed]").textContent = response.stepsComputed; element.querySelector("[data-e8-walk-available]").textContent = response.availableRoots; element.querySelector("[data-e8-walk-length]").textContent = response.points.length; element.querySelector("[data-e8-walk-norm]").textContent = response.normSquared; }
  function renderCurrent(element, point, norm) { if (!point) { element.textContent = "No point computed."; return; } element.textContent = `Step ${point.step}: (${point.root.numerators.map(value => point.root.denominator === 1 ? value : `${value}/${point.root.denominator}`).join(", ")}) · ${point.root.family} · norm squared ${norm}`; }
  register();
})();

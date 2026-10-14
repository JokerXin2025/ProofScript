(function () {
  "use strict";

  function register() {
    if (!window.PS4HTMLComputation) return;
    window.PS4HTMLComputation.register("proofscript/e8-root-explorer-v2", async ({ component, compute, element }) => {
      const payload = component.payload || {};
      const defaults = payload.defaultInput || {};
      const id = `e8-${crypto.randomUUID()}`;
      element.innerHTML = `
        <div class="e8-computation">
          <div class="e8-toolbar">
            <label for="${id}-family">Root family<select id="${id}-family"><option value="all">All roots</option><option value="integral">Integral</option><option value="halfIntegral">Half-integral</option></select></label>
            <label for="${id}-projection">Projection<select id="${id}-projection" data-e8-projection><option value="coxeterPlane">Coxeter plane</option><option value="coordinates">Coordinates</option></select></label>
            <span class="e8-coordinate-controls" data-e8-coordinates hidden><span class="e8-axis-control"><label for="${id}-x">x</label><select id="${id}-x" data-e8-x></select></span><span class="e8-axis-control"><label for="${id}-y">y</label><select id="${id}-y" data-e8-y></select></span></span>
            <label class="e8-radius" for="${id}-radius">Radius <input id="${id}-radius" type="text" inputmode="decimal" placeholder="optional, e.g. 1/2"></label>
          </div>
          <div class="e8-summary" aria-live="polite"><div><small>Selected roots</small><strong data-e8-selected>...</strong></div><div><small>All roots</small><strong data-e8-total>...</strong></div><div><small>Norm squared</small><strong data-e8-norm>...</strong></div></div>
          <div class="e8-body"><div class="e8-projection"><div class="e8-canvas-wrap"><canvas data-e8-canvas tabindex="0" aria-label="E8 root projection"></canvas></div></div><div class="e8-details"><div data-e8-density></div><div data-e8-root></div></div></div>
          <p class="e8-message" data-e8-message></p>
        </div>`;

      const selects = element.querySelectorAll("select");
      const familySelect = selects[0];
      const projectionSelect = selects[1];
      const xSelect = element.querySelector(`#${id}-x`);
      const ySelect = element.querySelector(`#${id}-y`);
      const coordinateControls = element.querySelector("[data-e8-coordinates]");
      const radiusInput = element.querySelector(`#${id}-radius`);
      const canvas = element.querySelector("[data-e8-canvas]");
      const message = element.querySelector("[data-e8-message]");
      let response = null;
      let selectedIndex = -1;
      let points = [];
      let hoverIndex = -1;
      let hoverAmount = 0;
      let hoverFrame = 0;

      for (let index = 0; index < 8; index += 1) {
        xSelect.add(new Option(String(index), String(index)));
        ySelect.add(new Option(String(index), String(index)));
      }
      xSelect.value = "0";
      ySelect.value = "1";
      familySelect.value = ["all", "integral", "halfIntegral"].includes(defaults.family) ? defaults.family : "all";
      projectionSelect.value = defaults.projection === "coordinates" ? "coordinates" : "coxeterPlane";

      function redraw() {
        if (response) {
          points = drawProjection(canvas, response.roots, selectedIndex, hoverIndex, hoverAmount);
        }
      }

      function animateHover() {
        hoverFrame = 0;
        const target = hoverIndex >= 0 ? 1 : 0;
        hoverAmount += (target - hoverAmount) * .18;
        redraw();
        if (Math.abs(target - hoverAmount) > .01) hoverFrame = requestAnimationFrame(animateHover);
      }

      function setHover(index) {
        if (hoverIndex === index) return;
        hoverIndex = index;
        if (!hoverFrame) hoverFrame = requestAnimationFrame(animateHover);
      }

      function updateCoordinateControls() {
        coordinateControls.hidden = projectionSelect.value !== "coordinates";
        ySelect.querySelectorAll("option").forEach(option => { option.disabled = option.value === xSelect.value; });
        if (ySelect.value === xSelect.value) ySelect.value = xSelect.value === "0" ? "1" : "0";
        redraw();
      }
      updateCoordinateControls();
      projectionSelect.addEventListener("change", () => { updateCoordinateControls(); void run(); });
      xSelect.addEventListener("change", () => { updateCoordinateControls(); void run(); });
      ySelect.addEventListener("change", () => { updateCoordinateControls(); void run(); });
      canvas.addEventListener("keydown", event => {
        if ((event.key === "Enter" || event.key === " ") && response && points.length) {
          event.preventDefault();
          selectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
          renderSelectedRoot(element, response, selectedIndex);
          redraw();
        }
      });

      async function run() {
        element.dataset.loading = "true";
        message.textContent = "Computing E8 roots in Lean/Wasm...";
        try {
          const input = {
            family: familySelect.value,
            projection: projectionSelect.value === "coordinates"
              ? { coordinates: { x: Number(xSelect.value), y: Number(ySelect.value) } }
              : "coxeterPlane",
          };
          const radius = radiusInput.value.trim();
          if (radius) {
            const parts = radius.split("/");
            if (parts.length > 2 || !/^\d+$/.test(parts[0]) || (parts[1] && !/^\d+$/.test(parts[1]))) {
              throw new Error("Radius must be a non-negative rational number, such as 1/2");
            }
            input.radius = { numerator: Number(parts[0]), denominator: Number(parts[1] || 1) };
          }
          const result = await compute(input);
          if (!result.ok) throw new Error(result.error.message);
          response = result.value;
          selectedIndex = -1;
          points = renderResponse(element, response, canvas);
          message.textContent = "Only the projection on the two-dimensional plane.";
          delete element.dataset.error;
        } catch (error) {
          message.textContent = error.message;
          element.dataset.error = "true";
        } finally {
          delete element.dataset.loading;
        }
      }
      familySelect.addEventListener("change", run);
      radiusInput.addEventListener("change", run);
      canvas.addEventListener("click", event => {
        points = canvas.__e8Points || [];
        if (!response || !points.length) return;
        const rect = canvas.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        let nearest = -1;
        let distance = 14;
        points.forEach((point, index) => {
          const current = Math.hypot(point.x - x, point.y - y);
          if (current < distance) { distance = current; nearest = index; }
        });
        if (nearest >= 0) {
          selectedIndex = nearest;
          renderSelectedRoot(element, response, selectedIndex);
          redraw();
        }
      });
      canvas.addEventListener("mousemove", event => {
        points = canvas.__e8Points || [];
        if (!points.length) return;
        const rect = canvas.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        let nearest = -1;
        let distance = 14;
        points.forEach((point, index) => {
          const current = Math.hypot(point.x - x, point.y - y);
          if (current < distance) { distance = current; nearest = index; }
        });
        setHover(nearest);
        canvas.title = nearest >= 0 ? `root ${nearest + 1}: ${formatRoot(response.roots[nearest])}` : "";
      });
      canvas.addEventListener("mouseleave", () => {
        setHover(-1);
        canvas.removeAttribute("title");
      });
      if (typeof ResizeObserver !== "undefined") {
        new ResizeObserver(() => {
          redraw();
        }).observe(canvas);
      }
      await run();
    });
  }

  function formatRoot(root) {
    return root.numerators.map(value => root.denominator === 1 ? String(value) : `${value}/${root.denominator}`).join(", ");
  }
  function renderResponse(element, response, canvas) {
    element.querySelector("[data-e8-selected]").textContent = response.selectedCount;
    element.querySelector("[data-e8-total]").textContent = `${response.integralCount} + ${response.halfIntegralCount} = ${response.totalCount}`;
    element.querySelector("[data-e8-norm]").textContent = response.normSquared;
    const packing = response.packing;
    const radiusAdmissible = response.radiusAdmissible ?? response["radiusAdmissible?"];
    const density = element.querySelector("[data-e8-density]");
    density.replaceChildren();
    const heading = document.createElement("h3"); heading.textContent = "Packing"; density.append(heading);
    addMathText(density, "Maximum radius: ", "\\frac{\\sqrt{2}}{2}");
    addMathText(density, "Density: ", "\\frac{\\pi^4}{384}");
    if (radiusAdmissible != null) addText(density, "Radius: ", radiusAdmissible ? "admissible" : "exceeds threshold");
    renderSelectedRoot(element, response, -1);
    return drawProjection(canvas, response.roots, -1);
  }
  function addText(parent, label, value) {
    const paragraph = document.createElement("p");
    paragraph.append(document.createTextNode(label));
    const strong = document.createElement("strong"); strong.textContent = value;
    paragraph.append(strong); parent.append(paragraph);
  }
  function addMathText(parent, label, value) {
    const paragraph = document.createElement("p");
    paragraph.append(document.createTextNode(label));
    const strong = document.createElement("strong"); strong.textContent = `$${value}$`;
    paragraph.append(strong); parent.append(paragraph);
    renderMathWhenReady(strong);
  }
  function renderMathWhenReady(element, attempts = 0) {
    if (typeof window.renderMathInElement === "function") {
      window.renderMathInElement(element, { delimiters: [{ left: "$", right: "$", display: false }] });
    } else if (attempts < 20) {
      setTimeout(() => renderMathWhenReady(element, attempts + 1), 50);
    }
  }
  function renderSelectedRoot(element, response, index) {
    const container = element.querySelector("[data-e8-root]");
    container.replaceChildren();
    const root = response.roots[index];
    if (!root) {
      const hint = document.createElement("p"); hint.textContent = "Select a point to inspect its exact coordinates."; container.append(hint); return;
    }
    const heading = document.createElement("h3"); heading.textContent = `Root ${index + 1}`; container.append(heading);
    const coordinates = document.createElement("p"); coordinates.className = "e8-coordinates"; coordinates.textContent = `(${formatRoot(root)})`; container.append(coordinates);
    const antipode = response.roots.findIndex(candidate => candidate.family === root.family && candidate.denominator === root.denominator && candidate.numerators.every((value, coordinate) => value === -root.numerators[coordinate]));
    const detail = document.createElement("p"); detail.textContent = `${root.family}; denominator ${root.denominator}; norm squared ${response.normSquared}`; container.append(detail);
    if (antipode >= 0) { const link = document.createElement("button"); link.type = "button"; link.className = "e8-antipode"; link.textContent = "−v  ·  Antipodal root"; link.title = `Show antipodal root ${antipode + 1}`; link.addEventListener("click", () => { renderSelectedRoot(element, response, antipode); drawProjection(element.querySelector("[data-e8-canvas]"), response.roots, antipode); }); container.append(link); }
  }
  function projectedPoint(root, mode, xIndex, yIndex) {
    const values = root.numerators.map(value => value / root.denominator);
    if (mode === "coordinates") return { x: values[xIndex], y: values[yIndex] };
    return { x: values[0] - values[1] + .5 * (values[2] - values[3]), y: values[4] - values[5] + .5 * (values[6] - values[7]) };
  }
  function drawProjection(canvas, roots, selectedIndex, hoverIndex = -1, hoverAmount = 1) {
    const box = canvas.getBoundingClientRect();
    const ratio = window.devicePixelRatio || 1;
    const width = Math.max(box.width, 1), height = Math.max(box.height, 1);
    canvas.width = width * ratio; canvas.height = height * ratio;
    const context = canvas.getContext("2d"); context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.fillStyle = "#f8fbff"; context.fillRect(0, 0, width, height);
    const root = canvas.closest(".e8-computation");
    const mode = root.querySelector("[data-e8-projection]").value;
    const xIndex = Number(root.querySelector("[data-e8-x]")?.value || 0);
    const yIndex = Number(root.querySelector("[data-e8-y]")?.value || 1);
    const raw = roots.map(root => projectedPoint(root, mode, xIndex, yIndex));
    const extent = Math.max(...raw.flatMap(point => [Math.abs(point.x), Math.abs(point.y)]), 1);
    const scale = Math.min(width, height) * .42 / extent;
    const points = raw.map((point, index) => ({ x: width / 2 + point.x * scale + ((index * 17) % 5 - 2) * .7, y: height / 2 - point.y * scale + ((index * 11) % 5 - 2) * .7 }));
    context.strokeStyle = "#cbd5e1"; context.beginPath(); context.moveTo(width / 2, 0); context.lineTo(width / 2, height); context.moveTo(0, height / 2); context.lineTo(width, height / 2); context.stroke();
    // Draw families in separate passes so overlapping roots retain their color cues.
    ["integral", "halfIntegral"].forEach(family => points.forEach((point, index) => {
      const root = roots[index];
      if ((root.family === "halfIntegral" ? "halfIntegral" : "integral") !== family) return;
      const selected = selectedIndex === index;
      const hovered = hoverIndex === index;
      const active = selected || hovered;
      context.fillStyle = family === "integral" ? "#176b87" : "#54a87a";
      context.globalAlpha = selectedIndex >= 0 && !selected && !hovered ? .3 : .82;
      if (hovered && hoverAmount > 0) { context.globalAlpha = .12 * hoverAmount; context.beginPath(); context.arc(point.x, point.y, 12 + 5 * hoverAmount, 0, Math.PI * 2); context.fill(); }
      context.globalAlpha = selectedIndex >= 0 && !selected && !hovered ? .3 : .82;
      context.beginPath();
      const size = active ? (selected ? 6.5 : 4.5 + 1.5 * hoverAmount) : 4.1;
      if (family === "halfIntegral") { context.moveTo(point.x, point.y - size); context.lineTo(point.x + size, point.y); context.lineTo(point.x, point.y + size); context.lineTo(point.x - size, point.y); context.closePath(); } else { context.arc(point.x, point.y, size, 0, Math.PI * 2); }
      context.fill();
      if (active) { context.strokeStyle = "#123f52"; context.globalAlpha = selected ? 1 : .75 * hoverAmount; context.lineWidth = 1.5; context.stroke(); }
    }));
    context.globalAlpha = 1;
    canvas.__e8Points = points;
    return points;
  }
  register();
})();

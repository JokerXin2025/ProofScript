(function () {
  "use strict";

  const IDS = {
    scaling: "proofscript/packing-scaling-instance-v1",
    periodic: "proofscript/periodic-density-instance-v1",
    eisenstein: "proofscript/eisenstein-coefficient-v1",
  };
  const safeInteger = value => Number.isSafeInteger(value) && value >= 0;
  const formatRatio = value => value.denominator === 1 ? String(value.numerator) : `${value.numerator}/${value.denominator}`;
  const ratio = (numerator, denominator) => ({ numerator, denominator });

  function versionOk(component) {
    return String(component.payload?.contractVersion || "").split(".")[0] === "1";
  }
  function readInteger(input, positive = false) {
    const value = Number(input.value);
    if (!safeInteger(value) || (positive && value === 0)) throw new Error("v1 JSON integer range exceeded or integer must be positive");
    return value;
  }
  function powerFits(value, exponent) {
    let result = 1n;
    const limit = BigInt(Number.MAX_SAFE_INTEGER);
    for (let index = 0; index < exponent; index += 1) {
      result *= BigInt(value);
      if (result > limit) return false;
    }
    return true;
  }
  function addText(parent, label, value) {
    const paragraph = document.createElement("p");
    paragraph.append(document.createTextNode(label));
    const strong = document.createElement("strong");
    strong.textContent = String(value);
    paragraph.append(strong);
    parent.append(paragraph);
  }
  function addMath(parent, label, value) {
    const paragraph = document.createElement("p");
    paragraph.append(document.createTextNode(label));
    const strong = document.createElement("strong");
    strong.textContent = `$${value}$`;
    paragraph.append(strong);
    parent.append(paragraph);
    renderMath(strong);
  }
  function renderEisensteinFormula(output, value) {
    const equations = document.createElement("div");
    equations.className = "formula-equations";
    addMath(equations, "", `\\sigma_{${value.sigmaExponent}}(${value.index})=${value.divisorPowerSum}`);
    addMath(equations, "", `\\operatorname{multiplier}(${value.series})=${value.multiplier}`);
    const left = value.index === 0 ? `\\operatorname{coeff}_0(${value.series})` : `\\operatorname{coeff}_{${value.index}}(${value.series})`;
    const right = value.index === 0 ? "1" : `${value.multiplier}\\cdot\\sigma_{${value.sigmaExponent}}(${value.index})=${value.coefficient}`;
    addMath(equations, "", `${left}=${right}`);
    output.append(equations);
  }
  function renderMath(node, attempts = 0) {
    if (typeof window.renderMathInElement === "function") {
      window.renderMathInElement(node, { delimiters: [{ left: "$", right: "$", display: false }] });
    } else if (attempts < 20) {
      setTimeout(() => renderMath(node, attempts + 1), 80);
    }
  }
  function inputField(parent, label, value) {
    const wrapper = document.createElement("label");
    wrapper.className = "formula-field";
    wrapper.append(document.createTextNode(label));
    const input = document.createElement("input");
    input.type = "number";
    input.min = "0";
    input.step = "1";
    input.value = value;
    input.inputMode = "numeric";
    wrapper.append(input);
    parent.append(wrapper);
    return input;
  }
  function createShell(element, title) {
    const root = document.createElement("div");
    root.className = "formula-instance";
    const heading = document.createElement("h3");
    heading.textContent = title;
    root.append(heading);
    const form = document.createElement("div");
    form.className = "formula-form";
    const output = document.createElement("div");
    output.className = "formula-output";
    output.setAttribute("aria-live", "polite");
    root.append(form, output);
    element.replaceChildren(root);
    return { form, output };
  }
  function attach(component, compute, element, setup) {
    if (!versionOk(component)) throw new Error("Unsupported computation contract version");
    const ui = setup();
    let requestId = 0;
    async function run() {
      const current = ++requestId;
      try {
        const input = ui.read();
        element.dataset.loading = "true";
        const result = await compute(input);
        if (current !== requestId) return;
        if (!result.ok) throw new Error(result.error.message);
        ui.render(result.value);
      } catch (error) {
        if (current === requestId) ui.error(error.message || String(error));
      } finally {
        if (current === requestId) delete element.dataset.loading;
      }
    }
    ui.listen(run);
    return run();
  }
  function showError(output, message) {
    output.replaceChildren();
    const paragraph = document.createElement("p");
    paragraph.className = "formula-error";
    paragraph.textContent = message;
    output.append(paragraph);
  }
  function ratioFields(form, prefix, value) {
    return {
      numerator: inputField(form, `${prefix} numerator`, value.numerator),
      denominator: inputField(form, `${prefix} denominator`, value.denominator),
    };
  }
  function readRatio(fields) {
    return ratio(readInteger(fields.numerator, true), readInteger(fields.denominator, true));
  }

  function register() {
    if (!window.PS4HTMLComputation) return;
    window.PS4HTMLComputation.register(IDS.scaling, ({ component, compute, element }) => attach(component, compute, element, () => {
      const defaults = component.payload.defaultInput;
      const shell = createShell(element, "Packing scaling instance");
      const fields = {
        dimension: inputField(shell.form, "Dimension", defaults.dimension),
        separation: ratioFields(shell.form, "Separation", defaults.separation),
        scale: ratioFields(shell.form, "Scale", defaults.scale),
        observationRadius: ratioFields(shell.form, "Observation radius", defaults.observationRadius),
      };
      return {
        read: () => {
          const dimension = readInteger(fields.dimension, true);
          const scale = readRatio(fields.scale);
          if (!powerFits(scale.numerator, dimension) || !powerFits(scale.denominator, dimension)) throw new Error("v1 JSON integer range exceeded");
          return { dimension, separation: readRatio(fields.separation), scale, observationRadius: readRatio(fields.observationRadius) };
        },
        listen: run => Object.values(fields).flatMap(field => field.numerator ? [field.numerator, field.denominator] : [field]).forEach(input => input.addEventListener("change", run)),
        error: message => showError(shell.output, message),
        render: value => { shell.output.replaceChildren(); const cards = document.createElement("div"); cards.className = "formula-card-grid"; addText(cards, "Scaled separation: ", formatRatio(value.scaledSeparation)); addText(cards, "Original ball radius: ", formatRatio(value.originalBallRadius)); addText(cards, "Scaled ball radius: ", formatRatio(value.scaledBallRadius)); addText(cards, "Scaled observation radius: ", formatRatio(value.scaledObservationRadius)); addText(cards, "Volume scale factor: ", formatRatio(value.volumeScaleFactor)); shell.output.append(cards); addMath(shell.output, "Density cancellation: ", "\\frac{c^d\\cdot\\text{covered volume}}{c^d\\cdot\\text{observation volume}}=\\delta_R(S)"); addText(shell.output, "Density preserved: ", value.densityPreserved ? "yes" : "no"); addText(shell.output, "Conclusion: ", value.instantiatedConclusion); },
      };
    }));

    window.PS4HTMLComputation.register(IDS.periodic, ({ component, compute, element }) => attach(component, compute, element, () => {
      const defaults = component.payload.defaultInput;
      const shell = createShell(element, "Periodic density instance");
      const fields = { dimension: inputField(shell.form, "Dimension", defaults.dimension), numReps: inputField(shell.form, "Number of center orbits", defaults.numReps), separationSquared: ratioFields(shell.form, "Separation squared", defaults.separationSquared), covolume: ratioFields(shell.form, "Covolume", defaults.covolume) };
      return {
        read: () => ({ dimension: readInteger(fields.dimension, true), numReps: readInteger(fields.numReps, true), separationSquared: readRatio(fields.separationSquared), covolume: readRatio(fields.covolume) }),
        listen: run => Object.values(fields).flatMap(field => field.numerator ? [field.numerator, field.denominator] : [field]).forEach(input => input.addEventListener("change", run)),
        error: message => showError(shell.output, message),
        render: value => { shell.output.replaceChildren(); addMath(shell.output, "Half dimension: ", `k=${value.halfDimension}`); addMath(shell.output, "Radius squared: ", `r^2=${formatRatio(value.radiusSquared)}`); addMath(shell.output, "Ball volume: ", `${formatRatio(value.ballVolumeCoefficient)}\\pi^{${value.piExponent}}`); addMath(shell.output, "Exact density: ", `${formatRatio(value.densityCoefficient)}\\pi^{${value.piExponent}}`); addText(shell.output, "Conclusion: ", value.instantiatedConclusion); },
      };
    }));

    window.PS4HTMLComputation.register(IDS.eisenstein, ({ component, compute, element }) => attach(component, compute, element, () => {
      const defaults = component.payload.defaultInput;
      const shell = createShell(element, "Eisenstein coefficient");
      const series = document.createElement("div");
      series.className = "formula-segmented";
      let selectedSeries = defaults.series;
      const buttons = ["E4", "E6"].map(value => { const button = document.createElement("button"); button.type = "button"; button.textContent = value; button.setAttribute("aria-pressed", String(value === selectedSeries)); button.addEventListener("click", () => { selectedSeries = value; buttons.forEach(item => item.setAttribute("aria-pressed", String(item === button))); if (run) void run(); }); series.append(button); return button; });
      shell.form.append(series);
      const index = inputField(shell.form, "Index", defaults.index);
      let run;
      const ui = { read: () => { const value = readInteger(index); if (value > 256) throw new Error("v1 JSON integer range exceeded; use an index at most 256"); return { series: selectedSeries, index: value }; }, listen: callback => { run = callback; index.addEventListener("change", callback); }, error: message => showError(shell.output, message), render: value => { shell.output.replaceChildren(); const table = document.createElement("table"); const caption = document.createElement("caption"); caption.textContent = "Divisor contributions from Lean"; table.append(caption); const head = document.createElement("thead"); const row = document.createElement("tr"); ["divisor", "power"].forEach(label => { const cell = document.createElement("th"); cell.textContent = label; row.append(cell); }); head.append(row); table.append(head); const body = document.createElement("tbody"); value.divisors.forEach(item => { const itemRow = document.createElement("tr"); [item.divisor, item.power].forEach(number => { const cell = document.createElement("td"); cell.textContent = String(number); itemRow.append(cell); }); body.append(itemRow); }); table.append(body); shell.output.append(table); renderEisensteinFormula(shell.output, value); } };
      return ui;
    }));
  }
  register();
})();

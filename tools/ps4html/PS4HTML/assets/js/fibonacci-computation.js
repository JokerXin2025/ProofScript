(function () {
  "use strict";

  function register() {
    if (!window.PS4HTMLComputation) return;
    window.PS4HTMLComputation.register("proofscript/fibonacci-calculator-v1", async ({ component, compute, element }) => {
      const payload = component.payload || {};
      const control = payload.controls?.n || {};
      const min = Number.isInteger(control.min) ? control.min : 0;
      const max = Number.isInteger(control.max) ? control.max : 40;
      const step = Number.isInteger(control.step) ? control.step : 1;
      const initial = Math.min(max, Math.max(min, Number(payload.defaultInput?.n ?? 10)));

      const inputId = `fibonacci-${crypto.randomUUID()}`;
      element.innerHTML = `
        <div class="fibonacci-computation">
          <div class="fibonacci-summary">
            <div class="fibonacci-control">
              <label for="${inputId}">Sequence index <strong data-fibonacci-n></strong></label>
              <input id="${inputId}" data-fibonacci-input type="range" min="${min}" max="${max}" step="${step}" value="${initial}">
              <div class="fibonacci-range"><span>${min}</span><span>${max}</span></div>
            </div>
            <output class="fibonacci-value" aria-live="polite"><span>F(<b data-fibonacci-output-n></b>)</span><strong data-fibonacci-value>...</strong></output>
          </div>
          <div class="fibonacci-chart" data-fibonacci-chart aria-label="Fibonacci prefix sequence"></div>
          <div class="fibonacci-footer"><span data-fibonacci-message>Preparing Lean/Wasm...</span><span data-fibonacci-timing></span></div>
        </div>`;

      const input = element.querySelector("[data-fibonacci-input]");
      const currentN = element.querySelector("[data-fibonacci-n]");
      const outputN = element.querySelector("[data-fibonacci-output-n]");
      const output = element.querySelector("[data-fibonacci-value]");
      const chart = element.querySelector("[data-fibonacci-chart]");
      const message = element.querySelector("[data-fibonacci-message]");
      const timing = element.querySelector("[data-fibonacci-timing]");
      let requestedN = initial;
      let computing = false;

      function fitValue() {
        output.style.fontSize = "";
        const available = output.clientWidth;
        const required = output.scrollWidth;
        if (available > 0 && required > available) {
          const maximum = Number.parseFloat(getComputedStyle(output).fontSize);
          output.style.fontSize = `${Math.max(30, maximum * available / required)}px`;
        }
      }

      new ResizeObserver(fitValue).observe(output);

      function requestUpdate() {
        requestedN = Number(input.value);
        currentN.textContent = `n = ${requestedN}`;
        if (!computing) void runLatest();
      }

      async function runLatest() {
        computing = true;
        element.dataset.loading = "true";
        try {
          while (true) {
            const n = requestedN;
            message.textContent = "Computing in Lean/Wasm...";
            const started = performance.now();
            try {
              const result = await compute({ n });
              if (n !== requestedN) continue;
              timing.textContent = `${(performance.now() - started).toFixed(1)} ms`;
              if (!result.ok) {
                message.textContent = result.error.message;
                element.dataset.error = "true";
              } else {
                delete element.dataset.error;
                outputN.textContent = result.value.n;
                output.textContent = result.value.value.toLocaleString();
                fitValue();
                message.textContent = "Computed by Lean/Wasm";
                renderBars(chart, result.value.sequence);
              }
            } catch (error) {
              if (n === requestedN) {
                message.textContent = error.message;
                element.dataset.error = "true";
              }
            }
            if (n === requestedN) break;
          }
        } finally {
          computing = false;
          delete element.dataset.loading;
        }
      }

      input.addEventListener("input", requestUpdate);
      currentN.textContent = `n = ${initial}`;
      await runLatest();
    });
  }

  function renderBars(chart, sequence) {
    const maximum = Math.max(...sequence, 1);
    chart.replaceChildren(...sequence.map((value, index) => {
      const item = document.createElement("div");
      item.className = "fibonacci-bar-item";
      const bar = document.createElement("span");
      bar.className = "fibonacci-bar";
      bar.style.height = `${Math.max(3, Math.sqrt(value / maximum) * 100)}%`;
      bar.title = `F(${index}) = ${value}`;
      const label = document.createElement("small");
      label.textContent = value.toLocaleString();
      item.append(bar, label);
      return item;
    }));
  }

  register();
})();

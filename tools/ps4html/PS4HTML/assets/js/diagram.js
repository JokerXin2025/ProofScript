document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.diagram-figure .diagram-zoom').forEach(input => {
        const figure = input.closest('.diagram-figure');
        const svg = figure.querySelector('.diagram-zoom-stage svg');
        if (!svg) return;

        // LaTeX SVGs provide physical dimensions (usually pt). Retaining those units
        // lets the browser scale the layout box as well as the drawing itself.
        const width = svg.getAttribute('width') || `${svg.viewBox.baseVal.width}px`;
        const height = svg.getAttribute('height') || `${svg.viewBox.baseVal.height}px`;
        const label = figure.querySelector('.diagram-zoom-value');
        const update = () => {
            const scale = Number(input.value) / 100;
            svg.style.width = `calc(${width} * ${scale})`;
            svg.style.height = `calc(${height} * ${scale})`;
            label.textContent = `${input.value}%`;
        };
        input.addEventListener('input', update);
        update();
    });
});

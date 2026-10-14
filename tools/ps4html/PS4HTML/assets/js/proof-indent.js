document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.proof-indent-slider').forEach(input => {
        updateProofIndent(input);
        input.addEventListener('input', () => updateProofIndent(input));
    });
});

function updateProofIndent(input) {
    const proof = input.closest('.theorem-proof');
    if (!proof) return;

    const indent = Number(input.value);
    const inset = indent * 3 / 5;
    proof.style.setProperty('--proof-indent', `${indent}px`);
    proof.style.setProperty('--proof-inset', `${inset}px`);

    const value = input.closest('.proof-indent-control')?.querySelector('.proof-indent-value');
    if (value) value.textContent = indent;
}

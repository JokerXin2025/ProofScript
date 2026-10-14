document.addEventListener('DOMContentLoaded', () => {
    const minimumCodeHeight = 300;

    document.querySelectorAll('.theorem-proof, .page-media-latex, .proof-text-card').forEach(card => {
        const inner = card.querySelector('.proof-flip-inner');
        const button = card.querySelector('.flip-btn');
        if (!inner || !button) return;

        button.addEventListener('click', () => {
            const flipped = !inner.classList.contains('flipped');
            if (flipped) {
                const frontHeight = inner.getBoundingClientRect().height;
                inner.dataset.frontHeight = String(frontHeight);
                inner.style.height = `${frontHeight}px`;
                inner.getBoundingClientRect();
                inner.classList.add('flipped');
                card.classList.add('is-flipped');
                requestAnimationFrame(() => {
                    inner.style.height = `${Math.max(frontHeight, minimumCodeHeight)}px`;
                });
            } else {
                const frontHeight = Number(inner.dataset.frontHeight);
                inner.classList.remove('flipped');
                card.classList.remove('is-flipped');
                inner.style.height = `${frontHeight || inner.scrollHeight}px`;
                window.setTimeout(() => {
                    if (!inner.classList.contains('flipped')) {
                        inner.style.height = '';
                        delete inner.dataset.frontHeight;
                    }
                }, 550);
            }
            button.innerHTML = flipped
                ? '<i class="codicon codicon-file-symlink-file"></i>'
                : '<i class="codicon codicon-file-code"></i>';
            button.title = flipped
                ? (button.dataset.backTitle || '返回证明')
                : (button.dataset.frontTitle || '查看 Lean 源码');
        });

        inner.addEventListener('transitionend', event => {
            if (event.propertyName === 'height' && !inner.classList.contains('flipped')) {
                inner.style.height = '';
                delete inner.dataset.frontHeight;
            }
        });
    });
});

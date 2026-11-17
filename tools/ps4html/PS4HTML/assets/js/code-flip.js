document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.theorem-proof, .page-media-latex, .proof-text-card').forEach(card => {
        const inner = card.querySelector('.proof-flip-inner');
        const button = card.querySelector('.flip-btn');
        if (!inner || !button) return;
        const front = inner.querySelector(':scope > .proof-flip-front');
        const back = inner.querySelector(':scope > .proof-flip-back');
        if (!front || !back) return;

        // The reverse side is absolutely positioned, so measure its natural content height.
        const syncHeight = () => {
            if (inner.classList.contains('flipped') && inner.getBoundingClientRect().width) {
                const height = back.getBoundingClientRect().height;
                if (height && Math.abs(inner.getBoundingClientRect().height - height) > 1) {
                    inner.style.height = `${height}px`;
                    document.dispatchEvent(new Event('ps4html:layoutchange'));
                }
            }
        };
        if (window.ResizeObserver) {
            new ResizeObserver(syncHeight).observe(back);
        }
        window.addEventListener('resize', syncHeight);

        button.addEventListener('click', () => {
            const flipped = !inner.classList.contains('flipped');
            const currentHeight = inner.getBoundingClientRect().height;
            inner.style.height = `${currentHeight}px`;
            inner.getBoundingClientRect();
            if (flipped) {
                inner.classList.add('flipped');
                card.classList.add('is-flipped');
            } else {
                inner.classList.remove('flipped');
                card.classList.remove('is-flipped');
            }
            requestAnimationFrame(() => {
                if (inner.classList.contains('flipped') !== flipped) return;
                const targetHeight = flipped ? back.getBoundingClientRect().height : front.getBoundingClientRect().height;
                if (!flipped && Math.abs(currentHeight - targetHeight) < 1) {
                    inner.style.height = '';
                } else {
                    inner.style.height = `${targetHeight}px`;
                }
                document.dispatchEvent(new Event('ps4html:layoutchange'));
            });
            button.innerHTML = flipped
                ? '<i class="codicon codicon-file-symlink-file"></i>'
                : '<i class="codicon codicon-file-code"></i>';
            button.title = flipped
                ? (button.dataset.backTitle || '返回证明')
                : (button.dataset.frontTitle || '查看 Lean 源码');
            document.dispatchEvent(new Event('ps4html:layoutchange'));
        });

        inner.addEventListener('transitionend', event => {
            if (event.target !== inner || event.propertyName !== 'height') return;
            if (!inner.classList.contains('flipped')) {
                inner.style.height = '';
            }
            document.dispatchEvent(new Event('ps4html:layoutchange'));
        });
    });
});

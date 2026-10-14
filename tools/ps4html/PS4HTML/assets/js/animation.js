document.addEventListener (
    'DOMContentLoaded', () => {
        const blocks = document.querySelectorAll('.step-block');
        let currentParent = null;
        let currentIndex = 1;
        blocks.forEach (
            block => {
                if (block.parentElement !== currentParent) {
                    currentParent = block.parentElement;
                    currentIndex = 1;
                }
                block.style.setProperty('--step-idx', currentIndex);
                currentIndex++;
            }
        );
    }
);
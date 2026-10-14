document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.reference-item').forEach((item, index) => {
        const trigger = item.querySelector(':scope > summary .reference-info');
        const dialog = item.querySelector(':scope > .reference-info-dialog');

        if (!trigger || !(dialog instanceof HTMLDialogElement)) return;

        if (!dialog.id) dialog.id = `reference-info-dialog-${index + 1}`;
        trigger.removeAttribute('onclick');
        trigger.setAttribute('aria-controls', dialog.id);
        trigger.setAttribute('aria-haspopup', 'dialog');

        if (trigger instanceof HTMLButtonElement) {
            trigger.type = 'button';
        } else {
            trigger.setAttribute('role', 'button');
            trigger.tabIndex = 0;
        }

        const openDialog = event => {
            event.preventDefault();
            event.stopPropagation();
            if (!dialog.open) dialog.showModal();
        };

        trigger.addEventListener('click', openDialog);
        trigger.addEventListener('keydown', event => {
            if (event.key === 'Enter' || event.key === ' ') openDialog(event);
        });

        dialog.querySelectorAll('.reference-info-dialog-close').forEach(button => {
            button.addEventListener('click', event => {
                if (!button.closest('form[method="dialog"]')) {
                    event.preventDefault();
                    dialog.close();
                }
            });
        });

        dialog.addEventListener('click', event => {
            if (event.target !== dialog) return;

            const rect = dialog.getBoundingClientRect();
            const inside = event.clientX >= rect.left && event.clientX <= rect.right
                && event.clientY >= rect.top && event.clientY <= rect.bottom;
            if (!inside) dialog.close();
        });

        // A modal must not remain inside a closed <details> subtree.
        document.body.append(dialog);
    });
});
